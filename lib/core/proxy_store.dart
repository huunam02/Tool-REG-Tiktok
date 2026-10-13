import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app_configuration.dart';
import 'desktop_user_agents.dart';

class ProxyProfile {
  const ProxyProfile(
      {required this.proxy,
      required this.userAgent,
      this.name = '',
      this.hasBeenUsed = false});

  final WebViewProxy proxy;
  final String userAgent;
  final String name;
  final bool hasBeenUsed;
}

class SavedProxy extends ProxyProfile {
  const SavedProxy({
    required this.id,
    required super.name,
    required super.proxy,
    required super.userAgent,
    super.hasBeenUsed,
  });

  final int id;
}

bool sameProxy(WebViewProxy? first, WebViewProxy? second) =>
    first?.uri == second?.uri &&
    first?.username == second?.username &&
    first?.password == second?.password;

// Uri.toString() omits default ports (80/443), but our input parser requires one.
String proxyAddress(WebViewProxy proxy) {
  final host =
      proxy.uri.host.contains(':') ? '[${proxy.uri.host}]' : proxy.uri.host;
  return '${proxy.uri.scheme}://$host:${proxy.uri.port}';
}

/// The current configuration is stored separately from the named proxy list.
/// Removing a list entry therefore keeps the user's current connection intact.
class ProxyStore {
  ProxyStore({
    DatabaseFactory? factory,
    String? databasePath,
    Future<String> Function()? selectUserAgent,
  })  : _factory = factory,
        _databasePath = databasePath,
        _selectUserAgent = selectUserAgent ?? selectNextDesktopUserAgent;

  static final instance = ProxyStore();
  final DatabaseFactory? _factory;
  final String? _databasePath;
  final Future<String> Function() _selectUserAgent;
  Future<Database>? _opening;

  Future<Database> get _database => _opening ??= _open();

  Future<String> generateUserAgent() => _selectUserAgent();

  Future<Database> _open() async {
    Database? db;
    try {
      final factory = _factory ?? databaseFactory;
      final filename = _databasePath ??
          path.join(await factory.getDatabasesPath(), 'proxies.db');
      db = await factory.openDatabase(filename,
          options: OpenDatabaseOptions(
              version: 3,
              onCreate: (db, _) async {
                await db.execute('''
          CREATE TABLE proxies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            user_agent TEXT NOT NULL,
            has_been_used INTEGER NOT NULL DEFAULT 0 CHECK (has_been_used IN (0, 1))
          )
        ''');
                await db.execute('''
          CREATE TABLE current_proxy (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            url TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            user_agent TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT ''
          )
        ''');
              },
              onUpgrade: (db, oldVersion, _) async {
                if (oldVersion < 2) {
                  for (final table in ['proxies', 'current_proxy']) {
                    await db.execute(
                        "ALTER TABLE $table ADD COLUMN user_agent TEXT NOT NULL DEFAULT ''");
                  }
                }
                if (oldVersion < 3) {
                  await db.execute(
                      'ALTER TABLE proxies ADD COLUMN has_been_used INTEGER NOT NULL DEFAULT 0 CHECK (has_been_used IN (0, 1))');
                  await db.execute(
                      "ALTER TABLE current_proxy ADD COLUMN name TEXT NOT NULL DEFAULT ''");
                }
              }));
      await db.transaction((txn) async {
        await _backfillUserAgents(txn);
        final current = await txn.query('current_proxy');
        if (current.isEmpty) return;
        final row = current.single;
        final matches = await txn.query('proxies',
            where:
                'url = ? AND username = ? AND password = ? AND user_agent = ?',
            whereArgs: [
              row['url'],
              row['username'],
              row['password'],
              row['user_agent']
            ],
            orderBy: 'id ASC',
            limit: 1);
        if (matches.isEmpty) return;
        await txn.update('proxies', {'has_been_used': 1},
            where: 'id = ?', whereArgs: [matches.single['id']]);
        if ((row['name'] as String).isEmpty) {
          await txn.update('current_proxy', {'name': matches.single['name']});
        }
      });
      return db;
    } catch (_) {
      await db?.close();
      _opening = null;
      rethrow;
    }
  }

  Future<void> _backfillUserAgents(Transaction txn) async {
    final entries = await txn.query('proxies', where: "user_agent = ''");
    for (final entry in entries) {
      await txn.update('proxies', {'user_agent': await _selectUserAgent()},
          where: 'id = ?', whereArgs: [entry['id']]);
    }
    final current = await txn.query('current_proxy', where: "user_agent = ''");
    if (current.isEmpty) return;
    final proxy = _readProxy(current.single);
    final saved = await _findSaved(txn, proxy);
    final userAgent =
        saved?['user_agent'] as String? ?? await _selectUserAgent();
    // Preserve a legacy cached proxy as a manageable list entry.
    if (saved == null) {
      await txn.insert('proxies', {
        'name': proxyAddress(proxy),
        ..._values(proxy),
        'user_agent': userAgent,
      });
    }
    await txn.update('current_proxy', {'user_agent': userAgent});
  }

