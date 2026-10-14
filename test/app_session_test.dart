import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_session.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/desktop_user_agents.dart';
import 'package:test_tiktok/main.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';
import 'package:test_tiktok/screen/splash_page.dart';

import 'support/memory_proxy_store.dart';

final _platform = _SessionPlatform();

class _SessionPlatform extends InAppWebViewPlatform {
  final calls = <String>[];
  Completer<bool>? cookieGate;
  int webViewsCreated = 0;
  String? webViewUserAgent;
  String? nativeUserAgent;
  UserPreferredContentMode? contentMode;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) => _Storage(params);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Controller(const PlatformInAppWebViewControllerCreationParams(id: null));

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViewsCreated++;
    webViewUserAgent = params.initialSettings?.userAgent;
    contentMode = params.initialSettings?.preferredContentMode;
    return _WebView(params);
  }
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params) : super.implementation();

  @override
  Future<bool> deleteAllCookies() async {
    _platform.calls.add('cookies');
    return _platform.cookieGate == null
        ? true
        : await _platform.cookieGate!.future;
  }
}

class _Storage extends PlatformWebStorageManager {
  _Storage(super.params) : super.implementation();

  @override
  Future<void> deleteAllData() async {
    _platform.calls.add('android-storage');
  }

  @override
  Future<void> removeDataModifiedSince({
    required Set<WebsiteDataType> dataTypes,
    required DateTime date,
  }) async {
    expect(dataTypes, WebsiteDataType.ALL);
    expect(date.millisecondsSinceEpoch, 0);
    _platform.calls.add('apple-storage');
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller(super.params) : super.implementation();

  @override
  Future<String> getDefaultUserAgent() async {
    final agent = _platform.nativeUserAgent;
    if (agent == null) throw UnimplementedError();
    return agent;
  }

  @override
  Future<void> clearAllCache({bool includeDiskFiles = true}) async {
    expect(includeDiskFiles, isTrue);
    _platform.calls.add('cache');
  }
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InAppWebViewPlatform.instance = _platform;
    _platform.calls.clear();
    _platform.cookieGate = null;
    _platform.webViewsCreated = 0;
    _platform.webViewUserAgent = null;
    _platform.nativeUserAgent = null;
    _platform.contentMode = null;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'),
          null,
        );
  });

  test('iOS User-Agent list contains only Windows and macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(desktopUserAgents, hasLength(84));
    expect(desktopUserAgents.every((ua) => !ua.contains('Linux')), isTrue);
    expect(desktopUserAgents.any((ua) => ua.contains('Windows NT')), isTrue);
    expect(desktopUserAgents.any((ua) => ua.contains('Macintosh')), isTrue);
  });

  test('iOS replaces a previously stored Linux User-Agent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const linuxAgent =
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
    SharedPreferences.setMockInitialValues({
      'desktop_user_agent_direct': linuxAgent,
      'desktop_user_agents_used': [linuxAgent],
    });

    final selected = await loadDirectDesktopUserAgent();

    expect(desktopUserAgents, contains(selected));
    expect(selected, isNot(contains('Linux')));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'desktop_user_agent_direct',
      ),
      selected,
    );
  });

  test(
    'Android restores a saved Linux User-Agent across repeated loads',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const agent =
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      SharedPreferences.setMockInitialValues({
        'desktop_user_agent_direct': agent,
        'desktop_user_agents_used': [agent],
      });
      expect(await loadDirectDesktopUserAgent(), agent);
      await (await SharedPreferences.getInstance()).reload();
      expect(await loadDirectDesktopUserAgent(), agent);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        [agent],
      );
    },
  );

  test('Android preserves a saved Windows direct UA across launches', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const windowsAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    SharedPreferences.setMockInitialValues({
      'desktop_user_agent_direct': windowsAgent,
      'desktop_user_agents_used': [windowsAgent],
    });
    final selected = await loadDirectDesktopUserAgent();
    expect(selected, windowsAgent);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'desktop_user_agent_direct',
      ),
      selected,
    );
  });

  for (final platform in [TargetPlatform.iOS]) {
    test(
      '$platform uses every UA before repeating across cycle boundaries',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final firstCycle = <String>[];
        final secondCycle = <String>[];
        for (final cycle in [firstCycle, secondCycle]) {
          for (var i = 0; i < desktopUserAgents.length; i++) {
            cycle.add(await selectNextDesktopUserAgent());
            // Force subsequent selections to read what was persisted.
            await (await SharedPreferences.getInstance()).reload();
          }
          expect(cycle.toSet(), desktopUserAgents.toSet());
        }
        expect(secondCycle.first, isNot(firstCycle.last));
      },
    );
  }

  test(
    'Android randomizes Chrome versions without repeating UA across full cycles',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _platform.nativeUserAgent =
          'Mozilla/5.0 (Linux; Android 16; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/154.0.8037.107 Mobile Safari/537.36';
      final agents = <String>[];
      expect(androidDesktopUserAgents, hasLength(42));
      for (var i = 0; i < 84; i++) {
        final agent = await selectNextDesktopUserAgent();
        expect(agent, matches(r'Chrome/(12\d|13\d|140)\.0\.0\.0'));
        expect(agent, isNot(matches(r'Android|Mobile| wv|Macintosh')));
        if (agents.isNotEmpty) expect(agent, isNot(agents.last));
        agents.add(agent);
        await (await SharedPreferences.getInstance()).reload();
      }
      expect(agents.take(42).toSet(), androidDesktopUserAgents.toSet());
      expect(agents.skip(42).toSet(), androidDesktopUserAgents.toSet());
      expect(
        agents
            .take(42)
            .map((agent) => RegExp(r'Chrome/(\d+)').firstMatch(agent)!.group(1))
            .toSet(),
        hasLength(21),
      );
      expect(await loadDirectDesktopUserAgent(), agents.last);
      expect(await loadDirectDesktopUserAgent(), agents.last);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        agents.skip(42).toList(),
      );
    },
  );

  testWidgets(
    'Android change UA button updates the displayed UA on every tap',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _platform.nativeUserAgent = 'Chrome/154.0.8037.107';
      await tester.pumpWidget(
        MaterialApp(
          home: CreateProxyPage(generateUserAgent: selectNextDesktopUserAgent),
        ),
      );
      await tester.pumpAndSettle();
      String displayedAgent() => tester
          .widget<TextFormField>(find.byKey(const Key('savedProxyUserAgent')))
          .controller!
          .text;
      var previous = displayedAgent();
      expect(previous, matches(r'Chrome/(12\d|13\d|140)\.0\.0\.0'));
      final seen = {previous};
      for (var i = 0; i < 4; i++) {
        final button = find.byKey(const Key('generateProxyUserAgent'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(displayedAgent(), isNot(previous));
        expect(displayedAgent(), matches(r'Chrome/(12\d|13\d|140)\.0\.0\.0'));
        expect(seen.add(displayedAgent()), isTrue);
        previous = displayedAgent();
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'direct User-Agent reuses the last known identity instead of selecting a new one',
    () async {
      SharedPreferences.setMockInitialValues({
        'desktop_user_agents_used': [desktopUserAgents[7]],
      });
      expect(await loadDirectDesktopUserAgent(), desktopUserAgents[7]);
      expect(await loadDirectDesktopUserAgent(), desktopUserAgents[7]);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        [desktopUserAgents[7]],
      );
    },
  );

  test(
    'clears all Apple website data and cache without changing User-Agent',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await clearAppSession();
      expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        isNull,
      );
    },
  );

  testWidgets('shows Splash while loading before opening Home', (tester) async {
    await tester.pumpWidget(MyApp(proxyStore: MemoryProxyStore()));

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byKey(const Key('splashLoading')), findsOneWidget);
    expect(find.text('Tool TikTok'), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(SplashPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(_platform.calls, isEmpty);
  });

  testWidgets(
    'iOS opens the selected desktop UA even when native Safari discovery is available',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      _platform.nativeUserAgent =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse('proxy.example.com:8080')
        ..currentUserAgent = desktopUserAgents[5];
      final savedAgent = store.currentUserAgent;
      await tester.pumpWidget(MyApp(proxyStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(_platform.webViewUserAgent, savedAgent);
      expect(_platform.contentMode, UserPreferredContentMode.DESKTOP);
      expect(store.currentUserAgent, savedAgent);
      expect(_platform.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('startup and opening TikTok preserve cookies, storage and cache', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test_tiktok/webview_proxy'),
      (call) async => null,
    );
    // If startup tries to clear cookies, this unfinished gate will block Home.
    _platform.cookieGate = Completer<bool>();
    await tester.pumpWidget(MyApp(proxyStore: MemoryProxyStore()));
    await tester.pumpAndSettle();
    expect(_platform.calls, isEmpty);
    expect(_platform.webViewsCreated, 0);
    expect(find.byKey(const Key('resetSession')), findsNothing);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(_platform.webViewsCreated, 1);
    expect(_platform.calls, isEmpty);
    expect(desktopUserAgents, contains(_platform.webViewUserAgent));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'restarting the app keeps the direct User-Agent and browser session',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      final selected = <String>[];
      for (var launch = 0; launch < 2; launch++) {
        await tester.pumpWidget(MyApp(proxyStore: MemoryProxyStore()));
        await tester.pumpAndSettle();
        final userAgent = tester
            .widget<HomePage>(find.byType(HomePage))
            .userAgent;
        selected.add(userAgent);
        await tester.tap(find.byKey(const Key('openTikTok')));
        await tester.pumpAndSettle();
        expect(_platform.webViewUserAgent, userAgent);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await (await SharedPreferences.getInstance()).reload();
      }
      expect(selected.last, selected.first);
      expect(_platform.calls, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        hasLength(1),
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'configuration loading failure retries without clearing the browser session',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      final store = MemoryProxyStore()..failReads = true;
      await tester.pumpWidget(MyApp(proxyStore: store));
      await tester.pumpAndSettle();
      expect(
        find.text('Không thể tải cấu hình ứng dụng. Hãy thử lại.'),
        findsOneWidget,
      );
      expect(_platform.calls, isEmpty);
      expect(_platform.webViewsCreated, 0);
      store.failReads = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(_platform.calls, isEmpty);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(_platform.webViewsCreated, 1);
      expect(_platform.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'proxy User-Agent and session survive app restarts and WebView loads',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore()
        ..current = WebViewProxy.parse('proxy.example.com:8080')
        ..currentUserAgent = desktopUserAgents[5];
      final boundAgent = store.currentUserAgent;
      for (var launch = 0; launch < 2; launch++) {
        await tester.pumpWidget(MyApp(proxyStore: store));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HomePage>(find.byType(HomePage)).userAgent,
          boundAgent,
        );
        expect(find.byKey(const Key('resetSession')), findsNothing);
        expect(_platform.calls, isEmpty);
        await tester.tap(find.byKey(const Key('openTikTok')));
        await tester.pumpAndSettle();
        expect(_platform.webViewUserAgent, boundAgent);
        expect(_platform.calls, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        isNull,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'only applying a new proxy clears the session and its User-Agent survives restart',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      _platform.nativeUserAgent =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      final store = MemoryProxyStore();
      final boundAgent = desktopUserAgents[11];
      final id = await store.save(
        name: 'New proxy',
        proxy: WebViewProxy.parse('proxy.example.com:8080')!,
        userAgent: boundAgent,
      );
      await tester.pumpWidget(MyApp(proxyStore: store));
      await tester.pumpAndSettle();
      expect(_platform.calls, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('manageProxies')));
      await tester.tap(find.byKey(const Key('manageProxies')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('savedProxy-$id')));
      await tester.pumpAndSettle();
      expect(_platform.calls, isEmpty);
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(_platform.webViewUserAgent, boundAgent);
      expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      _platform.calls.clear();
      await tester.pumpWidget(MyApp(proxyStore: store));
      await tester.pumpAndSettle();
      expect(_platform.calls, isEmpty);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(_platform.webViewUserAgent, boundAgent);
      expect(_platform.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
