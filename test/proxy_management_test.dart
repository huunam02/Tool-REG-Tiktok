import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';
import 'package:test_tiktok/screen/edit_proxy_page.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/proxy_management_page.dart';

import 'support/memory_proxy_store.dart';
import 'support/test_session_platform.dart';

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

Future<void> openManager(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('manageProxies')));
  await tester.tap(find.byKey(const Key('manageProxies')));
  await tester.pumpAndSettle();
}

Future<void> fillAccount(WidgetTester tester) async {
  for (final (key, value) in [
    ('savedAccountEmail', 'person@example.com'),
    ('savedAccountPassword', 'tiktok-password'),
    ('savedMailboxPassword', 'mailbox-password'),
  ]) {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), value);
  }
}

void main() {
  final session = TestSessionPlatform();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'desktop_user_agent_direct': 'direct-agent',
    });
    session.calls.clear();
    session.cookieGate = null;
    session.cacheGate = null;
    InAppWebViewPlatform.instance = session;
  });
  testWidgets('manager adds, validates, edits and deletes list entries', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateProxyPage), findsOneWidget);
    expect(find.byType(EditProxyPage), findsNothing);
    expect(fieldText(tester, 'savedProxyUrl'), isEmpty);
    expect(find.byKey(const Key('savedProxyName')), findsNothing);
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập địa chỉ proxy.'), findsNothing);
    expect(find.text('Nhập email tài khoản hợp lệ.'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.enterText(
      find.byKey(const Key('savedProxyUrl')),
      'https://office.example.com:443',
    );
    await tester.ensureVisible(find.byKey(const Key('savedProxyPassword')));
    await tester.enterText(
      find.byKey(const Key('savedProxyPassword')),
      'secret',
    );
    await fillAccount(tester);
    expect(
      tester.getTopLeft(find.byKey(const Key('savedProxyUserAgent'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('savedProxyPassword'))).dy,
      ),
    );
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.account!.email, 'person@example.com');
    final userAgent = store.entries.single.userAgent;
    expect(store.current, isNull);
    // Saving never makes a configuration the one in use.
    expect(store.entries.single.proxy!.password, 'secret');

    await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProxyPage), findsOneWidget);
    expect(find.byType(CreateProxyPage), findsNothing);
    expect(find.byKey(const Key('savedProxyName')), findsNothing);
    expect(fieldText(tester, 'savedProxyPassword'), 'secret');
    expect(
      tester.getTopLeft(find.byKey(const Key('savedProxyUserAgent'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('savedProxyPassword'))).dy,
      ),
    );
    expect(
      fieldText(tester, 'savedProxyUrl'),
      'https://office.example.com:443',
    );
    await tester.ensureVisible(find.byKey(const Key('savedAccountEmail')));
    await tester.enterText(
      find.byKey(const Key('savedAccountEmail')),
      'updated@example.com',
    );
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.account!.email, 'updated@example.com');
    expect(store.entries.single.userAgent, userAgent);

    await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.byKey(const Key('savedProxy-1')), findsNothing);
    expect(find.byKey(const Key('addProxy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves an empty proxy as the device default network', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    await fillAccount(tester);
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();

    expect(store.entries, hasLength(1));
    expect(store.entries.single.proxy, isNull);
    expect(find.text('Mặc định của máy'), findsOneWidget);
  });

  testWidgets(
    'editor defaults to a random User-Agent and saves the regenerated preview',
    (tester) async {
      final store = MemoryProxyStore();
      await tester.pumpWidget(
        MaterialApp(home: ProxyManagementPage(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addProxy')));
      await tester.pumpAndSettle();
      final firstAgent = fieldText(tester, 'savedProxyUserAgent');
      expect(firstAgent, isNotEmpty);
      await tester.ensureVisible(
        find.byKey(const Key('generateProxyUserAgent')),
      );
      await tester.tap(find.byKey(const Key('generateProxyUserAgent')));
      await tester.pumpAndSettle();
      final secondAgent = fieldText(tester, 'savedProxyUserAgent');
      expect(secondAgent, isNot(firstAgent));
      await tester.ensureVisible(find.byKey(const Key('savedProxyUrl')));
      await tester.enterText(
        find.byKey(const Key('savedProxyUrl')),
        'localhost:8080',
      );
      await fillAccount(tester);
      await tester.tap(find.byKey(const Key('saveProxyEntry')));
      await tester.pumpAndSettle();
      expect(store.entries.single.userAgent, secondAgent);
      await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'savedProxyUserAgent'), secondAgent);
      await tester.ensureVisible(
        find.byKey(const Key('generateProxyUserAgent')),
      );
      await tester.tap(find.byKey(const Key('generateProxyUserAgent')));
      await tester.pumpAndSettle();
      final editedAgent = fieldText(tester, 'savedProxyUserAgent');
      await tester.tap(find.byKey(const Key('saveProxyEntry')));
      await tester.pumpAndSettle();
      expect(editedAgent, isNot(secondAgent));
      expect(store.entries.single.userAgent, editedAgent);
      expect(session.calls, isEmpty);
    },
  );

  testWidgets(
    'Home reports read failure and retries without changing cached data',
    (tester) async {
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse('localhost:8080')
        ..failReads = true;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retryProxyCache')), findsOneWidget);
      expect(store.current!.uri.port, 8080);
      store.failReads = false;
      await tester.tap(find.byKey(const Key('retryProxyCache')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retryProxyCache')), findsNothing);
      expect(store.current!.uri.port, 8080);
    },
  );

  testWidgets('manager and editor fit a narrow screen with enlarged text', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    await store.save(
      name: 'Proxy with a long descriptive name',
      proxy: WebViewProxy.parse(
        'long.proxy.example.com:8080',
        username: 'username',
      )!,
    );
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: ProxyManagementPage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('generateProxyUserAgent')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProxyPage), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('generateProxyUserAgent')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('usage filters and search show only matching proxies', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    final usedId = await store.save(
      name: 'Office',
      proxy: WebViewProxy.parse('office.example.com:8080')!,
    );
    final unusedId = await store.save(
      name: 'Backup',
      proxy: WebViewProxy.parse('backup.example.com:8080')!,
    );
    await store.setUsed(usedId, true);
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-unused')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('savedProxy-$unusedId')), findsOneWidget);
    expect(find.byKey(Key('savedProxy-$usedId')), findsNothing);
    await tester.tap(find.byKey(const Key('filter-used')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('savedProxy-$usedId')), findsOneWidget);
    expect(find.byKey(Key('savedProxy-$unusedId')), findsNothing);
    expect(
      store.entries.singleWhere((entry) => entry.id == usedId).hasBeenUsed,
      isTrue,
    );
    expect(
      store.entries.singleWhere((entry) => entry.id == unusedId).hasBeenUsed,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('searchProxies')),
      'backup.example.com',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(Key('savedProxy-$unusedId')), findsOneWidget);
    expect(find.byKey(Key('savedProxy-$usedId')), findsNothing);
    expect(session.calls, isEmpty);
  });
}
