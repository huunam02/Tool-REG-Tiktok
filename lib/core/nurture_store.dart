import 'package:sqflite/sqflite.dart';

import 'nurture_data.dart';

abstract class NurtureRepository {
  Future<List<NurtureAccount>> listAccounts();
  Future<Map<String, String>> preferences();
  Future<void> savePreferences(Map<String, String> values);
  Future<void> beginSession({
    required String id,
    required String email,
    int? configurationId,
    required NurturePlan plan,
    required String phase,
    DateTime? scheduledAt,
  });
  Future<void> saveProgress(String id, int revision, NurtureTotals totals);
  Future<void> setPhase(String id, String phase);
  Future<void> markRegistered(String email);
}

class SqliteNurtureRepository implements NurtureRepository {
  SqliteNurtureRepository(this._database);
  final Future<Database> Function() _database;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS nurture_accounts (
      account_key TEXT PRIMARY KEY, email TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS nurture_sessions (
      id TEXT PRIMARY KEY,
      account_key TEXT NOT NULL REFERENCES nurture_accounts(account_key),
      configuration_id INTEGER REFERENCES configurations(id) ON DELETE SET NULL,
      mode TEXT NOT NULL CHECK(mode IN ('feed','search')), keyword TEXT NOT NULL DEFAULT '',
      phase TEXT NOT NULL CHECK(phase IN ('waiting','running','paused','completed','stopped','error')),
      scheduled_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      revision INTEGER NOT NULL DEFAULT 0,
      watch_ms INTEGER NOT NULL DEFAULT 0 CHECK(watch_ms >= 0),
      videos INTEGER NOT NULL DEFAULT 0 CHECK(videos >= 0),
      full_videos INTEGER NOT NULL DEFAULT 0 CHECK(full_videos >= 0),
      skipped_videos INTEGER NOT NULL DEFAULT 0 CHECK(skipped_videos >= 0),
      comments INTEGER NOT NULL DEFAULT 0 CHECK(comments >= 0))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS nurture_sessions_account ON nurture_sessions(account_key, updated_at)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await syncAccounts(db);
  }

  static Future<void> syncAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''INSERT OR IGNORE INTO nurture_accounts(account_key,email,created_at,updated_at)
      SELECT lower(trim(account_email)), trim(account_email), ?, ? FROM configurations
      WHERE trim(account_email) != '' ''',
      [now, now],
    );
  }

  @override
  Future<List<NurtureAccount>> listAccounts() async {
    final db = await _database();
    return db.transaction((txn) async {
      await syncAccounts(txn);
      final configurations = await txn.query(
        'configurations',
        columns: ['id', 'name', 'account_email'],
        where: "trim(account_email) != '' AND listed = 1",
        orderBy: 'is_current DESC, id DESC',
      );
      final selected = <String, Map<String, Object?>>{};
      for (final row in configurations) {
        selected.putIfAbsent(
          nurtureAccountKey(row['account_email'] as String),
          () => row,
        );
      }
      final rows = await txn.rawQuery(
        '''SELECT a.account_key,a.email,
        COALESCE(SUM(s.watch_ms),0) AS watch_ms, COALESCE(SUM(s.videos),0) AS videos,
        COALESCE(SUM(s.full_videos),0) AS full_videos, COALESCE(SUM(s.skipped_videos),0) AS skipped_videos,
        COALESCE(SUM(s.comments),0) AS comments, MAX(s.updated_at) AS last_updated
        FROM nurture_accounts a LEFT JOIN nurture_sessions s ON s.account_key = a.account_key
        GROUP BY a.account_key ORDER BY last_updated DESC, a.email COLLATE NOCASE''',
      );
      final latest = await txn.rawQuery(
        '''SELECT s.account_key,s.phase,s.mode,s.keyword
        FROM nurture_sessions s WHERE s.rowid = (
          SELECT t.rowid FROM nurture_sessions t WHERE t.account_key = s.account_key
          ORDER BY t.updated_at DESC,t.rowid DESC LIMIT 1)''',
      );
      final latestByAccount = <String, Map<String, Object?>>{};
      for (final row in latest) {
        latestByAccount.putIfAbsent(row['account_key'] as String, () => row);
      }
      return [
        for (final row in rows)
          _readAccount(
            row,
            selected[row['account_key']],
            latestByAccount[row['account_key']],
          ),
      ];
    });
  }

  static NurtureAccount _readAccount(
    Map<String, Object?> row,
    Map<String, Object?>? config,
    Map<String, Object?>? session,
  ) => NurtureAccount(
    key: row['account_key'] as String,
    email: row['email'] as String,
    configurationId: config?['id'] as int?,
    configurationName: config?['name'] as String? ?? '',
    totals: NurtureTotals.fromMap(row),
    phase: session?['phase'] as String? ?? 'idle',
    mode: session?['mode'] == 'search' ? NurtureMode.search : NurtureMode.feed,
    keyword: session?['keyword'] as String? ?? '',
    updatedAt: row['last_updated'] is int
        ? DateTime.fromMillisecondsSinceEpoch(row['last_updated'] as int)
        : null,
  );

  @override
  Future<Map<String, String>> preferences() async => {
    for (final row in await (await _database()).query('app_settings'))
      row['key'] as String: row['value'] as String,
  };

  @override
  Future<void> savePreferences(Map<String, String> values) async {
    final db = await _database();
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> beginSession({
    required String id,
    required String email,
    int? configurationId,
    required NurturePlan plan,
    required String phase,
    DateTime? scheduledAt,
  }) async {
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = nurtureAccountKey(email);
    if (key.isEmpty) {
      throw const FormatException('Thiếu tài khoản cho phiên nuôi.');
    }
    await db.transaction((txn) async {
      await txn.insert('nurture_accounts', {
        'account_key': key,
        'email': email.trim(),
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final validConfig = configurationId == null
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'configurations',
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [configurationId],
            );
      await txn.insert('nurture_sessions', {
        'id': id,
        'account_key': key,
        'configuration_id': validConfig.isEmpty ? null : configurationId,
        'mode': plan.mode.name,
        'keyword': plan.keyword,
        'phase': phase,
        'scheduled_at': scheduledAt?.millisecondsSinceEpoch,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<void> saveProgress(
    String id,
    int revision,
    NurtureTotals totals,
  ) async {
    await (await _database()).rawUpdate(
      '''UPDATE nurture_sessions SET
      watch_ms = MAX(watch_ms,?), videos = MAX(videos,?), full_videos = MAX(full_videos,?),
      skipped_videos = MAX(skipped_videos,?), comments = MAX(comments,?), revision = ?, updated_at = ?
      WHERE id = ? AND revision < ?''',
      [
        totals.watchMilliseconds,
        totals.videos,
        totals.fullVideos,
        totals.skippedVideos,
        totals.comments,
        revision,
        DateTime.now().millisecondsSinceEpoch,
        id,
        revision,
      ],
    );
  }

  @override
  Future<void> setPhase(String id, String phase) async {
    await (await _database()).update(
      'nurture_sessions',
      {'phase': phase, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markRegistered(String email) async {
    await (await _database()).update(
      'configurations',
      {'statusAccount': 'registered'},
      where: 'lower(trim(account_email)) = ?',
      whereArgs: [nurtureAccountKey(email)],
    );
  }
}
