import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';
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
  testWidgets(
    'Home only displays the active proxy and restores its User-Agent',
    (tester) async {
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse(
          'https://proxy.example.com:443',
          username: 'user',
          password: 'secret',
        )
        ..currentUserAgent = 'bound-user-agent';
      for (final agent in ['first-session', 'another-session']) {
        await tester.pumpWidget(
          MaterialApp(
            home: HomePage(userAgent: agent, proxyStore: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('https://proxy.example.com:443'), findsOneWidget);
        expect(find.text('user'), findsOneWidget);
        expect(find.text('secret'), findsOneWidget);
        expect(store.currentUserAgent, 'bound-user-agent');
        for (final key in [
          'proxyUrl',
          'proxyUsername',
          'proxyPassword',
          'saveCurrentProxy',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
        expect(find.text('Lưu vào danh sách'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'Set switches proxy and User-Agent together and switching back restores them',
    (tester) async {
      final store = MemoryProxyStore();
      final first = WebViewProxy.parse('first.example.com:8000')!;
      final second = WebViewProxy.parse(
        'second.example.com:8080',
        username: 'second-user',
        password: 'second-secret',
      )!;
      final firstId = await store.save(name: 'First', proxy: first);
      final secondId = await store.save(name: 'Second', proxy: second);
      await store.setCurrent(first);
      final firstAgent = store.currentUserAgent;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in [secondId, firstId]) {
        final oldProxy = store.current;
        final oldAgent = store.currentUserAgent;
        final selected = store.entries.singleWhere((entry) => entry.id == id);
        await openManager(tester);
        await tester.scrollUntilVisible(
          find.byKey(Key('savedProxy-$id')),
          180,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('proxyListScroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tapAt(
          tester.getTopLeft(find.byKey(Key('savedProxy-$id'))) +
              const Offset(30, 30),
        );
        await tester.pumpAndSettle();
        expect(sameProxy(store.current, oldProxy), isTrue);
        expect(store.currentUserAgent, oldAgent);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const Key('selectedProxyUserAgent')),
              )
              .data,
          selected.userAgent,
        );
        await tester.tap(find.byKey(const Key('setSelectedProxy')));
        await tester.pumpAndSettle();
        expect(find.byType(ProxyManagementPage), findsNothing);
        expect(sameProxy(store.current, selected.proxy), isTrue);
        expect(find.text(proxyAddress(selected.proxy)), findsOneWidget);
        expect(store.currentUserAgent, selected.userAgent);
      }
      expect(store.currentUserAgent, firstAgent);
      await openManager(tester);
      await tester.tap(find.byKey(const Key('disableProxy')));
      await tester.pumpAndSettle();
      expect(store.current, isNull);
      expect(find.text('Kết nối trực tiếp — không dùng proxy'), findsOneWidget);
      expect(store.entries, hasLength(2));
      expect(
        session.calls,
        hasLength(6),
      ); // Only the two different proxies clear the session.
    },
  );

  testWidgets('setting the same proxy again preserves cookies and session', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    final id = await store.save(
      name: 'Current',
      proxy: WebViewProxy.parse('localhost:8080')!,
    );
    await store.useSaved(id);
    final oldAgent = store.currentUserAgent;
    session.cookieGate = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setSelectedProxy')));
    await tester.pumpAndSettle();
    expect(session.calls, isEmpty);
    expect(store.current!.uri.port, 8080);
    expect(store.currentUserAgent, oldAgent);
  });

  testWidgets('disabling a proxy keeps the browser session', (tester) async {
    final store = MemoryProxyStore()
      ..current = WebViewProxy.parse('localhost:8080');
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disableProxy')));
    await tester.pumpAndSettle();
    expect(store.current, isNull);
    expect(session.calls, isEmpty);
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
    expect(find.text('Nhập địa chỉ proxy.'), findsOneWidget);
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
    expect(find.text('secret'), findsOneWidget);

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

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform Set waits for cookies, storage and cache before changing the current proxy',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final store = MemoryProxyStore()
          ..current = WebViewProxy.parse('localhost:8000');
        final id = await store.save(
          name: 'New',
          proxy: WebViewProxy.parse('localhost:9000')!,
        );
        final oldAgent = store.currentUserAgent;
        session.cookieGate = Completer<bool>();
        session.cacheGate = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(home: ProxyManagementPage(store: store)),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getTopLeft(find.byKey(Key('savedProxy-$id'))) +
              const Offset(30, 30),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('setSelectedProxy')));
        await tester.pump();
        expect(session.calls, ['cookies']);
        expect(store.current!.uri.port, 8000);
        expect(store.currentUserAgent, oldAgent);
        expect(store.entries.single.hasBeenUsed, isFalse);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('setSelectedProxy')))
              .onPressed,
          isNull,
        );
        session.cookieGate!.complete(false);
        await tester.pump();
        expect(session.calls, [
          'cookies',
          platform == TargetPlatform.android
              ? 'android-storage'
              : 'apple-storage',
          'cache',
        ]);
        expect(store.current!.uri.port, 8000);
        session.cacheGate!.complete();
        await tester.pumpAndSettle();
        expect(store.current!.uri.port, 9000);
        expect(store.currentUserAgent, store.entries.single.userAgent);
        expect(store.entries.single.hasBeenUsed, isTrue);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'session clear failure keeps the current proxy and User-Agent and allows retry',
    (tester) async {
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse('localhost:8000');
      final id = await store.save(
        name: 'New',
        proxy: WebViewProxy.parse('localhost:9000')!,
      );
      final oldAgent = store.currentUserAgent;
      session.cookieGate = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(home: ProxyManagementPage(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('savedProxy-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pump();
      session.cookieGate!.completeError(StateError('Cannot clear cookies'));
      await tester.pumpAndSettle();
      expect(store.current!.uri.port, 8000);
      expect(store.currentUserAgent, oldAgent);
      expect(session.calls, ['cookies']);
      expect(store.entries.single.hasBeenUsed, isFalse);
      expect(
        find.text(
          'Không thể xóa phiên. Cấu hình đang sử dụng chưa thay đổi. Hãy thử lại.',
        ),
        findsOneWidget,
      );
      session.cookieGate = null;
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Thử lại'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Thử lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(store.current!.uri.port, 9000);
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
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('openTikTok')))
            .onPressed,
        isNull,
      );
      expect(store.current!.uri.port, 8080);
      store.failReads = false;
      await tester.tap(find.byKey(const Key('retryProxyCache')));
      await tester.pumpAndSettle();
      expect(find.text('http://localhost:8080'), findsOneWidget);
      expect(find.byKey(const Key('retryProxyCache')), findsNothing);
    },
  );

  testWidgets(
    'failed Set keeps the old proxy and User-Agent, then allows retry',
    (tester) async {
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse('localhost:8000');
      final id = await store.save(
        name: 'New',
        proxy: WebViewProxy.parse('localhost:9000')!,
      );
      final oldAgent = store.currentUserAgent;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(Key('savedProxy-$id')));
      await tester.pumpAndSettle();
      store.failWrites = true;
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(store.current!.uri.port, 8000);
      expect(store.currentUserAgent, oldAgent);
      expect(find.byType(ProxyManagementPage), findsOneWidget);
      expect(
        find.text('Không thể đọc hoặc lưu cấu hình. Hãy thử lại.'),
        findsOneWidget,
      );
      store.failWrites = false;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Thử lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(store.current!.uri.port, 9000);
      expect(store.currentUserAgent, store.entries.single.userAgent);
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

  testWidgets(
    'current proxy displays its complete User-Agent and password directly',
    (tester) async {
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse(
          'proxy.example.com:8080',
          username: 'full-user',
          password: 'full-secret',
        )
        ..currentUserAgent = 'Mozilla/5.0 test full browser identity';
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('currentProxyUserAgent')),
            )
            .data,
        store.currentUserAgent,
      );
      expect(find.text('full-user'), findsOneWidget);
      expect(find.text('full-secret'), findsOneWidget);
      expect(find.byKey(const Key('currentProxyShowPassword')), findsNothing);
    },
  );

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
