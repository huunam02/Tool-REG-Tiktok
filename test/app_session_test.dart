import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/app_session.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/desktop_user_agents.dart';
import 'package:test_tiktok/core/chrome_user_agent.dart';
import 'package:test_tiktok/core/webview_user_agent.dart';
import 'package:test_tiktok/main.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';
import 'package:test_tiktok/screen/splash_page.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';

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

  test('iOS User-Agent list contains only macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(desktopUserAgents, hasLength(5));
    expect(
      desktopUserAgents.every(
        (ua) => RegExp(r'Chrome/15[1-5]\.0\.0\.0').hasMatch(ua),
      ),
      isTrue,
    );
    expect(desktopUserAgents.any((ua) => ua.contains('Edg/')), isFalse);
    expect(desktopUserAgents.every((ua) => !ua.contains('Linux')), isTrue);
    expect(desktopUserAgents.any((ua) => ua.contains('Windows NT')), isFalse);
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
    'Android upgrades a saved built-in Linux UA and keeps it across loads',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const agent =
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      SharedPreferences.setMockInitialValues({
        'desktop_user_agent_direct': agent,
        'desktop_user_agents_used': [agent],
      });
      expect(
        await loadDirectDesktopUserAgent(),
        upgradeLegacyDesktopUserAgent(agent),
      );
      await (await SharedPreferences.getInstance()).reload();
      expect(
        await loadDirectDesktopUserAgent(),
        upgradeLegacyDesktopUserAgent(agent),
      );
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        [agent],
      );
    },
  );

  test(
    'Android upgrades an old Windows direct UA while keeping Windows',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const windowsAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      SharedPreferences.setMockInitialValues({
        'desktop_user_agent_direct': windowsAgent,
        'desktop_user_agents_used': [windowsAgent],
      });
      final selected = await loadDirectDesktopUserAgent();
      expect(selected, windowsChromeUserAgent);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'desktop_user_agent_direct',
        ),
        selected,
      );
    },
  );

  test(
    'Android migrates duplicate Linux/Windows history without repeating the last Chrome version',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final linux = [
        for (final major in recentChromeFullVersions.keys)
          chromeDesktopUserAgent('X11; Linux x86_64', major: major),
      ];
      final windows = chromeDesktopUserAgent(
        'Windows NT 10.0; Win64; x64',
        major: 151,
      );
      SharedPreferences.setMockInitialValues({
        'desktop_user_agents_used': [...linux, windows],
      });
      final selected = await selectNextDesktopUserAgent();
      expect(selected, miuiBrowserUserAgent);
      expect(selected, isNot(contains('Chrome/151.')));
      final history = (await SharedPreferences.getInstance()).getStringList(
        'desktop_user_agents_used',
      )!;
      expect(history, [...linux, selected]);
    },
  );

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
    'Android randomizes recent Chrome versions across complete cycles',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _platform.nativeUserAgent =
          'Mozilla/5.0 (Linux; Android 16; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/154.0.8037.107 Mobile Safari/537.36';
      final agents = <String>[];
      final count = androidDesktopUserAgents.length;
      expect(count, 6);
      for (var i = 0; i < count * 2; i++) {
        final agent = await selectNextDesktopUserAgent();
        if (agent == miuiBrowserUserAgent) {
          expect(agent, contains('X11; Linux x86_64'));
          expect(agent, isNot(contains('Mobile')));
        } else {
          expect(agent, matches(r'Chrome/15[1-5]\.0\.0\.0'));
          expect(agent, contains('X11; Linux x86_64'));
          expect(
            agent,
            isNot(matches(r'Android|Mobile| wv|Macintosh|Windows')),
          );
        }
        if (agents.isNotEmpty) expect(agent, isNot(agents.last));
        agents.add(agent);
        await (await SharedPreferences.getInstance()).reload();
      }
      expect(agents.take(count).toSet(), androidDesktopUserAgents.toSet());
      expect(agents.skip(count).toSet(), androidDesktopUserAgents.toSet());
      expect(
        agents
            .take(count)
            .map((agent) => RegExp(r'Chrome/(\d+)').firstMatch(agent)!.group(1))
            .toSet(),
        {'135', '151', '152', '153', '154', '155'},
      );
      expect(await loadDirectDesktopUserAgent(), agents.last);
      expect(await loadDirectDesktopUserAgent(), agents.last);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        agents.skip(count).toList(),
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
      expect(androidDesktopUserAgents, contains(previous));
      for (var i = 0; i < 4; i++) {
        final button = find.byKey(const Key('generateProxyUserAgent'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(displayedAgent(), isNot(previous));
        expect(androidDesktopUserAgents, contains(displayedAgent()));
        previous = displayedAgent();
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android can choose Miui directly without random retries', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateProxyPage(
          generateUserAgent: () async => androidDesktopUserAgents.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('useMiuiUserAgent'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('savedProxyUserAgent')),
    );
    expect(field.controller!.text, miuiBrowserUserAgent);
    expect(field.controller!.text, contains('X11; Linux x86_64'));
    expect(field.controller!.text, isNot(contains('Mobile')));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android can select Windows and retain it when normalizing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      MaterialApp(
        home: CreateProxyPage(
          generateUserAgent: () async => androidDesktopUserAgents.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('useWindowsUserAgent'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('savedProxyUserAgent')),
    );
    expect(field.controller!.text, windowsChromeUserAgent);
    expect(
      normalizeDesktopUserAgentForPlatform(field.controller!.text),
      windowsChromeUserAgent,
    );
    expect(
      await resolveWebViewUserAgent(field.controller!.text),
      windowsChromeUserAgent,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'direct User-Agent reuses the last known identity instead of selecting a new one',
    () async {
      SharedPreferences.setMockInitialValues({
        'desktop_user_agents_used': [desktopUserAgents[1]],
      });
      expect(await loadDirectDesktopUserAgent(), desktopUserAgents[1]);
      expect(await loadDirectDesktopUserAgent(), desktopUserAgents[1]);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'desktop_user_agents_used',
        ),
        [desktopUserAgents[1]],
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
        ..currentUserAgent = desktopUserAgents[1];
      final savedAgent = store.currentUserAgent;
      await tester.pumpWidget(MyApp(proxyStore: store));
      await tester.pumpAndSettle();
      await _openTikTok(tester);
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
    await _openTikTok(tester);
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
        await _openTikTok(tester);
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
      await _openTikTok(tester);
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
        ..currentUserAgent = desktopUserAgents[1];
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
        await _openTikTok(tester);
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
}

/// Opens TikTok for the configuration in use, as runs and the Settings
/// checks do (Home no longer has its own Mở TikTok button).
Future<void> _openTikTok(WidgetTester tester) async {
  final home = tester
      .state<GetBuilderState<HomeController>>(
        find.byType(GetBuilder<HomeController>),
      )
      .controller!;
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    home.openTikTok(
      TikTokLaunchAction.browse,
      (configuration, _) => navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TikTokPage(configuration: configuration),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
