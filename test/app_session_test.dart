import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/app_session.dart';
import 'package:test_tiktok/desktop_user_agents.dart';
import 'package:test_tiktok/main.dart';

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

  test('clears all Apple website data and cache before selecting a UA',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final userAgent = await prepareAppSession();
    expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
    expect(desktopUserAgents, contains(userAgent));
  });

  testWidgets('waits for session reset then opens WebView only from Home',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    _platform.cookieGate = Completer<bool>();
    await tester.pumpWidget(const MyApp());
    expect(_platform.calls, ['cookies']);
    expect(_platform.webViewsCreated, 0);

    // false means there were no cookies, not that deletion failed.
    _platform.cookieGate!.complete(false);
    await tester.pumpAndSettle();
    expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
    expect(_platform.webViewsCreated, 0);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(_platform.webViewsCreated, 1);
    expect(desktopUserAgents, contains(_platform.webViewUserAgent));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('restarting the app changes the displayed and WebView User-Agent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    final selected = <String>[];
    for (var launch = 0; launch < 2; launch++) {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      final userAgent = tester
          .widget<SelectableText>(find.byKey(const Key('userAgent')))
          .data!;
      selected.add(userAgent);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(_platform.webViewUserAgent, userAgent);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await (await SharedPreferences.getInstance()).reload();
    }
    expect(selected.last, isNot(selected.first));
    expect(_platform.calls, [
      'cookies',
      'apple-storage',
      'cache',
      'cookies',
      'apple-storage',
      'cache'
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Home resets session, retries failures and uses the new User-Agent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('comments')), 'Keep this comment');
    final original =
        tester.widget<SelectableText>(find.byKey(const Key('userAgent'))).data!;
    _platform.calls.clear();
    _platform.cookieGate = Completer<bool>();
    await tester.ensureVisible(find.byKey(const Key('resetSession')));
    await tester.tap(find.byKey(const Key('resetSession')));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('resetSession')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('openTikTok')))
            .onPressed,
        isNull);
    _platform.cookieGate!.completeError(StateError('Cannot reset cookies'));
    await tester.pumpAndSettle();
    expect(find.text('Không thể xóa phiên. Hãy thử lại.'), findsOneWidget);
    expect(
        tester.widget<SelectableText>(find.byKey(const Key('userAgent'))).data,
        original);
    expect(_platform.calls, ['cookies']);
    _platform.calls.clear();
    _platform.cookieGate = null;
    await tester.tap(find.byKey(const Key('resetSession')));
    await tester.pumpAndSettle();
    final updated =
        tester.widget<SelectableText>(find.byKey(const Key('userAgent'))).data!;
    expect(updated, isNot(original));
    expect(_platform.calls, ['cookies', 'apple-storage', 'cache']);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('comments')))
            .controller!
            .text,
        'Keep this comment');
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(_platform.webViewUserAgent, updated);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('blocks TikTok if reset fails and allows a clean retry',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    _platform.cookieGate = Completer<bool>();
    await tester.pumpWidget(const MyApp());
    _platform.cookieGate!.completeError(StateError('Cookie deletion failed'));
    await tester.pumpAndSettle();
    expect(_platform.webViewsCreated, 0);
    expect(find.text('Không thể tạo phiên mới. Hãy thử lại.'), findsOneWidget);

    _platform.cookieGate = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(_platform.webViewsCreated, 0);
    expect(_platform.calls, ['cookies', 'cookies', 'apple-storage', 'cache']);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(_platform.webViewsCreated, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}