  static Future<Map<String, Object?>?> _findSaved(
      DatabaseExecutor db, WebViewProxy proxy) async {
    final rows = await db.query('proxies',
        where: 'url = ? AND username = ? AND password = ?',
        whereArgs: [proxyAddress(proxy), proxy.username, proxy.password],
        orderBy: 'id ASC',
        limit: 1);
    return rows.isEmpty ? null : rows.single;
  }

  Future<String> _userAgentFor(DatabaseExecutor db, WebViewProxy proxy) async {
    final saved = await _findSaved(db, proxy);
    if (saved != null) return saved['user_agent'] as String;
    final current = await db.query('current_proxy');
    if (current.isNotEmpty && sameProxy(_readProxy(current.single), proxy)) {
      return current.single['user_agent'] as String;
    }
    return _selectUserAgent();
  }

  static Map<String, Object?> _values(WebViewProxy proxy) => {
        'url': proxyAddress(proxy),
        'username': proxy.username,
        'password': proxy.password,
      };

  static WebViewProxy _readProxy(Map<String, Object?> row) =>
      WebViewProxy.parse(row['url'] as String,
          username: row['username'] as String,
          password: row['password'] as String)!;

  Future<WebViewProxy?> getCurrent() async {
    return (await getCurrentProfile())?.proxy;
  }

  Future<ProxyProfile?> getCurrentProfile() async {
    final rows = await (await _database).query('current_proxy');
    return rows.isEmpty
        ? null
        : ProxyProfile(
            proxy: _readProxy(rows.single),
            userAgent: rows.single['user_agent'] as String,
            name: rows.single['name'] as String,
            hasBeenUsed: true);
  }

  Future<void> setCurrent(WebViewProxy? proxy) async {
    final db = await _database;
    if (proxy == null) {
      await db.delete('current_proxy');
    } else {
      await db.transaction((txn) async {
        final userAgent = await _userAgentFor(txn, proxy);
        final saved = await _findSaved(txn, proxy);
        await txn.insert(
            'current_proxy',
            {
              'id': 1,
              ..._values(proxy),
              'user_agent': userAgent,
              'name': saved?['name'] ?? '',
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (saved != null) {
          await txn.update('proxies', {'has_been_used': 1},
              where: 'id = ?', whereArgs: [saved['id']]);
        }
      });
    }
  }

  Future<void> useSaved(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query('proxies', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Proxy no longer exists');
      final row = rows.single;
      await txn.insert(
          'current_proxy',
          {
            'id': 1,
            'url': row['url'],
            'username': row['username'],
            'password': row['password'],
            'user_agent': row['user_agent'],
            'name': row['name'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update('proxies', {'has_been_used': 1},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<SavedProxy>> list() async {
    final rows = await (await _database).query('proxies', orderBy: 'id DESC');
    return rows
        .map((row) => SavedProxy(
            id: row['id'] as int,
            name: row['name'] as String,
            proxy: _readProxy(row),
            userAgent: row['user_agent'] as String,
            hasBeenUsed: row['has_been_used'] == 1))
        .toList();
  }

  Future<int> save(
      {int? id,
      required String name,
      required WebViewProxy proxy,
      String? userAgent}) async {
    final requestedUserAgent = userAgent?.trim();
    if (requestedUserAgent != null &&
        (requestedUserAgent.isEmpty ||
            RegExp(r'[\r\n]').hasMatch(requestedUserAgent))) {
      throw const FormatException('Nhập User-Agent hợp lệ trên một dòng.');
    }
    final db = await _database;
    return db.transaction((txn) async {
      final values = {
        'name': name.trim().isEmpty ? proxyAddress(proxy) : name.trim(),
        ..._values(proxy),
        if (requestedUserAgent != null) 'user_agent': requestedUserAgent,
      };
      if (id != null) {
        final updated = await txn
            .update('proxies', values, where: 'id = ?', whereArgs: [id]);
        if (updated == 0) throw StateError('Proxy no longer exists');
        return id;
      }
      final existing = await _findSaved(txn, proxy);
      if (existing != null) {
        final existingId = existing['id'] as int;
        await txn.update('proxies', values,
            where: 'id = ?', whereArgs: [existingId]);
        return existingId;
      }
      final selectedUserAgent =
          requestedUserAgent ?? await _userAgentFor(txn, proxy);
      return txn
          .insert('proxies', {...values, 'user_agent': selectedUserAgent});
    });
  }

  Future<void> delete(int id) async {
    await (await _database).delete('proxies', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setUsed(int id, bool used) async {
    final updated = await (await _database).update(
        'proxies', {'has_been_used': used ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    if (updated == 0) throw StateError('Proxy no longer exists');
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
