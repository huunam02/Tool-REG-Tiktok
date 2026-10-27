import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String filename;
  late ProxyStore store;
  ProxyStore openStore() => ProxyStore(
    factory: databaseFactoryFfi,
    databasePath: filename,
    selectUserAgent: () async => 'custom-agent',
  );
  const account = AccountCredentials(
    email: 'Person@example.com',
    password: 'original-password',
    mailboxPassword: 'original-mail',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nurture_store_');
    filename = path.join(directory.path, 'proxies.db');
    store = openStore();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'v9 migration preserves every configuration field and selection',
    () async {
      final id = await store.save(
        name: 'Existing',
        proxy: null,
        account: account,
        userAgent: 'custom-agent',
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(id);
      await store.close();
      final old = await databaseFactoryFfi.openDatabase(filename);
      final before = await old.query('configurations');
      await old.execute('DROP TABLE nurture_sessions');
      await old.execute('DROP TABLE nurture_accounts');
      await old.execute('DROP TABLE app_settings');
      await old.setVersion(9);
      await old.close();
      store = openStore();
      expect(
        (await store.getCurrentProfile())!.account!.password,
        account.password,
      );
      expect((await store.nurture.listAccounts()).single.email, account.email);
      await store.close();
      final migrated = await databaseFactoryFfi.openDatabase(filename);
      expect(await migrated.getVersion(), 21);
      expect(await migrated.query('configurations'), before);
      expect(await migrated.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await migrated.close();
      store = openStore();
    },
  );

  test(
    'same email aggregates sessions and rejects duplicate or stale progress',
    () async {
      final id = await store.save(name: 'First', proxy: null, account: account);
      await store.save(
        name: 'Second',
        proxy: null,
        account: const AccountCredentials(
          email: 'person@example.com',
          password: 'other',
          mailboxPassword: 'mail',
        ),
      );
      await store.nurture.beginSession(
        id: 'a',
        email: account.email,
        configurationId: id,
        plan: const NurturePlan(NurtureMode.search, 'Du lịch'),
        phase: 'running',
      );
      const totals = NurtureTotals(
        watchMilliseconds: 90000,
        videos: 3,
        fullVideos: 1,
        skippedVideos: 2,
        comments: 1,
      );
      await store.nurture.saveProgress('a', 1, totals);
      await store.nurture.saveProgress('a', 1, totals);
      await store.nurture.saveProgress('a', 0, const NurtureTotals());
      await store.nurture.beginSession(
        id: 'b',
        email: 'person@example.com',
        plan: const NurturePlan(NurtureMode.feed),
        phase: 'paused',
      );
      await store.nurture.saveProgress(
        'b',
        1,
        const NurtureTotals(watchMilliseconds: 30000, videos: 1, fullVideos: 1),
      );
      final entry = (await store.nurture.listAccounts()).single;
      expect(entry.totals.minutes, 2);
      expect(entry.totals.videos, 4);
      expect(entry.totals.comments, 1);
      expect(entry.phase, 'paused');
      await store.nurture.savePreferences({
        'nurture_keywords': 'Du lịch\nẨm thực',
        'home_comments': 'Existing text',
      });
      await store.close();
      store = openStore();
      final restored = (await store.nurture.listAccounts()).single;
      expect(restored.totals.watchMilliseconds, 120000);
      expect(restored.phase, 'stopped');
      expect(
        (await store.nurture.preferences())['home_comments'],
        'Existing text',
      );
      expect(
        (await store.nurture.preferences())['nurture_keywords'],
        'Du lịch\nẨm thực',
      );
    },
  );

  test(
    'deleting the last configuration removes its account and history',
    () async {
      final id = await store.save(
        name: 'Existing',
        proxy: null,
        account: account,
      );
      await store.nurture.beginSession(
        id: 'history',
        email: account.email,
        configurationId: id,
        plan: const NurturePlan(NurtureMode.feed),
        phase: 'stopped',
      );
      await store.nurture.saveProgress(
        'history',
        1,
        const NurtureTotals(
          watchMilliseconds: 5000,
          videos: 1,
          skippedVideos: 1,
        ),
      );
      await store.delete(id);
      expect(await store.nurture.listAccounts(), isEmpty);
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(filename);
      expect(await db.query('configurations'), isEmpty);
      expect(await db.query('nurture_sessions'), isEmpty);
      expect(await db.query('nurture_accounts'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
      store = openStore();
    },
  );

  test(
    'deleting the selected account clears Home and nurture statistics',
    () async {
      final id = await store.save(
        name: 'Active',
        proxy: null,
        account: account,
      );
      await store.useSaved(id);
      await store.delete(id);
      expect(await store.getCurrentProfile(), isNull);
      expect(await store.nurture.listAccounts(), isEmpty);
    },
  );

  test(
    'mode is independently random and search query preserves Unicode and punctuation',
    () {
      final random = Random(61);
      final modes = List.generate(
        1000,
        (_) =>
            NurturePlan.choose(['Du lịch & cà phê', 'Ẩm thực'], random: random),
      );
      final feedCount = modes
          .where((plan) => plan.mode == NurtureMode.feed)
          .length;
      expect(feedCount, inInclusiveRange(400, 600));
      expect(modes.take(10).map((plan) => plan.mode).toSet(), hasLength(2));
      final search = const NurturePlan(NurtureMode.search, 'Du lịch & cà phê');
      expect(Uri.parse(search.initialUrl).queryParameters['q'], search.keyword);
      expect(NurturePlan.choose([' ', '']).mode, NurtureMode.feed);
    },
  );

  test('registration time follows the account status', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final id = await store.save(
      name: 'Account',
      proxy: null,
      account: account,
      statusAccount: AccountStatus.registered,
    );
    final registered = (await store.nurture.listAccounts()).single.registeredAt;
    expect(registered!.isAfter(before), isTrue);
    // Saving again as registered keeps the original time.
    await store.save(
      id: id,
      name: 'Renamed',
      proxy: null,
      account: account,
      statusAccount: AccountStatus.registered,
    );
    await store.markRegistered(id, account.email);
    expect(
      (await store.nurture.listAccounts()).single.registeredAt,
      registered,
    );
    await store.save(
      id: id,
      name: 'Renamed',
      proxy: null,
      account: account,
      statusAccount: AccountStatus.unregistered,
    );
    expect((await store.nurture.listAccounts()).single.registeredAt, isNull);
    await store.markRegistered(id, account.email);
    expect((await store.nurture.listAccounts()).single.registeredAt, isNotNull);
  });

  test('only sessions that watched count as nurtures', () async {
    await store.save(
      name: 'Account',
      proxy: null,
      account: account,
      statusAccount: AccountStatus.registered,
    );
    var entry = (await store.nurture.listAccounts()).single;
    expect(entry.nurtureCount, 0);
    expect(entry.lastNurturedAt, isNull);
    for (final (id, watched) in [('a', 30000), ('b', 0), ('c', 45000)]) {
      await store.nurture.beginSession(
        id: id,
        email: account.email,
        plan: const NurturePlan(NurtureMode.feed),
        phase: 'running',
      );
      await store.nurture.saveProgress(
        id,
        1,
        NurtureTotals(watchMilliseconds: watched),
      );
    }
    entry = (await store.nurture.listAccounts()).single;
    expect(entry.nurtureCount, 2);
    expect(entry.lastNurturedAt, isNotNull);
  });

  test('v14 databases gain the registration time column', () async {
    await store.save(
      name: 'Old',
      proxy: null,
      account: account,
      statusAccount: AccountStatus.registered,
    );
    await store.close();
    final old = await databaseFactoryFfi.openDatabase(filename);
    await old.execute('ALTER TABLE configurations DROP COLUMN registered_at');
    await old.setVersion(14);
    await old.close();
    store = openStore();
    // Registered before the column existed: the time is unknown.
    final entry = (await store.nurture.listAccounts()).single;
    expect(entry.email, account.email);
    expect(entry.registeredAt, isNull);
  });

  test('each configuration keeps its own nurture settings', () async {
    const custom = NurtureSettings(
      likePercent: 45,
      commentPercent: 5,
      longWatchPercent: 70,
      minMinutes: 10,
      maxMinutes: 20,
    );
    final first = await store.save(
      name: 'First',
      proxy: null,
      account: account,
    );
    await store.save(
      name: 'Second',
      proxy: null,
      account: const AccountCredentials(
        email: 'second@example.com',
        password: 'secret',
        mailboxPassword: 'mail',
      ),
      nurtureSettings: custom,
    );
    await store.close();
    store = openStore();
    final saved = {
      for (final entry in await store.list()) entry.name: entry.nurtureSettings,
    };
    expect(saved, {'First': NurtureSettings.defaults, 'Second': custom});
    // Saving without settings keeps them; invalid values are rejected.
    await store.save(id: first, name: 'First', proxy: null, account: account);
    await expectLater(
      store.save(
        id: first,
        name: 'First',
        proxy: null,
        nurtureSettings: const NurtureSettings(minMinutes: 5, maxMinutes: 4),
      ),
      throwsFormatException,
    );
    await store.useSaved(first);
    expect(
      (await store.getCurrentProfile())!.nurtureSettings,
      NurtureSettings.defaults,
    );
    // The selected configuration is what Home hands to TikTok.
    final second = (await store.list()).singleWhere((e) => e.name == 'Second');
    await store.useSaved(second.id);
    expect((await store.getCurrentProfile())!.nurtureSettings, custom);
    // Editing only the settings of the selected configuration applies them.
    const edited = NurtureSettings(likePercent: 0, commentPercent: 100);
    await store.save(
      id: second.id,
      name: 'Second',
      proxy: null,
      nurtureSettings: edited,
    );
    final current = (await store.getCurrentProfile())!;
    expect(current.configurationId, second.id);
    expect(current.nurtureSettings, edited);
  });

  test('v16 databases gain per-configuration nurture settings', () async {
    await store.save(name: 'Old', proxy: null, account: account);
    await store.close();
    final old = await databaseFactoryFfi.openDatabase(filename);
    for (final column in [
      'nurture_like_percent',
      'nurture_comment_percent',
      'nurture_long_watch_percent',
      'nurture_min_minutes',
      'nurture_max_minutes',
    ]) {
      await old.execute('ALTER TABLE configurations DROP COLUMN $column');
    }
    await old.execute('CREATE TABLE nurture_settings (id INTEGER PRIMARY KEY)');
    await old.setVersion(16);
    await old.close();
    store = openStore();
    final entry = (await store.list()).single;
    expect(entry.name, 'Old');
    expect(entry.nurtureSettings, NurtureSettings.defaults);
    await store.close();
    final migrated = await databaseFactoryFfi.openDatabase(filename);
    final tables = await migrated.query(
      'sqlite_master',
      where: "type = 'table' AND name = 'nurture_settings'",
    );
    expect(tables, isEmpty);
    await migrated.close();
  });
}
