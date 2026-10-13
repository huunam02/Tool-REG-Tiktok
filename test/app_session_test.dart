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
import 'package:test_tiktok/screen/splash_page.dart';

import 'support/memory_proxy_store.dart';

final _platform = _SessionPlatform();

class _SessionPlatform extends InAppWebViewPlatform {
  final calls = <String>[];
  Completer<bool>? cookieGate;
  int webViewsCreated = 0;
  String? webViewUserAgent;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) =>
      _Cookies(params);

  @override
  PlatformWebStorageManager createPlatformWebStorageManager(
    PlatformWebStorageManagerCreationParams params,
  ) =>
      _Storage(params);

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Controller(const PlatformInAppWebViewControllerCreationParams(id: null));

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViewsCreated++;
    webViewUserAgent = params.initialSettings?.userAgent;
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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('test_tiktok/webview_proxy'), null);
  });

  test(
      'uses every desktop UA before repeating, including across cycle boundaries',
      () async {
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
  });

  test(
      'direct User-Agent reuses the last known identity instead of selecting a new one',
      () async {
    SharedPreferences.setMockInitialValues({
      'desktop_user_agents_used': [desktopUserAgents[7]]
    });
    expect(await loadDirectDesktopUserAgent(), desktopUserAgents[7]);
    expect(await loadDirectDesktopUserAgent(), desktopUserAgents[7]);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('desktop_user_agents_used'),
        [desktopUserAgents[7]]);
  });

  test('clears all Apple website data and cache without changing User-Agent',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await clearAppSession();
    expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('desktop_user_agents_used'),
        isNull);
  });

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

  testWidgets('startup and opening TikTok preserve cookies, storage and cache',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
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
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    final selected = <String>[];
    for (var launch = 0; launch < 2; launch++) {
      await tester.pumpWidget(MyApp(proxyStore: MemoryProxyStore()));
      await tester.pumpAndSettle();
      final userAgent =
          tester.widget<HomePage>(find.byType(HomePage)).userAgent;
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
        (await SharedPreferences.getInstance())
            .getStringList('desktop_user_agents_used'),
        hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'configuration loading failure retries without clearing the browser session',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    final store = MemoryProxyStore()..failReads = true;
    await tester.pumpWidget(MyApp(proxyStore: store));
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải cấu hình ứng dụng. Hãy thử lại.'),
        findsOneWidget);
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
  });

  testWidgets(
      'proxy User-Agent and session survive app restarts and WebView loads',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
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
          tester.widget<HomePage>(find.byType(HomePage)).userAgent, boundAgent);
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
        (await SharedPreferences.getInstance())
            .getStringList('desktop_user_agents_used'),
        isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'only applying a new proxy clears the session and its User-Agent survives restart',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    final store = MemoryProxyStore();
    final boundAgent = desktopUserAgents[11];
    final id = await store.save(
        name: 'New proxy',
        proxy: WebViewProxy.parse('proxy.example.com:8080')!,
        userAgent: boundAgent);
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
  });
}
