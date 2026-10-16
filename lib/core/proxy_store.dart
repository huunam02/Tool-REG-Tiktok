import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app_configuration.dart';
import 'configuration_data.dart';
import 'proxy_draft.dart';
import 'desktop_user_agents.dart';
import 'chrome_user_agent.dart';
import 'proxy_time_zone.dart';
import 'nurture_store.dart';

class ProxyProfile {
  const ProxyProfile({
    required this.proxy,
    required this.userAgent,
    this.name = '',
    this.hasBeenUsed = false,
    this.account,
    this.statusAccount = AccountStatus.unregistered,
    this.configurationId,
    this.timeZoneId = '',
  });

  final WebViewProxy? proxy;
  final String userAgent;
  final String name;
  final bool hasBeenUsed;
  final AccountCredentials? account;
  final AccountStatus statusAccount;
  final int? configurationId;
  final String timeZoneId;

  ProxyProfile copyWith({String? userAgent, String? timeZoneId}) =>
      ProxyProfile(
        proxy: proxy,
        userAgent: userAgent ?? this.userAgent,
        timeZoneId: timeZoneId ?? this.timeZoneId,
        name: name,
        hasBeenUsed: hasBeenUsed,
        account: account,
        statusAccount: statusAccount,
        configurationId: configurationId,
      );
}

class SavedProxy extends ProxyProfile {
  const SavedProxy({
    required this.id,
    required super.name,
    required super.proxy,
    required super.userAgent,
    super.hasBeenUsed,
    super.account,
    super.statusAccount,
    super.timeZoneId,
  }) : super(configurationId: id);
  final int id;
}

bool sameProxy(WebViewProxy? first, WebViewProxy? second) =>
    first?.uri == second?.uri &&
    first?.username == second?.username &&
    first?.password == second?.password;

bool sameProfile(ProxyProfile? first, ProxyProfile? second) =>
    sameProxy(first?.proxy, second?.proxy) &&
    first?.userAgent == second?.userAgent &&
    first?.timeZoneId == second?.timeZoneId &&
    sameAccount(first?.account, second?.account);

String proxyAddress(WebViewProxy proxy) {
  final host = proxy.uri.host.contains(':')
      ? '[${proxy.uri.host}]'
      : proxy.uri.host;
  return '${proxy.uri.scheme}://$host:${proxy.uri.port}';
}

String proxyLabel(WebViewProxy? proxy) =>
    proxy == null ? 'Mặc định của máy' : proxyAddress(proxy);

/// All configurations and the active selection live in one table.
/// An unlisted active row preserves the selected snapshot when its saved entry
/// is edited or deleted. It is removed when another configuration is selected.
class ProxyStore {
  ProxyStore({
    DatabaseFactory? factory,
    String? databasePath,
    Future<String> Function()? selectUserAgent,
  }) : _factory = factory,
       _databasePath = databasePath,
       _selectUserAgent = selectUserAgent ?? selectNextDesktopUserAgent;

  static final instance = ProxyStore();
  final DatabaseFactory? _factory;
  final String? _databasePath;
  final Future<String> Function() _selectUserAgent;
  Future<Database>? _opening;
  Future<Database> get _database => _opening ??= _open();
  NurtureRepository? _nurture;
  NurtureRepository get nurture =>
      _nurture ??= SqliteNurtureRepository(() => _database);
  Future<String> generateUserAgent() async =>
      normalizeDesktopUserAgentForPlatform(await _selectUserAgent());

