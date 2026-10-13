import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';
import 'package:test_tiktok/screen/proxy_management_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  const record = '192.0.2.7:9323:proxy-user:proxy-password';
  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

  test('imports proxy address, port and separate credentials', () {
    final proxy = WebViewProxy.parseImport(record);
    expect(proxy.uri.toString(), 'http://192.0.2.7:9323');
    expect(proxy.uri.userInfo, isEmpty);
    expect(proxy.username, 'proxy-user');
    expect(proxy.password, 'proxy-password');
  });

  test('import preserves password characters and accepts copied line endings',
      () {
    final proxy = WebViewProxy.parseImport(
        '\r\nproxy.example.com:8080:user: pass:word \r\n');
    expect(proxy.uri.host, 'proxy.example.com');
    expect(proxy.password, ' pass:word ');
  });

  test('import rejects invalid ports, missing credentials and multiple rows',
      () {
    for (final invalid in [
      '',
      '192.0.2.7:9323',
      '192.0.2.7:9323:user',
      '192.0.2.7:9323::password',
      '192.0.2.7:9323:user:',
      '192.0.2.7:9323:user:   ',
      '192.0.2.7:0:user:password',
      '192.0.2.7:65536:user:password',
      '192.0.2.7:abc:user:password',
      'local host:8080:user:password',
      'proxy.example.com/path:8080:user:password',
      '$record\n$record',
    ]) {
      expect(() => WebViewProxy.parseImport(invalid), throwsFormatException);
    }
  });

  testWidgets('import requires a manually entered name before persisting proxy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryProxyStore();
    await tester
        .pumpWidget(MaterialApp(home: ProxyManagementPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    final agent = text(tester, 'savedProxyUserAgent');
    await tester.enterText(find.byKey(const Key('proxyImportData')), record);
    await tester.tap(find.byKey(const Key('importProxyData')));
    await tester.pumpAndSettle();
    expect(text(tester, 'savedProxyName'), isEmpty);
    expect(text(tester, 'savedProxyUrl'), 'http://192.0.2.7:9323');
    expect(text(tester, 'savedProxyUsername'), 'proxy-user');
    expect(text(tester, 'savedProxyPassword'), 'proxy-password');
    expect(text(tester, 'savedProxyUserAgent'), agent);
    expect(text(tester, 'proxyImportData'), isEmpty);
    expect(store.entries, isEmpty);
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên proxy.'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.enterText(find.byKey(const Key('savedProxyName')), 'My proxy');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.name, 'My proxy');
    expect(store.entries.single.proxy.password, 'proxy-password');
    expect(store.entries.single.userAgent, agent);
    expect(store.current, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paste button fills proxy import data from clipboard',
      (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': record};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: CreateProxyPage(generateUserAgent: () async => 'test-agent')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pasteProxyData')));
    await tester.pump();

    expect(text(tester, 'proxyImportData'), record);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing has no import and preserves name and User-Agent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryProxyStore();
    await store.save(
        name: 'Chosen name',
        proxy: WebViewProxy.parse('original.example.com:8080')!,
        userAgent: 'chosen-agent');
    await tester
        .pumpWidget(MaterialApp(home: ProxyManagementPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tùy chọn proxy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proxyImportData')), findsNothing);
    expect(find.byKey(const Key('importProxyData')), findsNothing);
    await tester.enterText(
        find.byKey(const Key('savedProxyUrl')), 'http://192.0.2.7:9323');
    await tester.enterText(
        find.byKey(const Key('savedProxyUsername')), 'proxy-user');
    await tester.enterText(
        find.byKey(const Key('savedProxyPassword')), 'proxy-password');
    await tester.pumpAndSettle();
    expect(text(tester, 'savedProxyName'), 'Chosen name');
    expect(text(tester, 'savedProxyUserAgent'), 'chosen-agent');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.name, 'Chosen name');
    expect(store.entries.single.userAgent, 'chosen-agent');
    expect(store.entries.single.proxy.uri.host, '192.0.2.7');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid import leaves existing fields intact and can be corrected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: CreateProxyPage(generateUserAgent: () async => 'test-agent')));
    await tester.pumpAndSettle();
    final originals = {
      'savedProxyName': 'Entered name',
      'savedProxyUrl': 'https://original.example.com:443',
      'savedProxyUsername': 'original-user',
      'savedProxyPassword': 'original-password',
    };
    for (final entry in originals.entries) {
      await tester.enterText(find.byKey(Key(entry.key)), entry.value);
    }
    await tester.enterText(find.byKey(const Key('proxyImportData')),
        '192.0.2.7:99999:user:password');
    await tester.tap(find.byKey(const Key('importProxyData')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập proxy HTTP/HTTPS dạng host:port.'), findsOneWidget);
    for (final entry in originals.entries) {
      expect(text(tester, entry.key), entry.value);
    }
    await tester.enterText(find.byKey(const Key('proxyImportData')), record);
    await tester.pumpAndSettle();
    expect(find.text('Nhập proxy HTTP/HTTPS dạng host:port.'), findsNothing);
    await tester.tap(find.byKey(const Key('importProxyData')));
    await tester.pumpAndSettle();
    expect(text(tester, 'savedProxyName'), 'Entered name');
    expect(text(tester, 'savedProxyUserAgent'), 'test-agent');
    expect(text(tester, 'savedProxyUrl'), 'http://192.0.2.7:9323');
    expect(tester.takeException(), isNull);
  });
}
