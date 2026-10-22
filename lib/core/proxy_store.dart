import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'app_configuration.dart';
import 'configuration_data.dart';
import 'proxy_draft.dart';
import 'desktop_user_agents.dart';
import 'firefox_user_agent.dart';
import 'proxy_time_zone.dart';
import 'device_memory.dart';
import 'gpu_profile.dart';
import 'nurture_data.dart';
import 'nurture_store.dart';
import 'signup_failure.dart';

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
    this.nurtureAfterSignup = false,
    this.nurtureSettings = NurtureSettings.defaults,
    this.gpuProfileId = '',
    this.signupFailed = false,
  });

  final WebViewProxy? proxy;
  final String userAgent;
  final String name;
  final bool hasBeenUsed;
  final AccountCredentials? account;
  final AccountStatus statusAccount;
  final int? configurationId;
  final String timeZoneId;
  final bool nurtureAfterSignup;

  /// Like/comment/long-watch rates and session length for this account.
  final NurtureSettings nurtureSettings;

  /// The phone GPU pages see over WebGL; fixed per configuration.
  final String gpuProfileId;
  GpuProfile get gpuProfile => GpuProfile.byId(gpuProfileId);

  /// The last automatic signup of this configuration failed.
  final bool signupFailed;

  ProxyProfile copyWith({
    String? userAgent,
    String? timeZoneId,
    String? gpuProfileId,
  }) => ProxyProfile(
    proxy: proxy,
    userAgent: userAgent ?? this.userAgent,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    name: name,
    hasBeenUsed: hasBeenUsed,
    account: account,
    statusAccount: statusAccount,
    configurationId: configurationId,
    nurtureAfterSignup: nurtureAfterSignup,
    nurtureSettings: nurtureSettings,
    gpuProfileId: gpuProfileId ?? this.gpuProfileId,
    signupFailed: signupFailed,
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
    super.nurtureAfterSignup,
    super.nurtureSettings,
    super.gpuProfileId,
    super.signupFailed,
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
      time_zone_id TEXT NOT NULL DEFAULT '',
      nurture_after_signup INTEGER NOT NULL DEFAULT 0
        CHECK (nurture_after_signup IN (0, 1)),
      signup_failed INTEGER NOT NULL DEFAULT 0
        CHECK (signup_failed IN (0, 1)),
      registered_at INTEGER,
      gpu_profile TEXT NOT NULL DEFAULT '',
      $_nurtureSettingsColumns
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX one_current_configuration '
      'ON configurations(is_current) WHERE is_current = 1',
    );
    await SqliteNurtureRepository.createSchema(db);
    await _createSignupFailureSchema(db);
  }

  /// Per-configuration nurture settings; the defaults are [NurtureSettings].
  static final _nurtureSettingsColumnDefinitions = () {
    const d = NurtureSettings.defaults;
    const max = NurtureSettings.maxSessionMinutes;
    return {
      'nurture_like_percent':
          'INTEGER NOT NULL DEFAULT ${d.likePercent} '
          'CHECK (nurture_like_percent BETWEEN 0 AND 100)',
      'nurture_comment_percent':
          'INTEGER NOT NULL DEFAULT ${d.commentPercent} '
          'CHECK (nurture_comment_percent BETWEEN 0 AND 100)',
      'nurture_long_watch_percent':
          'INTEGER NOT NULL DEFAULT ${d.longWatchPercent} '
          'CHECK (nurture_long_watch_percent BETWEEN 0 AND 100)',
      'nurture_min_minutes':
          'INTEGER NOT NULL DEFAULT ${d.minMinutes} '
          'CHECK (nurture_min_minutes BETWEEN 1 AND $max)',
      'nurture_max_minutes':
          'INTEGER NOT NULL DEFAULT ${d.maxMinutes} '
          'CHECK (nurture_max_minutes BETWEEN 1 AND $max)',
    };
  }();

  /// Older versions kept a simulated Local IP per configuration. WebRTC is
  /// always blocked, so it was never used: erase it, and drop the column
  /// where this SQLite supports DROP COLUMN (3.35+).
  static Future<void> _removeLocalIps(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(configurations)');
    if (!columns.any((column) => column['name'] == 'local_ip')) return;
    await db.execute("UPDATE configurations SET local_ip = ''");
    try {
      await db.execute('ALTER TABLE configurations DROP COLUMN local_ip');
    } on DatabaseException {
      // Older Android SQLite: the column stays, empty and unused.
    }
  }

  /// Give every configuration without a known phone GPU a random one.
  static Future<void> _fillGpuProfiles(DatabaseExecutor db) async {
    final rows = await db.query(
      'configurations',
      columns: ['id', 'gpu_profile'],
    );
    for (final row in rows) {
      if (GpuProfile.isKnown(row['gpu_profile'] as String? ?? '')) continue;
      await db.update(
        'configurations',
        {'gpu_profile': GpuProfile.random().id},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  static String get _nurtureSettingsColumns => [
    for (final entry in _nurtureSettingsColumnDefinitions.entries)
      '${entry.key} ${entry.value}',
  ].join(',\n      ');

  static Future<void> _createSignupFailureSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS signup_failures (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      configuration_id INTEGER NOT NULL
        REFERENCES configurations(id) ON DELETE CASCADE,
      email TEXT NOT NULL,
      message TEXT NOT NULL,
      step TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS signup_failures_configuration '
      'ON signup_failures(configuration_id, created_at)',
    );
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
          version: 20,
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
            if (!columns.any(
              (column) => column['name'] == 'nurture_after_signup',
            )) {
              await db.execute(
                'ALTER TABLE configurations ADD COLUMN nurture_after_signup '
                'INTEGER NOT NULL DEFAULT 0 CHECK (nurture_after_signup IN (0, 1))',
              );
            }
            if (!columns.any((column) => column['name'] == 'signup_failed')) {
              await db.execute(
                'ALTER TABLE configurations ADD COLUMN signup_failed '
                'INTEGER NOT NULL DEFAULT 0 CHECK (signup_failed IN (0, 1))',
              );
            }
            if (!columns.any((column) => column['name'] == 'registered_at')) {
              // Accounts registered before this column have no known time.
              await db.execute(
                'ALTER TABLE configurations ADD COLUMN registered_at INTEGER',
              );
            }
            await _createSignupFailureSchema(db);
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
            final nurtureColumns = await db.rawQuery(
              'PRAGMA table_info(configurations)',
            );
            for (final entry in _nurtureSettingsColumnDefinitions.entries) {
              if (!nurtureColumns.any(
                (column) => column['name'] == entry.key,
              )) {
                await db.execute(
                  'ALTER TABLE configurations ADD COLUMN '
                  '${entry.key} ${entry.value}',
                );
              }
            }
            // A development build kept one shared row; settings are now
            // stored per configuration.
            await db.execute('DROP TABLE IF EXISTS nurture_settings');
            final sessions = await db.rawQuery(
              'PRAGMA table_info(nurture_sessions)',
            );
            if (!sessions.any((column) => column['name'] == 'likes')) {
              await db.execute(
                'ALTER TABLE nurture_sessions ADD COLUMN likes '
                'INTEGER NOT NULL DEFAULT 0 CHECK (likes >= 0)',
              );
            }
            await _removeLocalIps(db);
            final gpuColumns = await db.rawQuery(
              'PRAGMA table_info(configurations)',
            );
            if (!gpuColumns.any((column) => column['name'] == 'gpu_profile')) {
              await db.execute(
                "ALTER TABLE configurations ADD COLUMN gpu_profile TEXT NOT NULL DEFAULT ''",
              );
            }
            await _fillGpuProfiles(db);
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
    userAgent: normalizeDesktopUserAgentForPlatform(
      row['user_agent'] as String,
    ),
    name: row['name'] as String,
    account: _readAccount(row),
    statusAccount: _readStatus(row),
    hasBeenUsed: row['has_been_used'] == 1,
    configurationId: row['id'] as int,
    timeZoneId: row['time_zone_id'] as String? ?? '',
    nurtureAfterSignup: row['nurture_after_signup'] == 1,
    nurtureSettings: NurtureSettings.fromMap(row),
    gpuProfileId: row['gpu_profile'] as String? ?? '',
    signupFailed: row['signup_failed'] == 1,
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
    final previous = await db.query(
      'configurations',
      columns: ['id'],
      where: 'is_current = 1',
      limit: 1,
    );
    if ((previous.isEmpty ? null : previous.single['id']) != id) {
      await db.insert('app_settings', {
        'key': 'current_configuration_logged_in',
        'value': 'false',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
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
        'gpu_profile': GpuProfile.random().id,
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

  /// Older installations can recover their existing cookie-backed session.
  /// Once selection changes, cookies alone cannot confirm the new account.
  Future<bool> canReuseCurrentAccountSession() async {
    final rows = await (await _database).query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['current_configuration_logged_in'],
      limit: 1,
    );
    return rows.isEmpty || rows.single['value'] == 'true';
  }

  Future<bool> setCurrentAccountLoggedIn(
    int configurationId,
    String email,
    bool loggedIn,
  ) async {
    final db = await _database;
    return db.transaction((txn) async {
      final selected = await txn.query(
        'configurations',
        columns: ['id'],
        where: 'id = ? AND is_current = 1 AND account_email = ?',
        whereArgs: [configurationId, email.trim()],
        limit: 1,
      );
      if (selected.isEmpty) return false;
      await txn.insert('app_settings', {
        'key': 'current_configuration_logged_in',
        'value': loggedIn ? 'true' : 'false',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  static SavedProxy _readSaved(Map<String, Object?> row) => SavedProxy(
    id: row['id'] as int,
    name: row['name'] as String,
    proxy: _readProxy(row),
    userAgent: normalizeDesktopUserAgentForPlatform(
      row['user_agent'] as String,
    ),
    timeZoneId: row['time_zone_id'] as String? ?? '',
    account: _readAccount(row),
    statusAccount: _readStatus(row),
    hasBeenUsed: row['has_been_used'] == 1,
    nurtureAfterSignup: row['nurture_after_signup'] == 1,
    nurtureSettings: NurtureSettings.fromMap(row),
    gpuProfileId: row['gpu_profile'] as String? ?? '',
    signupFailed: row['signup_failed'] == 1,
  );

  /// Give each unregistered configuration whose phone GPU was never sold
  /// with this device's RAM ([deviceMemoryGb]) a phone that was. Registered
  /// accounts keep theirs, so TikTok never sees their phone change. Returns
  /// the new GPU id of each changed configuration.
  Future<Map<int, String>> fitGpuProfilesToDevice([double? memory]) async {
    memory ??= deviceMemoryGb;
    if (memory == null) return const {};
    final db = await _database;
    final rows = await db.query(
      'configurations',
      columns: ['id', 'gpu_profile', 'statusAccount'],
    );
    final changed = <int, String>{};
    for (final row in rows) {
      if (row['statusAccount'] == 'registered') continue;
      if (GpuProfile.byId(row['gpu_profile'] as String? ?? '').fits(memory)) {
        continue;
      }
      final id = row['id'] as int;
      final gpu = GpuProfile.random(null, memory).id;
      await db.update(
        'configurations',
        {'gpu_profile': gpu},
        where: 'id = ?',
        whereArgs: [id],
      );
      changed[id] = gpu;
    }
    return changed;
  }

  Future<List<SavedProxy>> list() async {
    final rows = await (await _database).query(
      'configurations',
      where: 'listed = 1',
      orderBy: 'id DESC',
    );
    return rows.map(_readSaved).toList();
  }

  Future<int> save({
    int? id,
    required String name,
    required WebViewProxy? proxy,
    String? userAgent,
    AccountCredentials? account,
    AccountStatus? statusAccount,
    String? timeZoneId,
    bool? nurtureAfterSignup,
    NurtureSettings? nurtureSettings,
    String? gpuProfileId,
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
        nurtureAfterSignup: nurtureAfterSignup,
        nurtureSettings: nurtureSettings,
        gpuProfileId: gpuProfileId,
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
            nurtureAfterSignup: draft.nurtureAfterSignup,
            nurtureSettings: draft.nurtureSettings,
            gpuProfileId: draft.gpuProfileId,
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
    bool? nurtureAfterSignup,
    NurtureSettings? nurtureSettings,
    String? gpuProfileId,
  }) async {
    account?.validate();
    if (gpuProfileId != null && !GpuProfile.isKnown(gpuProfileId)) {
      throw const FormatException('Thiết bị GPU không có trong danh sách.');
    }
    final nurtureError = nurtureSettings?.error;
    if (nurtureError != null) throw FormatException(nurtureError);
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
      // When the account became registered; cleared if it is unregistered.
      if (statusAccount == AccountStatus.registered &&
          existing?['statusAccount'] != AccountStatus.registered.name)
        'registered_at': DateTime.now().millisecondsSinceEpoch,
      if (statusAccount == AccountStatus.unregistered) 'registered_at': null,
      if (nurtureAfterSignup != null)
        'nurture_after_signup': nurtureAfterSignup ? 1 : 0,
      ...?nurtureSettings?.toMap(),
      if (gpuProfileId != null) 'gpu_profile': gpuProfileId.trim(),
      if (account != null &&
          existing != null &&
          existing['account_email'] != account.email.trim())
        'signup_failed': 0,
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
    return txn.insert('configurations', {
      ...values,
      'user_agent': agent,
      'gpu_profile': values['gpu_profile'] ?? GpuProfile.random().id,
    });
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
    return await (await _database).rawUpdate(
          '''UPDATE configurations SET statusAccount = ?, signup_failed = 0,
          registered_at = COALESCE(registered_at, ?)
          WHERE id = ? AND account_email = ?''',
          [
            AccountStatus.registered.name,
            DateTime.now().millisecondsSinceEpoch,
            id,
            email.trim(),
          ],
        ) ==
        1;
  }

  /// Log a failed automatic signup and list the configuration as failed,
  /// unless it has meanwhile been registered or given another account.
  Future<bool> recordSignupFailure(
    int id,
    String email, {
    required String message,
    String step = '',
    DateTime? at,
  }) async {
    if (email.trim().isEmpty) return false;
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'configurations',
        columns: ['id'],
        where: 'id = ? AND account_email = ? AND statusAccount = ?',
        whereArgs: [id, email.trim(), AccountStatus.unregistered.name],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      await txn.insert('signup_failures', {
        'configuration_id': id,
        'email': email.trim(),
        'message': message.trim().isEmpty
            ? 'Không rõ nguyên nhân.'
            : message.trim(),
        'step': step.trim(),
        'created_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      });
      await txn.update(
        'configurations',
        {'signup_failed': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    });
  }

  /// Unregistered configurations whose last automatic signup failed, most
  /// recently failed first, each with its newest [logLimit] attempts.
  Future<List<FailedConfiguration>> listFailedConfigurations({
    int logLimit = 20,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''SELECT c.*, COUNT(f.id) AS failure_count,
        MAX(f.created_at) AS last_failure
      FROM configurations c
      LEFT JOIN signup_failures f ON f.configuration_id = c.id
      WHERE c.listed = 1 AND c.signup_failed = 1 AND c.statusAccount = ?
      GROUP BY c.id
      ORDER BY last_failure DESC, c.id DESC''',
      [AccountStatus.unregistered.name],
    );
    return [
      for (final row in rows)
        FailedConfiguration(
          configuration: _readSaved(row),
          failureCount: (row['failure_count'] as num?)?.toInt() ?? 0,
          failures: (await db.query(
            'signup_failures',
            where: 'configuration_id = ?',
            whereArgs: [row['id']],
            orderBy: 'created_at DESC, id DESC',
            limit: logLimit,
          )).map(SignupFailure.fromRow).toList(),
        ),
    ];
  }

  /// Remove a configuration from the failed list; its log is kept.
  Future<void> clearSignupFailure(int id) async {
    await (await _database).update(
      'configurations',
      {'signup_failed': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
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
