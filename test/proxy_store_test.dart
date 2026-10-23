import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/proxy_draft.dart';
import 'package:test_tiktok/core/firefox_user_agent.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late ProxyStore store;
  late String filename;
  var nextAgent = 0;

  ProxyStore openStore() => ProxyStore(
    factory: databaseFactoryFfi,
    databasePath: filename,
    selectUserAgent: () async => 'test-user-agent-${nextAgent++}',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('proxy_store_test_');
    filename = path.join(directory.path, 'proxies.db');
    nextAgent = 0;
    store = openStore();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('upgrading erases the unused Local IP column', () async {
    await store.save(name: 'A', proxy: WebViewProxy.parse('192.0.2.7:8080')!);
    await store.close();
    final old = await databaseFactoryFfi.openDatabase(filename);
    await old.execute(
      "ALTER TABLE configurations ADD COLUMN local_ip TEXT NOT NULL DEFAULT ''",
    );
    await old.execute("UPDATE configurations SET local_ip = '192.168.22.34'");
    await old.setVersion(17);
    await old.close();
    store = openStore();
    expect((await store.list()).single.name, 'A');
    await store.close();
    final migrated = await databaseFactoryFfi.openDatabase(filename);
    final columns = await migrated.rawQuery(
      'PRAGMA table_info(configurations)',
    );
    expect(
      columns.map((column) => column['name']),
      isNot(contains('local_ip')),
    );
    await migrated.close();
    store = openStore();
  });

  test('persists Nuôi sau khi đăng ký per configuration', () async {
    const account = AccountCredentials(
      email: 'nurture@example.com',
      password: 'password',
      mailboxPassword: 'mail',
    );
    final ids = await store.saveDrafts([
      const ProxyDraft(
        'Nurture',
        null,
        'agent',
        account: account,
        nurtureAfterSignup: true,
      ),
      const ProxyDraft(
        'Plain',
        null,
        'agent',
        account: AccountCredentials(
          email: 'plain@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      ),
    ]);
    final saved = {for (final entry in await store.list()) entry.id: entry};
    expect(saved[ids.first]!.nurtureAfterSignup, isTrue);
    expect(saved[ids.last]!.nurtureAfterSignup, isFalse);
    await store.useSaved(ids.first);
    expect((await store.getCurrentProfile())!.nurtureAfterSignup, isTrue);
    // Saving without the flag (e.g. marking registered) keeps it.
    await store.markRegistered(ids.first, account.email);
    expect((await store.getCurrentProfile())!.nurtureAfterSignup, isTrue);
    await store.save(
      id: ids.first,
      name: 'Nurture',
      proxy: null,
      nurtureAfterSignup: false,
    );
    expect((await store.getCurrentProfile())!.nurtureAfterSignup, isFalse);
  });

  test(
    'signup failures are logged per configuration until registered',
    () async {
      const account = AccountCredentials(
        email: 'failed@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final failed = await store.save(
        name: 'Failed',
        proxy: null,
        account: account,
      );
      final other = await store.save(
        name: 'Other',
        proxy: null,
        account: const AccountCredentials(
          email: 'other@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      );
      expect(await store.listFailedConfigurations(), isEmpty);
      // A changed email cannot log against the configuration.
      expect(
        await store.recordSignupFailure(
          failed,
          'someone@example.com',
          message: 'x',
        ),
        isFalse,
      );
      final first = DateTime(2026, 10, 18, 1, 34);
      expect(
        await store.recordSignupFailure(
          failed,
          account.email,
          message: 'TikTok báo lỗi tài khoản (mã 1023).',
          step: 'Đang mở danh sách Year…',
          at: first,
        ),
        isTrue,
      );
      await store.recordSignupFailure(
        failed,
        account.email,
        message: '  ',
        at: first.add(const Duration(minutes: 40)),
      );
      var list = await store.listFailedConfigurations();
      expect(list.single.configuration.id, failed);
      expect(list.single.configuration.signupFailed, isTrue);
      expect(list.single.failureCount, 2);
      expect(list.single.failures.map((failure) => failure.message), [
        'Không rõ nguyên nhân.',
        'TikTok báo lỗi tài khoản (mã 1023).',
      ]);
      expect(list.single.failures.last.step, 'Đang mở danh sách Year…');
      expect(list.single.failures.last.createdAt, first);
      expect(
        (await store.list())
            .singleWhere((entry) => entry.id == other)
            .signupFailed,
        isFalse,
      );
      expect(
        (await store.listFailedConfigurations(logLimit: 1)).single.failures,
        hasLength(1),
      );

      // The log survives reopening; dismissing keeps it for a later failure.
      await store.close();
      store = openStore();
      await store.clearSignupFailure(failed);
      expect(await store.listFailedConfigurations(), isEmpty);
      await store.recordSignupFailure(failed, account.email, message: 'again');
      list = await store.listFailedConfigurations();
      expect(list.single.failureCount, 3);

      // Registering clears the failed state.
      expect(await store.markRegistered(failed, account.email), isTrue);
      expect(await store.listFailedConfigurations(), isEmpty);
      expect(
        (await store.list())
            .singleWhere((entry) => entry.id == failed)
            .signupFailed,
        isFalse,
      );
      expect(
        await store.recordSignupFailure(failed, account.email, message: 'late'),
        isFalse,
      );
    },
  );

  test('a new account email or deletion removes the failed state', () async {
    const account = AccountCredentials(
      email: 'failed@example.com',
      password: 'password',
      mailboxPassword: 'mail',
    );
    final id = await store.save(name: 'Failed', proxy: null, account: account);
    await store.recordSignupFailure(id, account.email, message: 'error');
    await store.save(
      id: id,
      name: 'Failed',
      proxy: null,
      account: const AccountCredentials(
        email: 'replacement@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      ),
    );
    expect(await store.listFailedConfigurations(), isEmpty);
    await store.recordSignupFailure(
      id,
      'replacement@example.com',
      message: 'error',
    );
    expect(await store.listFailedConfigurations(), hasLength(1));
    await store.delete(id);
    expect(await store.listFailedConfigurations(), isEmpty);
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(filename);
    expect(await db.query('signup_failures'), isEmpty);
    await db.close();
    store = openStore();
  });

  test('version 11 databases gain the signup failure log', () async {
    await store.save(
      name: 'Old',
      proxy: null,
      account: const AccountCredentials(
        email: 'old@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      ),
    );
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(filename);
    await db.execute('DROP TABLE signup_failures');
    await db.execute('ALTER TABLE configurations DROP COLUMN signup_failed');
    await db.setVersion(11);
    await db.close();
    store = openStore();
    final entry = (await store.list()).single;
    expect(entry.signupFailed, isFalse);
    expect(
      await store.recordSignupFailure(
        entry.id,
        'old@example.com',
        message: 'error',
      ),
      isTrue,
    );
    expect(await store.listFailedConfigurations(), hasLength(1));
  });

  test('version 10 databases gain the nurture column switched off', () async {
    await store.save(
      name: 'Old',
      proxy: null,
      account: const AccountCredentials(
        email: 'old@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      ),
    );
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(filename);
    await db.execute(
      'ALTER TABLE configurations DROP COLUMN nurture_after_signup',
    );
    await db.setVersion(10);
    await db.close();
    store = openStore();
    final entries = await store.list();
    expect(entries.single.nurtureAfterSignup, isFalse);
    final id = await store.save(
      id: entries.single.id,
      name: 'Old',
      proxy: null,
      nurtureAfterSignup: true,
    );
    expect(
      (await store.list())
          .singleWhere((entry) => entry.id == id)
          .nurtureAfterSignup,
      isTrue,
    );
  });

  test(
    'changing configuration resets persisted login and rejects stale confirmation',
    () async {
      const firstAccount = AccountCredentials(
        email: 'first@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      const secondAccount = AccountCredentials(
        email: 'second@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final first = await store.save(
        name: 'First',
        proxy: null,
        account: firstAccount,
      );
      final second = await store.save(
        name: 'Second',
        proxy: null,
        account: secondAccount,
      );
      await store.useSaved(first);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      expect(
        await store.setCurrentAccountLoggedIn(first, firstAccount.email, true),
        isTrue,
      );
      await store.useSaved(first);
      expect(await store.canReuseCurrentAccountSession(), isTrue);
      await store.useSaved(second);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      expect(
        await store.setCurrentAccountLoggedIn(first, firstAccount.email, true),
        isFalse,
      );
      expect(
        await store.setCurrentAccountLoggedIn(second, firstAccount.email, true),
        isFalse,
      );
      await store.close();
      store = openStore();
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      expect(
        await store.setCurrentAccountLoggedIn(
          second,
          secondAccount.email,
          true,
        ),
        isTrue,
      );
      await store.close();
      store = openStore();
      expect(await store.canReuseCurrentAccountSession(), isTrue);
      await store.useSaved(first);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      await store.setCurrentAccountLoggedIn(first, firstAccount.email, true);
      await store.setCurrent(null);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
    },
  );

  test(
    'signup marks only the opened configuration and survives reopening',
    () async {
      const account = AccountCredentials(
        email: 'signup@example.com',
        password: 'tiktok-password',
        mailboxPassword: 'mail-password',
      );
      final id = await store.save(
        name: 'Signup',
        proxy: null,
        account: account,
        userAgent: 'signup-agent',
      );
      final otherId = await store.save(
        name: 'Other',
        proxy: WebViewProxy.parse('192.0.2.8:8080'),
        account: account,
      );
      await store.useSaved(id);
      expect(await store.markRegistered(id, account.email), isTrue);
      expect(
        (await store.getCurrentProfile())!.statusAccount,
        AccountStatus.registered,
      );
      await store.useSaved(otherId);
      expect(await store.markRegistered(id, account.email), isTrue);
      await store.close();
      store = openStore();
      final rows = await store.list();
      final registered = rows.singleWhere((row) => row.id == id);
      expect(registered.statusAccount, AccountStatus.registered);
      expect(registered.name, 'Signup');
      expect(registered.userAgent, firefoxDesktopUserAgent);
      expect(sameAccount(registered.account, account), isTrue);
      final current = (await store.getCurrentProfile())!;
      expect(current.configurationId, otherId);
      expect(current.statusAccount, AccountStatus.unregistered);
    },
  );

  test(
    'signup cannot register a deleted configuration or a changed email',
    () async {
      final id = await store.save(
        name: 'Changed',
        proxy: null,
        account: const AccountCredentials(
          email: 'new@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      );
      expect(await store.markRegistered(id, 'old@example.com'), isFalse);
      expect(await store.markRegistered(id, ''), isFalse);
      expect(
        (await store.list()).single.statusAccount,
        AccountStatus.unregistered,
      );
      await store.delete(id);
      expect(await store.markRegistered(id, 'new@example.com'), isFalse);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'timezone survives batch save, selection, edits and reopening',
    () async {
      final proxy = WebViewProxy.parse('192.0.2.7:8080')!;
      final ids = await store.saveDrafts([
        ProxyDraft('US', proxy, 'agent', timeZoneId: 'America/New_York'),
        ProxyDraft(
          'JP',
          WebViewProxy.parse('192.0.2.8:8080'),
          'agent',
          timeZoneId: 'Asia/Tokyo',
        ),
      ]);
      await store.useSaved(ids.first);
      await store.close();
      store = openStore();
      expect((await store.getCurrentProfile())!.timeZoneId, 'America/New_York');
      expect((await store.list()).map((row) => row.timeZoneId), [
        'Asia/Tokyo',
        'America/New_York',
      ]);
      await store.save(id: ids.first, name: 'renamed', proxy: proxy);
      expect((await store.getCurrentProfile())!.timeZoneId, 'America/New_York');
      await store.save(
        id: ids.first,
        name: 'edited',
        proxy: proxy,
        timeZoneId: 'America/Los_Angeles',
      );
      expect((await store.getCurrentProfile())!.timeZoneId, 'America/New_York');
      expect(
        (await store.list())
            .singleWhere((row) => row.id == ids.first)
            .timeZoneId,
        'America/Los_Angeles',
      );
      await store.useSaved(ids.first);
      expect(
        (await store.getCurrentProfile())!.timeZoneId,
        'America/Los_Angeles',
      );
    },
  );

  test(
    'v7 migration adds timezone without changing selected credentials or metadata',
    () async {
      final id = await store.save(
        name: 'Existing',
        proxy: WebViewProxy.parse(
          '192.0.2.7:8080',
          username: 'user',
          password: 'pass',
        ),
        userAgent: 'custom-agent',
      );
      await store.useSaved(id);
      await store.close();
      final old = await databaseFactoryFfi.openDatabase(filename);
      await old.execute('ALTER TABLE configurations DROP COLUMN time_zone_id');
      await old.execute('PRAGMA user_version = 7');
      await old.close();
      store = openStore();
      final selected = (await store.getCurrentProfile())!;
      expect(selected.configurationId, id);
      expect(selected.proxy!.username, 'user');
      expect(selected.proxy!.password, 'pass');
      expect(selected.userAgent, firefoxDesktopUserAgent);
      expect(selected.hasBeenUsed, isTrue);
      expect(selected.timeZoneId, isEmpty);
      await store.close();
      final migrated = await databaseFactoryFfi.openDatabase(filename);
      expect(await migrated.getVersion(), 20);
      expect(
        (await migrated.rawQuery(
          'PRAGMA table_info(configurations)',
        )).map((row) => row['name']),
        contains('time_zone_id'),
      );
      await migrated.close();
      store = openStore();
    },
  );

  test(
    'invalid timezone rolls back a batch and changed proxy clears old timezone',
    () async {
      final proxy = WebViewProxy.parse('192.0.2.7:8080')!;
      final id = await store.save(
        name: 'US',
        proxy: proxy,
        timeZoneId: 'America/New_York',
      );
      await expectLater(
        store.saveDrafts([
          ProxyDraft('changed', proxy, 'agent', timeZoneId: 'Asia/Tokyo'),
          ProxyDraft(
            'invalid',
            WebViewProxy.parse('192.0.2.8:8080'),
            'agent',
            timeZoneId: 'bad;script',
          ),
        ]),
        throwsFormatException,
      );
      expect((await store.list()).single.timeZoneId, 'America/New_York');
      await store.save(
        id: id,
        name: 'new proxy',
        proxy: WebViewProxy.parse('192.0.2.9:8080'),
      );
      expect((await store.list()).single.timeZoneId, isEmpty);
    },
  );

  test(
    'automatic timezone caching only updates the matching blank active row',
    () async {
      final proxy = WebViewProxy.parse('192.0.2.7:8080')!;
      final id = await store.save(name: 'old', proxy: proxy);
      expect(
        await store.cacheCurrentTimeZone(id, proxy, 'Asia/Tokyo'),
        isFalse,
      );
      await store.useSaved(id);
      expect(
        await store.cacheCurrentTimeZone(
          id,
          WebViewProxy.parse('192.0.2.8:8080')!,
          'Asia/Tokyo',
        ),
        isFalse,
      );
      expect(
        await store.cacheCurrentTimeZone(id, proxy, 'America/New_York'),
        isTrue,
      );
      expect(
        await store.cacheCurrentTimeZone(id, proxy, 'Asia/Tokyo'),
        isFalse,
      );
      await store.close();
      store = openStore();
      expect((await store.getCurrentProfile())!.timeZoneId, 'America/New_York');
    },
  );

  test(
    'version 6 upgrades every saved UA to Firefox and preserves accounts',
    () async {
      const oldAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
      const custom = 'CustomBrowser/1.0';
      const account = AccountCredentials(
        email: 'person@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final id = await store.save(
        name: 'Existing',
        proxy: WebViewProxy.parse('192.0.2.7:8080'),
        userAgent: oldAgent,
        account: account,
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(id);
      await store.save(
        name: 'Edge',
        proxy: WebViewProxy.parse('192.0.2.8:8080'),
        userAgent: '$oldAgent Edg/140.0.0.0',
      );
      await store.save(
        name: 'Custom',
        proxy: WebViewProxy.parse('192.0.2.9:8080'),
        userAgent: custom,
      );
      await store.close();
      final previous = await databaseFactoryFfi.openDatabase(filename);
      await previous.execute('PRAGMA user_version = 6');
      await previous.close();
      store = openStore();
      final selected = (await store.getCurrentProfile())!;
      // GeckoView sends only Firefox with "Desktop site" on.
      const expected = firefoxDesktopUserAgent;
      expect(selected.configurationId, id);
      expect(selected.userAgent, expected);
      expect(selected.account!.email, account.email);
      expect(selected.account!.password, account.password);
      expect(selected.account!.mailboxPassword, account.mailboxPassword);
      expect(selected.statusAccount, AccountStatus.registered);
      expect(selected.hasBeenUsed, isTrue);
      final saved = await store.list();
      expect(
        saved.singleWhere((row) => row.name == 'Edge').userAgent,
        expected,
      );
      expect(
        saved.singleWhere((row) => row.name == 'Custom').userAgent,
        expected,
      );
      await store.close();
      store = openStore();
      expect((await store.getCurrentProfile())!.userAgent, expected);
    },
  );

  test('saves all imported drafts and rolls back a failed batch', () async {
    final records = ImportedConfiguration.parseMany(
      '192.0.2.7:8080:user:pass|first@example.com|tiktok|mail|1\n'
      '192.0.2.8:8080:user:pass|second@example.com|tiktok|mail',
    );
    final drafts = [
      for (final row in records)
        ProxyDraft(
          row.account.email,
          row.proxy,
          'batch-agent',
          account: row.account,
          statusAccount: row.statusAccount,
        ),
    ];
    final ids = await store.saveDrafts(drafts);
    expect(ids, hasLength(2));
    await store.close();
    store = openStore();
    final saved = await store.list();
    expect(saved, hasLength(2));
    expect(
      saved.singleWhere((entry) => entry.id == ids.first).statusAccount,
      AccountStatus.registered,
    );
    expect(
      saved.singleWhere((entry) => entry.id == ids.last).statusAccount,
      AccountStatus.unregistered,
    );
    expect(
      saved.every((entry) => entry.userAgent == firefoxDesktopUserAgent),
      isTrue,
    );
    expect(await store.getCurrentProfile(), isNull);
    await expectLater(
      store.saveDrafts([
        ProxyDraft(
          'changed',
          drafts.first.proxy,
          'changed-agent',
          account: drafts.first.account,
        ),
        // An unknown phone fails the batch after the first row was written.
        ProxyDraft('invalid', drafts.last.proxy, '', gpuProfileId: 'unknown'),
      ]),
      throwsFormatException,
    );
    final after = await store.list();
    expect(
      after.every((entry) => entry.userAgent == firefoxDesktopUserAgent),
      isTrue,
    );
    expect(
      after.singleWhere((entry) => entry.id == ids.first).name,
      'first@example.com',
    );
  });

  test(
    'one table stores camelCase account status and metadata edits update the active row',
    () async {
      const account = AccountCredentials(
        email: 'person@example.com',
        password: 'tiktok',
        mailboxPassword: 'mailbox',
      );
      final proxy = WebViewProxy.parse('192.0.2.7:8080')!;
      final id = await store.save(
        name: account.email,
        proxy: proxy,
        account: account,
      );
      await store.useSaved(id);
      expect(
        (await store.getCurrentProfile())!.statusAccount,
        AccountStatus.unregistered,
      );
      await store.save(
        id: id,
        name: account.email,
        proxy: proxy,
        account: account,
        statusAccount: AccountStatus.registered,
      );
      expect(
        (await store.getCurrentProfile())!.statusAccount,
        AccountStatus.registered,
      );
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(filename);
      final tables = await db.query(
        'sqlite_master',
        columns: ['name'],
        where:
            "type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      );
      expect(
        tables.map((e) => e['name']),
        unorderedEquals([
          'configurations',
          'nurture_accounts',
          'nurture_sessions',
          'app_settings',
          'signup_failures',
        ]),
      );
      final columns = await db.rawQuery('PRAGMA table_info(configurations)');
      expect(columns.map((e) => e['name']), contains('statusAccount'));
      expect(columns.map((e) => e['name']), isNot(contains('statusaccount')));
      expect(await db.query('configurations'), hasLength(1));
      await db.close();
      store = openStore();
      expect(
        (await store.getCurrentProfile())!.statusAccount,
        AccountStatus.registered,
      );
      await store.save(
        id: id,
        name: account.email,
        proxy: proxy,
        statusAccount: AccountStatus.unregistered,
      );
      expect(
        (await store.getCurrentProfile())!.statusAccount,
        AccountStatus.unregistered,
      );
    },
  );

  test(
    'migrates the earlier single-table status spelling without losing the selected account',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        filename,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            await db.execute(
              "CREATE TABLE configurations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
              'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL, '
              "account_email TEXT NOT NULL DEFAULT '', account_password TEXT NOT NULL DEFAULT '', "
              "mailbox_password TEXT NOT NULL DEFAULT '', statusaccount TEXT NOT NULL DEFAULT 'unregistered', "
              'has_been_used INTEGER NOT NULL DEFAULT 0, listed INTEGER NOT NULL DEFAULT 1, is_current INTEGER NOT NULL DEFAULT 0)',
            );
          },
        ),
      );
      await db.insert('configurations', {
        'name': 'Existing',
        'url': 'http://192.0.2.7:8080',
        'username': 'user',
        'password': 'pass',
        'user_agent': 'agent',
        'account_email': 'person@example.com',
        'account_password': 'tiktok',
        'mailbox_password': 'mailbox',
        'statusaccount': 'registered',
        'is_current': 1,
        'has_been_used': 1,
      });
      await db.close();
      final current = (await store.getCurrentProfile())!;
      expect(current.account!.email, 'person@example.com');
      expect(current.account!.password, 'tiktok');
      expect(current.account!.mailboxPassword, 'mailbox');
      expect(current.statusAccount, AccountStatus.registered);
      expect(
        (await store.list()).single.statusAccount,
        AccountStatus.registered,
      );
    },
  );

  test(
    'two accounts on one proxy remain independent and survive reopening',
    () async {
      final proxy = WebViewProxy.parse(
        '192.0.2.7:6149',
        username: 'proxy-user',
        password: 'proxy-pass',
      )!;
      const first = AccountCredentials(
        email: 'first@example.com',
        password: 'first-password',
        mailboxPassword: 'first-mail',
      );
      const second = AccountCredentials(
        email: 'second@example.com',
        password: 'second-password',
        mailboxPassword: 'second-mail',
      );
      final firstId = await store.save(
        name: 'First',
        proxy: proxy,
        userAgent: 'same-agent',
        account: first,
      );
      final secondId = await store.save(
        name: 'Second',
        proxy: proxy,
        userAgent: 'same-agent',
        account: second,
      );
      expect(secondId, isNot(firstId));
      await store.useSaved(secondId);
      await store.close();
      store = openStore();
      expect(await store.list(), hasLength(2));
      expect(
        sameAccount((await store.getCurrentProfile())!.account, second),
        isTrue,
      );
      final entries = await store.list();
      expect(entries.singleWhere((e) => e.id == firstId).hasBeenUsed, isFalse);
      expect(entries.singleWhere((e) => e.id == secondId).hasBeenUsed, isTrue);
      await store.useSaved(firstId);
      expect(
        sameAccount((await store.getCurrentProfile())!.account, first),
        isTrue,
      );
      await store.delete(firstId);
      expect(await store.getCurrentProfile(), isNull);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      await store.setCurrent(null);
      expect(await store.getCurrentProfile(), isNull);
    },
  );

  test('v3 migration preserves the active proxy and adds account storage', () async {
    final db = await databaseFactoryFfi.openDatabase(
      filename,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE proxies (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
            'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL, has_been_used INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            "CREATE TABLE current_proxy (id INTEGER PRIMARY KEY CHECK (id = 1), name TEXT NOT NULL DEFAULT '', "
            'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL)',
          );
        },
      ),
    );
    final values = {
      'name': 'Legacy',
      'url': 'http://192.0.2.7:8080',
      'username': 'user',
      'password': 'pass',
      'user_agent': 'legacy-agent',
    };
    final id = await db.insert('proxies', values);
    await db.insert('current_proxy', {'id': 1, ...values});
    await db.close();
    final current = (await store.getCurrentProfile())!;
    expect(current.proxy!.password, 'pass');
    expect(current.userAgent, firefoxDesktopUserAgent);
    expect(current.account, isNull);
    const account = AccountCredentials(
      email: 'person@example.com',
      password: 'tiktok',
      mailboxPassword: 'mailbox',
    );
    await store.save(
      id: id,
      name: 'Combined',
      proxy: current.proxy,
      account: account,
    );
    await store.useSaved(id);
    await store.close();
    store = openStore();
    expect(
      sameAccount((await store.getCurrentProfile())!.account, account),
      isTrue,
    );
    expect((await store.list()).single.userAgent, firefoxDesktopUserAgent);
  });

  test(
    'current proxy, credentials and named list survive reopening SQLite',
    () async {
      final proxy = WebViewProxy.parse(
        'https://proxy.example.com:443',
        username: ' user ',
        password: "p'ass\nword",
      )!;
      final id = await store.save(name: 'Office', proxy: proxy);
      await store.setCurrent(proxy);
      final userAgent = (await store.getCurrentProfile())!.userAgent;
      await store.close();
      store = openStore();

      expect(sameProxy(await store.getCurrent(), proxy), isTrue);
      final entries = await store.list();
      expect(entries.single.id, id);
      expect(entries.single.name, 'Office');
      expect(entries.single.userAgent, userAgent);
      expect(entries.single.hasBeenUsed, isTrue);
      expect((await store.getCurrentProfile())!.name, 'Office');
      expect((await store.getCurrentProfile())!.userAgent, userAgent);
      expect(entries.single.proxy!.username, 'user');
      expect(entries.single.proxy!.password, "p'ass\nword");
      expect(sameProxy(entries.single.proxy, proxy), isTrue);
    },
  );

  test(
    'editing and deleting saved entries preserve the current configuration',
    () async {
      final first = WebViewProxy.parse('127.0.0.1:80')!;
      final second = WebViewProxy.parse('http://[::1]:8080')!;
      final id = await store.save(name: 'First', proxy: first);
      await store.setCurrent(first);
      await store.save(id: id, name: 'Updated', proxy: second);
      expect((await store.list()).single.name, 'Updated');
      expect(sameProxy(await store.getCurrent(), first), isTrue);
      await store.delete(id);
      expect(await store.list(), isEmpty);
      expect(sameProxy(await store.getCurrent(), first), isTrue);
    },
  );

  test(
    'switching replaces the singleton and disabling persists without deleting the list',
    () async {
      final first = WebViewProxy.parse('127.0.0.1:8080')!;
      final second = WebViewProxy.parse('proxy.example.com:8888')!;
      await store.save(name: 'Saved', proxy: first);
      await store.setCurrent(first);
      await store.setCurrent(second);
      expect(sameProxy(await store.getCurrent(), second), isTrue);
      await store.setCurrent(null);
      await store.close();
      store = openStore();
      expect(await store.getCurrent(), isNull);
      expect(await store.list(), hasLength(1));
    },
  );

  test(
    'every proxy shares the Firefox User-Agent across switches and edits',
    () async {
      final first = WebViewProxy.parse('first.example.com:8080')!;
      final second = WebViewProxy.parse('second.example.com:8080')!;
      final firstId = await store.save(name: 'First', proxy: first);
      await store.save(name: 'Second', proxy: second);
      await store.setCurrent(first);
      final firstAgent = (await store.getCurrentProfile())!.userAgent;
      await store.setCurrent(second);
      final secondAgent = (await store.getCurrentProfile())!.userAgent;
      // GeckoView sends only Firefox with "Desktop site" on.
      expect(firstAgent, firefoxDesktopUserAgent);
      expect(secondAgent, firstAgent);
      await store.setCurrent(first);
      expect((await store.getCurrentProfile())!.userAgent, firstAgent);
      await store.save(id: firstId, name: 'Renamed', proxy: first);
      expect(
        (await store.list())
            .firstWhere((entry) => entry.id == firstId)
            .userAgent,
        firstAgent,
      );
      expect(await store.save(name: 'Duplicate', proxy: first), firstId);
      expect(await store.list(), hasLength(2));
      expect(nextAgent, 2);
    },
  );

  test(
    'persists the preview User-Agent without rerandomizing on save and activates edits explicitly',
    () async {
      final proxy = WebViewProxy.parse('localhost:8080')!;
      final preview = await store.generateUserAgent();
      final id = await store.save(
        name: 'Preview',
        proxy: proxy,
        userAgent: preview,
      );
      expect((await store.list()).single.userAgent, preview);
      expect(nextAgent, 1);
      await store.useSaved(id);
      final replacement = await store.generateUserAgent();
      await store.save(
        id: id,
        name: 'Edited',
        proxy: proxy,
        userAgent: replacement,
      );
      expect((await store.getCurrentProfile())!.userAgent, preview);
      await store.useSaved(id);
      await store.close();
      store = openStore();
      expect((await store.getCurrentProfile())!.userAgent, replacement);
      expect((await store.list()).single.userAgent, replacement);
      expect(nextAgent, 2);
    },
  );

  test(
    'selecting by saved id uses that profile User-Agent after editing its endpoint',
    () async {
      final first = WebViewProxy.parse('first.example.com:8080')!;
      final second = WebViewProxy.parse('second.example.com:8080')!;
      await store.save(name: 'First', proxy: first);
      final secondId = await store.save(name: 'Second', proxy: second);
      final secondAgent = (await store.list()).first.userAgent;
      await store.save(id: secondId, name: 'Edited', proxy: first);
      await store.useSaved(secondId);
      final current = (await store.getCurrentProfile())!;
      expect(sameProxy(current.proxy, first), isTrue);
      expect(current.userAgent, secondAgent);
    },
  );

  for (final alreadyListed in [false, true]) {
    test(
      'migrates v1 cached proxy and binds its User-Agent (listed: $alreadyListed)',
      () async {
        final db = await databaseFactoryFfi.openDatabase(
          filename,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE proxies (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                'name TEXT NOT NULL, url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL)',
              );
              await db.execute(
                'CREATE TABLE current_proxy (id INTEGER PRIMARY KEY CHECK (id = 1), '
                'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL)',
              );
            },
          ),
        );
        final values = {
          'url': 'http://legacy.example.com:8080',
          'username': 'user',
          'password': 'secret',
        };
        await db.insert('current_proxy', {'id': 1, ...values});
        if (alreadyListed) {
          await db.insert('proxies', {'name': 'Legacy', ...values});
        }
        await db.close();

        final current = (await store.getCurrentProfile())!;
        final entries = await store.list();
        expect(entries, hasLength(1));
        expect(sameProxy(entries.single.proxy, current.proxy), isTrue);
        expect(entries.single.proxy!.password, 'secret');
        expect(entries.single.userAgent, current.userAgent);
        expect(entries.single.hasBeenUsed, isTrue);
        expect(current.userAgent, isNotEmpty);
        expect(nextAgent, 1);
        await store.close();
        store = openStore();
        expect((await store.getCurrentProfile())!.userAgent, current.userAgent);
        expect(nextAgent, 1);
      },
    );
  }

  test(
    'usage starts unused, changes on successful apply and survives editing and reopening',
    () async {
      final first = WebViewProxy.parse('first.example.com:8080')!;
      final second = WebViewProxy.parse('second.example.com:8080')!;
      final firstId = await store.save(name: 'First', proxy: first);
      final secondId = await store.save(name: 'Second', proxy: second);
      expect((await store.list()).every((entry) => !entry.hasBeenUsed), isTrue);
      await store.useSaved(firstId);
      await store.save(id: firstId, name: 'Renamed', proxy: first);
      expect(
        (await store.list())
            .singleWhere((entry) => entry.id == firstId)
            .hasBeenUsed,
        isTrue,
      );
      await expectLater(store.useSaved(9999), throwsStateError);
      expect(
        (await store.list())
            .singleWhere((entry) => entry.id == secondId)
            .hasBeenUsed,
        isFalse,
      );
      await store.useSaved(secondId);
      await store.setUsed(firstId, false);
      await store.close();
      store = openStore();
      final entries = await store.list();
      expect(
        entries.singleWhere((entry) => entry.id == firstId).hasBeenUsed,
        isFalse,
      );
      expect(
        entries.singleWhere((entry) => entry.id == secondId).hasBeenUsed,
        isTrue,
      );
      expect((await store.getCurrentProfile())!.name, 'Second');
    },
  );

  test(
    'v2 migration preserves credentials and marks only the known current proxy as used',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        filename,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE proxies (id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'name TEXT NOT NULL, url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE current_proxy (id INTEGER PRIMARY KEY CHECK (id = 1), '
              'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL)',
            );
          },
        ),
      );
      final values = {
        'url': 'http://active.example.com:8080',
        'username': 'user',
        'password': 'secret',
        'user_agent': 'legacy-agent',
      };
      final activeId = await db.insert('proxies', {
        'name': 'Active',
        ...values,
      });
      await db.insert('proxies', {
        'name': 'Other',
        ...values,
        'url': 'http://other.example.com:8080',
      });
      await db.insert('current_proxy', {'id': 1, ...values});
      await db.close();
      final entries = await store.list();
      expect(
        entries.singleWhere((entry) => entry.id == activeId).hasBeenUsed,
        isTrue,
      );
      expect(
        entries.singleWhere((entry) => entry.id != activeId).hasBeenUsed,
        isFalse,
      );
      final current = (await store.getCurrentProfile())!;
      expect(current.name, 'Active');
      expect(current.proxy!.password, 'secret');
      expect(current.userAgent, firefoxDesktopUserAgent);
      expect(nextAgent, 0);
    },
  );
}
