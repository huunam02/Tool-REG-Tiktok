import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late ProxyStore store;
  late String filename;
  var nextAgent = 0;

  ProxyStore openStore() => ProxyStore(
      factory: databaseFactoryFfi,
      databasePath: filename,
      selectUserAgent: () async => 'test-user-agent-${nextAgent++}');

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

  test('current proxy, credentials and named list survive reopening SQLite',
      () async {
    final proxy = WebViewProxy.parse('https://proxy.example.com:443',
        username: ' user ', password: "p'ass\nword")!;
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
    expect(entries.single.proxy.username, 'user');
    expect(entries.single.proxy.password, "p'ass\nword");
    expect(sameProxy(entries.single.proxy, proxy), isTrue);
  });

  test('editing and deleting saved entries preserve the current configuration',
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
  });

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
  });

  test('switching between proxies restores their distinct User-Agents',
      () async {
    final first = WebViewProxy.parse('first.example.com:8080')!;
    final second = WebViewProxy.parse('second.example.com:8080')!;
    final firstId = await store.save(name: 'First', proxy: first);
    await store.save(name: 'Second', proxy: second);
    await store.setCurrent(first);
    final firstAgent = (await store.getCurrentProfile())!.userAgent;
    await store.setCurrent(second);
    final secondAgent = (await store.getCurrentProfile())!.userAgent;
    expect(secondAgent, isNot(firstAgent));
    await store.setCurrent(first);
    expect((await store.getCurrentProfile())!.userAgent, firstAgent);
    await store.save(id: firstId, name: 'Renamed', proxy: first);
    expect(
        (await store.list())
            .firstWhere((entry) => entry.id == firstId)
            .userAgent,
        firstAgent);
    expect(await store.save(name: 'Duplicate', proxy: first), firstId);
    expect(await store.list(), hasLength(2));
    expect(nextAgent, 2);
  });

  test(
      'persists the preview User-Agent without rerandomizing on save and activates edits explicitly',
      () async {
    final proxy = WebViewProxy.parse('localhost:8080')!;
    final preview = await store.generateUserAgent();
    final id =
        await store.save(name: 'Preview', proxy: proxy, userAgent: preview);
    expect((await store.list()).single.userAgent, preview);
    expect(nextAgent, 1);
    await store.useSaved(id);
    final replacement = await store.generateUserAgent();
    await store.save(
        id: id, name: 'Edited', proxy: proxy, userAgent: replacement);
    expect((await store.getCurrentProfile())!.userAgent, preview);
    await store.useSaved(id);
    await store.close();
    store = openStore();
    expect((await store.getCurrentProfile())!.userAgent, replacement);
    expect((await store.list()).single.userAgent, replacement);
    expect(nextAgent, 2);
  });

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
  });

  for (final alreadyListed in [false, true]) {
    test(
        'migrates v1 cached proxy and binds its User-Agent (listed: $alreadyListed)',
        () async {
      final db = await databaseFactoryFfi.openDatabase(filename,
          options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, _) async {
                await db.execute(
                    'CREATE TABLE proxies (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                    'name TEXT NOT NULL, url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL)');
                await db.execute(
                    'CREATE TABLE current_proxy (id INTEGER PRIMARY KEY CHECK (id = 1), '
                    'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL)');
              }));
      final values = {
        'url': 'http://legacy.example.com:8080',
        'username': 'user',
        'password': 'secret'
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
      expect(entries.single.proxy.password, 'secret');
      expect(entries.single.userAgent, current.userAgent);
      expect(entries.single.hasBeenUsed, isTrue);
      expect(current.userAgent, isNotEmpty);
      expect(nextAgent, 1);
      await store.close();
      store = openStore();
      expect((await store.getCurrentProfile())!.userAgent, current.userAgent);
      expect(nextAgent, 1);
    });
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
        isTrue);
    await expectLater(store.useSaved(9999), throwsStateError);
    expect(
        (await store.list())
            .singleWhere((entry) => entry.id == secondId)
            .hasBeenUsed,
        isFalse);
    await store.useSaved(secondId);
    await store.setUsed(firstId, false);
    await store.close();
    store = openStore();
    final entries = await store.list();
    expect(entries.singleWhere((entry) => entry.id == firstId).hasBeenUsed,
        isFalse);
    expect(entries.singleWhere((entry) => entry.id == secondId).hasBeenUsed,
        isTrue);
    expect((await store.getCurrentProfile())!.name, 'Second');
  });

  test(
      'v2 migration preserves credentials and marks only the known current proxy as used',
      () async {
    final db = await databaseFactoryFfi.openDatabase(filename,
        options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await db.execute(
                  'CREATE TABLE proxies (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                  'name TEXT NOT NULL, url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE current_proxy (id INTEGER PRIMARY KEY CHECK (id = 1), '
                  'url TEXT NOT NULL, username TEXT NOT NULL, password TEXT NOT NULL, user_agent TEXT NOT NULL)');
            }));
    final values = {
      'url': 'http://active.example.com:8080',
      'username': 'user',
      'password': 'secret',
      'user_agent': 'legacy-agent'
    };
    final activeId = await db.insert('proxies', {'name': 'Active', ...values});
    await db.insert('proxies',
        {'name': 'Other', ...values, 'url': 'http://other.example.com:8080'});
    await db.insert('current_proxy', {'id': 1, ...values});
    await db.close();
    final entries = await store.list();
    expect(entries.singleWhere((entry) => entry.id == activeId).hasBeenUsed,
        isTrue);
    expect(entries.singleWhere((entry) => entry.id != activeId).hasBeenUsed,
        isFalse);
    final current = (await store.getCurrentProfile())!;
    expect(current.name, 'Active');
    expect(current.proxy.password, 'secret');
    expect(current.userAgent, 'legacy-agent');
    expect(nextAgent, 0);
  });
}
