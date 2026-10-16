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
      expect(await migrated.getVersion(), 10);
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
    'deleting a configuration retains statistics without a dangling foreign key',
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
      final remaining = (await store.nurture.listAccounts()).single;
      expect(remaining.configurationId, isNull);
      expect(remaining.totals.videos, 1);
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(filename);
      expect(
        (await db.query('nurture_sessions')).single['configuration_id'],
        isNull,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
      store = openStore();
    },
  );

  test(
    'deleted active snapshot remains on Home but cannot be selected from statistics',
    () async {
      final id = await store.save(
        name: 'Active',
        proxy: null,
        account: account,
      );
      await store.useSaved(id);
      await store.delete(id);
      expect((await store.getCurrentProfile())!.account!.email, account.email);
      final entry = (await store.nurture.listAccounts()).single;
      expect(entry.configurationId, isNull);
      expect(entry.configurationName, isEmpty);
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
}