  static Future<void> _createSchema(Database db) async {
    await db.execute('''CREATE TABLE configurations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      url TEXT NOT NULL,
      username TEXT NOT NULL,
      password TEXT NOT NULL,
      user_agent TEXT NOT NULL,
      account_email TEXT NOT NULL DEFAULT '',
      account_password TEXT NOT NULL DEFAULT '',
      mailbox_password TEXT NOT NULL DEFAULT '',
      statusAccount TEXT NOT NULL DEFAULT 'unregistered'
        CHECK (statusAccount IN ('unregistered', 'registered')),
      has_been_used INTEGER NOT NULL DEFAULT 0 CHECK (has_been_used IN (0, 1)),
      listed INTEGER NOT NULL DEFAULT 1 CHECK (listed IN (0, 1)),
      is_current INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1)),
      time_zone_id TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX one_current_configuration '
      'ON configurations(is_current) WHERE is_current = 1',
    );
    await SqliteNurtureRepository.createSchema(db);
  }

  Future<Database> _open() async {
    Database? db;
    try {
      final factory = _factory ?? databaseFactory;
      final filename =
          _databasePath ??
          path.join(await factory.getDatabasesPath(), 'proxies.db');
      db = await factory.openDatabase(
        filename,
        options: OpenDatabaseOptions(
          version: 10,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onOpen: (db) async {
            await db.update('nurture_sessions', {
              'phase': 'stopped',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            }, where: "phase IN ('waiting','running','paused')");
          },
          onCreate: (db, _) => _createSchema(db),
          onUpgrade: (db, oldVersion, _) async {
            if (oldVersion < 5) {
              await _migrate(db);
            } else if (oldVersion < 6) {
              await db.execute(
                'ALTER TABLE configurations RENAME TO configurations_legacy',
              );
              await db.execute(
                'DROP INDEX IF EXISTS one_current_configuration',
              );
              await _createSchema(db);
              await db.execute(
                'INSERT INTO configurations (id, name, url, username, password, user_agent, '
                'account_email, account_password, mailbox_password, statusAccount, has_been_used, listed, is_current) '
                'SELECT id, name, url, username, password, user_agent, account_email, account_password, '
                'mailbox_password, statusAccount, has_been_used, listed, is_current FROM configurations_legacy',
              );
              await db.execute('DROP TABLE configurations_legacy');
            }
            final columns = await db.rawQuery(
              'PRAGMA table_info(configurations)',
            );
            if (!columns.any((column) => column['name'] == 'time_zone_id')) {
              await db.execute(
                "ALTER TABLE configurations ADD COLUMN time_zone_id TEXT NOT NULL DEFAULT ''",
              );
            }
            final rows = await db.query(
              'configurations',
              columns: ['id', 'user_agent'],
            );
            for (final row in rows) {
              final previous = row['user_agent'] as String;
              final updated = normalizeDesktopUserAgentForPlatform(previous);
              if (updated != previous) {
                await db.update(
                  'configurations',
                  {'user_agent': updated},
                  where: 'id = ?',
                  whereArgs: [row['id']],
                );
              }
            }
            if (oldVersion < 10) await SqliteNurtureRepository.createSchema(db);
          },
        ),
      );
      return db;
    } catch (_) {
      await db?.close();
      _opening = null;
      rethrow;
    }
  }

  Future<void> _migrate(Database db) async {
    final entries = await db.query('proxies', orderBy: 'id ASC');
    final current = await db.query('current_proxy');
    await _createSchema(db);
    for (final row in entries) {
      final agent = (row['user_agent'] as String?) ?? '';
      await db.insert('configurations', {
        ...row,
        'user_agent': agent.isEmpty
            ? normalizeDesktopUserAgentForPlatform(await _selectUserAgent())
            : agent,
        'account_email': row['account_email'] ?? '',
        'account_password': row['account_password'] ?? '',
        'mailbox_password': row['mailbox_password'] ?? '',
      });
    }
    if (current.isNotEmpty) {
      final row = current.single;
      final proxy = _readProxy(row);
      final agent = (row['user_agent'] as String?) ?? '';
      final matches = await db.query(
        'configurations',
        where:
            'url = ? AND username = ? AND password = ? '
            'AND account_email = ? AND account_password = ? AND mailbox_password = ?'
            '${agent.isEmpty ? '' : ' AND user_agent = ?'}',
        whereArgs: [
          proxy == null ? '' : proxyAddress(proxy),
          proxy?.username ?? '',
          proxy?.password ?? '',
          row['account_email'] ?? '',
          row['account_password'] ?? '',
          row['mailbox_password'] ?? '',
          if (agent.isNotEmpty) agent,
        ],
        orderBy: 'id ASC',
        limit: 1,
      );
      int id;
      if (matches.isNotEmpty) {
        id = matches.single['id'] as int;
      } else {
        id = await db.insert('configurations', {
          ..._values(proxy),
          'name': row['name'] ?? proxyLabel(proxy),
          'user_agent': agent.isEmpty
              ? normalizeDesktopUserAgentForPlatform(await _selectUserAgent())
              : agent,
          'account_email': row['account_email'] ?? '',
          'account_password': row['account_password'] ?? '',
          'mailbox_password': row['mailbox_password'] ?? '',
          'listed': agent.isEmpty ? 1 : 0,
        });
      }
      await db.update(
        'configurations',
        {'is_current': 1, 'has_been_used': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await db.execute('DROP TABLE current_proxy');
    await db.execute('DROP TABLE proxies');
  }

  static Map<String, Object?> _values(WebViewProxy? proxy) => {
    'url': proxy == null ? '' : proxyAddress(proxy),
    'username': proxy?.username ?? '',
    'password': proxy?.password ?? '',
  };
  static Map<String, Object?> _accountValues(AccountCredentials account) => {
    'account_email': account.email.trim(),
    'account_password': account.password,
    'mailbox_password': account.mailboxPassword,
  };
  static WebViewProxy? _readProxy(Map<String, Object?> row) =>
      WebViewProxy.parse(
        (row['url'] as String?) ?? '',
        username: (row['username'] as String?) ?? '',
        password: (row['password'] as String?) ?? '',
      );
  static AccountCredentials? _readAccount(Map<String, Object?> row) =>
      (row['account_email'] as String).isEmpty
      ? null
      : AccountCredentials(
          email: row['account_email'] as String,
          password: row['account_password'] as String,
          mailboxPassword: row['mailbox_password'] as String,
        );
  static AccountStatus _readStatus(Map<String, Object?> row) =>
      row['statusAccount'] == 'registered'
      ? AccountStatus.registered
      : AccountStatus.unregistered;
  static ProxyProfile _readProfile(Map<String, Object?> row) => ProxyProfile(
    proxy: _readProxy(row),
    userAgent: row['user_agent'] as String,
    name: row['name'] as String,
    account: _readAccount(row),
    statusAccount: _readStatus(row),
    hasBeenUsed: row['has_been_used'] == 1,
    configurationId: row['id'] as int,
    timeZoneId: row['time_zone_id'] as String? ?? '',
  );

  static Future<Map<String, Object?>?> _findSaved(
    DatabaseExecutor db,
    WebViewProxy? proxy, {
    String? accountEmail,
  }) async {
    final rows = await db.query(
      'configurations',
      where:
          'listed = 1 AND url = ? AND username = ? AND password = ?'
          '${accountEmail == null ? '' : ' AND account_email = ?'}',
      whereArgs: [
        proxy == null ? '' : proxyAddress(proxy),
        proxy?.username ?? '',
        proxy?.password ?? '',
        if (accountEmail != null) accountEmail,
      ],
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<WebViewProxy?> getCurrent() async =>
      (await getCurrentProfile())?.proxy;
  Future<ProxyProfile?> getCurrentProfile() async {
    final rows = await (await _database).query(
      'configurations',
      where: 'is_current = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : _readProfile(rows.single);
  }

  static Future<void> _applyCurrent(DatabaseExecutor db, int? id) async {
    await db.update('configurations', {
      'is_current': 0,
    }, where: 'is_current = 1');
    if (id != null) {
      await db.update(
        'configurations',
        {'is_current': 1, 'has_been_used': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await db.delete('configurations', where: 'listed = 0 AND is_current = 0');
  }

  Future<void> setCurrent(WebViewProxy? proxy) async {
    final db = await _database;
    await db.transaction((txn) async {
      if (proxy == null) return _applyCurrent(txn, null);
      final saved = await _findSaved(txn, proxy);
      if (saved != null) return _applyCurrent(txn, saved['id'] as int);
      final current = await txn.query(
        'configurations',
        where: 'is_current = 1',
        limit: 1,
      );
      if (current.isNotEmpty && sameProxy(_readProxy(current.single), proxy)) {
        return;
      }
      final id = await txn.insert('configurations', {
        ..._values(proxy),
        'name': '',
        'user_agent': normalizeDesktopUserAgentForPlatform(
          await _selectUserAgent(),
        ),
        'listed': 0,
      });
      await _applyCurrent(txn, id);
    });
  }

  Future<void> useSaved(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'configurations',
        where: 'id = ? AND listed = 1',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Configuration no longer exists');
      await _applyCurrent(txn, id);
    });
  }

  Future<List<SavedProxy>> list() async {
    final rows = await (await _database).query(
      'configurations',
      where: 'listed = 1',
      orderBy: 'id DESC',
    );
    return rows
        .map(
          (row) => SavedProxy(
            id: row['id'] as int,
            name: row['name'] as String,
            proxy: _readProxy(row),
            userAgent: row['user_agent'] as String,
            timeZoneId: row['time_zone_id'] as String? ?? '',
            account: _readAccount(row),
            statusAccount: _readStatus(row),
            hasBeenUsed: row['has_been_used'] == 1,
          ),
        )
        .toList();
  }

  Future<int> save({
    int? id,
    required String name,
    required WebViewProxy? proxy,
    String? userAgent,
    AccountCredentials? account,
    AccountStatus? statusAccount,
    String? timeZoneId,
  }) async {
    final db = await _database;
    return db.transaction(
      (txn) => _save(
        txn,
        id: id,
        name: name,
        proxy: proxy,
        userAgent: userAgent,
        account: account,
        statusAccount: statusAccount,
        timeZoneId: timeZoneId,
      ),
    );
  }

  Future<List<int>> saveDrafts(List<ProxyDraft> drafts) async {
    final db = await _database;
    return db.transaction((txn) async {
      final ids = <int>[];
      for (final draft in drafts) {
        ids.add(
          await _save(
            txn,
            name: draft.name,
            proxy: draft.proxy,
            userAgent: draft.userAgent,
            account: draft.account,
            statusAccount: draft.statusAccount,
            timeZoneId: draft.timeZoneId,
          ),
        );
      }
      return ids;
    });
  }

  Future<int> _save(
    DatabaseExecutor txn, {
    int? id,
    required String name,
    required WebViewProxy? proxy,
    String? userAgent,
    AccountCredentials? account,
    AccountStatus? statusAccount,
    String? timeZoneId,
  }) async {
    account?.validate();
    final requestedTimeZone = timeZoneId == null
        ? null
        : normalizeProxyTimeZone(timeZoneId);
    final requestedAgent = userAgent == null
        ? null
        : normalizeDesktopUserAgentForPlatform(userAgent.trim());
    if (requestedAgent != null &&
        (requestedAgent.isEmpty ||
            RegExp(r'[\r\n]').hasMatch(requestedAgent))) {
      throw const FormatException('Nhập User-Agent hợp lệ trên một dòng.');
    }
    Map<String, Object?>? existing;
    if (id != null) {
      final rows = await txn.query(
        'configurations',
        where: 'id = ? AND listed = 1',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Configuration no longer exists');
      existing = rows.single;
    } else {
      existing = await _findSaved(
        txn,
        proxy,
        accountEmail: account?.email.trim() ?? '',
      );
    }
    final values = <String, Object?>{
      'name': name.trim().isEmpty ? proxyLabel(proxy) : name.trim(),
      ..._values(proxy),
      if (requestedAgent != null) 'user_agent': requestedAgent,
      if (account != null) ..._accountValues(account),
      if (statusAccount != null) 'statusAccount': statusAccount.name,
      if (requestedTimeZone != null) 'time_zone_id': requestedTimeZone,
      if (requestedTimeZone == null &&
          existing != null &&
          !sameProxy(_readProxy(existing), proxy))
        'time_zone_id': '',
    };
    if (existing != null) {
      final savedId = existing['id'] as int;
      final sameConnection =
          sameProxy(_readProxy(existing), proxy) &&
          (requestedAgent == null ||
              requestedAgent == existing['user_agent']) &&
          (requestedTimeZone == null ||
              requestedTimeZone == existing['time_zone_id']) &&
          (account == null || sameAccount(_readAccount(existing), account));
      if (existing['is_current'] == 1 && !sameConnection) {
        await txn.update(
          'configurations',
          {'is_current': 0},
          where: 'id = ?',
          whereArgs: [savedId],
        );
        final snapshot = Map<String, Object?>.from(existing)..remove('id');
        await txn.insert('configurations', {...snapshot, 'listed': 0});
      }
      await txn.update(
        'configurations',
        values,
        where: 'id = ?',
        whereArgs: [savedId],
      );
      return savedId;
    }
    final current = await txn.query(
      'configurations',
      where: 'is_current = 1',
      limit: 1,
    );
    final agent =
        requestedAgent ??
        (current.isNotEmpty && sameProxy(_readProxy(current.single), proxy)
            ? current.single['user_agent'] as String
            : normalizeDesktopUserAgentForPlatform(await _selectUserAgent()));
    return txn.insert('configurations', {...values, 'user_agent': agent});
  }

  /// Fill an old active configuration after lookup without changing selection.
  Future<bool> cacheCurrentTimeZone(
    int id,
    WebViewProxy proxy,
    String zone,
  ) async {
    final value = normalizeProxyTimeZone(zone);
    if (value.isEmpty) {
      throw const FormatException('Chưa xác định được múi giờ.');
    }
    return await (await _database).update(
          'configurations',
          {'time_zone_id': value},
          where:
              'id = ? AND is_current = 1 AND url = ? AND username = ? AND password = ? AND time_zone_id = ?',
          whereArgs: [
            id,
            proxyAddress(proxy),
            proxy.username,
            proxy.password,
            '',
          ],
        ) ==
        1;
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'configurations',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      if (rows.single['is_current'] == 1) {
        await txn.update(
          'configurations',
          {'listed': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.delete('configurations', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Update only the account that was opened, without changing selection or
  /// overwriting any other configuration fields.
  Future<bool> markRegistered(int id, String email) async {
    if (email.trim().isEmpty) return false;
    return await (await _database).update(
          'configurations',
          {'statusAccount': AccountStatus.registered.name},
          where: 'id = ? AND account_email = ?',
          whereArgs: [id, email.trim()],
        ) ==
        1;
  }

  Future<void> setUsed(int id, bool used) async {
    final changed = await (await _database).update(
      'configurations',
      {'has_been_used': used ? 1 : 0},
      where: 'id = ? AND listed = 1',
      whereArgs: [id],
    );
    if (changed == 0) throw StateError('Configuration no longer exists');
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
