import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_tiktok/core/account_sessions.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/controller/proxy_management_controller.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('test_tiktok/gecko_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late String filename;
  late ProxyStore store;
  final clearedContexts = <String>[];
  const first = AccountCredentials(
    email: 'first@example.test',
    password: 'fake-password',
    dataMail: 'fake-mail-data',
  );
  const second = AccountCredentials(
    email: 'second@example.test',
    password: 'other-fake-password',
    dataMail: 'other-fake-mail-data',
  );

  setUp(() async {
    // Every test uses its own disposable DB and fake preferences/native API.
    directory = await Directory.systemTemp.createTemp('configuration_delete_');
    filename = path.join(directory.path, 'test.db');
    store = ProxyStore(
      factory: databaseFactoryFfi,
      databasePath: filename,
      selectUserAgent: () async => 'test-agent',
    );
    SharedPreferences.setMockInitialValues({});
    clearedContexts.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'clearContext') {
        throw StateError('Unexpected global clear');
      }
      clearedContexts.add((call.arguments as Map)['contextId'] as String);
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<int> account(AccountCredentials credentials, {String? proxy}) =>
      store.save(
        name: credentials.email,
        proxy: proxy == null ? null : WebViewProxy.parse(proxy),
        account: credentials,
        statusAccount: AccountStatus.registered,
      );

  Future<void> history(
    String id,
    AccountCredentials credentials,
    int? config,
  ) async {
    await store.nurture.beginSession(
      id: id,
      email: credentials.email,
      configurationId: config,
      plan: const NurturePlan(NurtureMode.feed),
      phase: 'completed',
    );
    await store.nurture.saveProgress(
      id,
      1,
      const NurtureTotals(watchMilliseconds: 5000, videos: 1, fullVideos: 1),
    );
  }

  Future<Database> inspect() async {
    await store.close();
    return databaseFactoryFfi.openDatabase(filename);
  }

  test(
    'selected registered account is physically removed, other account survives',
    () async {
      final removed = await account(first);
      final kept = await account(second);
      await history('removed-history', first, removed);
      await history('old-detached-history', first, null);
      await history('kept-history', second, kept);
      await store.useSaved(removed);
      await store.setCurrentAccountLoggedIn(removed, first.email, true);
      await AccountSessions.save(kept, second.email);
      await AccountSessions.save(removed, first.email);
      final logic = ProxyManagementController(store: store);
      await logic.delete(
        (await store.list()).singleWhere((e) => e.id == removed),
      );
      expect(logic.loadFailed, isFalse);
      expect(clearedContexts, ['profile-$removed']);
      expect(await store.getCurrentProfile(), isNull);
      expect(await store.canReuseCurrentAccountSession(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('tiktok_gecko_session_valid_$removed'), isFalse);
      expect(prefs.containsKey('tiktok_session_owner_v2'), isFalse);
      expect(prefs.getBool('tiktok_gecko_session_valid_$kept'), isTrue);
      final db = await inspect();
      expect((await db.query('configurations')).single['id'], kept);
      expect(
        (await db.query('nurture_accounts')).single['email'],
        second.email,
      );
      expect((await db.query('nurture_sessions')).single['id'], 'kept-history');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await db.close();
    },
  );

  test('deleting an account also removes its hidden edited snapshot', () async {
    final id = await account(first, proxy: 'http://192.0.2.1:8080');
    await store.useSaved(id);
    await store.save(
      id: id,
      name: 'Edited',
      proxy: WebViewProxy.parse('http://192.0.2.2:8080'),
      account: first,
    );
    expect((await store.getCurrentProfile())!.configurationId, isNot(id));
    await store.delete(id);
    expect(await store.getCurrentProfile(), isNull);
    final db = await inspect();
    expect(await db.query('configurations'), isEmpty);
    expect(await db.query('nurture_accounts'), isEmpty);
    await db.close();
  });

  test(
    'another saved configuration for the same email retains its own data',
    () async {
      final removed = await account(first, proxy: 'http://192.0.2.1:8080');
      final kept = await account(first, proxy: 'http://192.0.2.2:8080');
      await history('removed', first, removed);
      await history('kept', first, kept);
      await store.useSaved(kept);
      await store.setCurrentAccountLoggedIn(kept, first.email, true);
      await store.delete(removed);
      expect((await store.getCurrentProfile())!.configurationId, kept);
      expect(await store.canReuseCurrentAccountSession(), isTrue);
      final db = await inspect();
      expect((await db.query('configurations')).single['id'], kept);
      expect((await db.query('nurture_sessions')).single['id'], 'kept');
      expect((await db.query('nurture_accounts')).single['email'], first.email);
      await db.close();
    },
  );

  test(
    'a storage clear failure keeps the configuration available for retry',
    () async {
      final id = await account(first);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'clear_failed');
      });
      final logic = ProxyManagementController(store: store);
      await logic.delete((await store.list()).single);
      expect(logic.loadFailed, isTrue);
      expect((await store.list()).single.id, id);
    },
  );

  test('deleting unregistered account cascades its failure log', () async {
    final id = await store.save(name: 'Failed', proxy: null, account: first);
    await store.recordSignupFailure(id, first.email, message: 'fake failure');
    await store.useSaved(id);
    await store.delete(id);
    await store.delete(id); // Repeating the request is harmless.
    final db = await inspect();
    expect(await db.query('configurations'), isEmpty);
    expect(await db.query('signup_failures'), isEmpty);
    expect(await db.query('nurture_accounts'), isEmpty);
    await db.close();
  });
}
