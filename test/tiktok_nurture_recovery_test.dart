import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/browser_view.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/webview_failure.dart';

class _Accessibility extends SignupAccessibility {
  bool recovered = false, draft = false, failReads = false, dialog = false;
  int reads = 0;
  final Map<String, dynamic> feed = Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/nurture_accessibility_recording.json',
          ).readAsStringSync(),
        )['feed']
        as Map,
  );

  @override
  Future<SignupSnapshot> snapshot() async {
    reads++;
    if (failReads) throw StateError('Transient snapshot failure');
    if (dialog) {
      // TikTok keeps "Verifying..." open for a while after a solved CAPTCHA.
      return SignupSnapshot({
        ...feed,
        'nodes': [
          ...feed['nodes'] as List,
          {
            'id': '9',
            'className': 'android.app.Dialog',
            'bounds': [200, 900, 880, 1500],
            'text': '',
          },
          {
            'id': '9.0',
            'className': 'android.view.View',
            'bounds': [220, 1000, 860, 1100],
            'text': 'Verifying...',
          },
        ],
      });
    }
    return SignupSnapshot(
      recovered
          ? feed
          : {
              'ready': true,
              'webBounds': [0, 0, 400, 800],
              'nodes': [],
              'hidden': [
                if (draft)
                  {
                    'id': 'unknown.editor',
                    'bounds': [290, 750, 370, 780],
                    'editable': true,
                    'length': 5,
                  },
              ],
            },
    );
  }

  @override
  Future<void> cancelPaste() async {}

  // The recorded feed never moves; gestures complete without effect.
  int gestures = 0;
  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async =>
      gestures++;
  @override
  Future<void> tap(SignupViewport viewport, Offset point) async => gestures++;
}

class _Controller extends TikTokController {
  _Controller(
    this.accessibility,
    CaptchaSettingsStore settings,
    DateTime Function() now, {
    bool automatic = false,
    List<TikTokFlowResult>? results,
    WebViewProxy? proxy,
  }) : super(
         configuration: AppConfiguration(
           proxy: proxy,
           userAgent: 'fixture',
           signupEmail: '',
           signupPassword: '',
           loginUsername: '',
           loginPassword: '',
           comments: [],
           nurtureSettings: const NurtureSettings(
             likePercent: 0,
             commentPercent: 0,
             longWatchPercent: 0,
             minMinutes: 10,
             maxMinutes: 10,
           ),
         ),
         launchAction: TikTokLaunchAction.login,
         useAccessibility: true,
         autoAdvance: automatic,
         onFlowFinished: results?.add,
         captchaSettingsStore: settings,
         nurtureProfileLoader: () async => NurtureCoordinateProfile({}),
         now: now,
       );
  final _Accessibility accessibility;
  @override
  SignupAccessibility get signupAccessibility => accessibility;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_tiktok/browser_view_87');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final automatic in [false, true]) {
    testWidgets(
      'lost playback retries in place and retains the original deadline (automatic=$automatic)',
      (tester) async {
        final settings = CaptchaSettingsStore();
        await settings.load();
        final accessibility = _Accessibility();
        final logic = _Controller(
          accessibility,
          settings,
          tester.binding.clock.now,
          automatic: automatic,
        )..onInit();
        final browser = BrowserController.test(87);
        var reloads = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getUrl') return 'https://www.tiktok.com/';
          if (call.method == 'loadUrl' || call.method == 'reload') {
            reloads++;
            accessibility.recovered = true;
            logic.onLoadStart(browser, Uri.parse('https://www.tiktok.com/'));
            unawaited(logic.startAutoWatch());
          }
          return null;
        });
        await logic.onWebViewCreated(browser);
        logic.loginConfirmed = true;
        await logic.toggleAutoWatch();
        final notices = <String>[];
        logic.onNotice = (notice) => notices.add(notice.message);
        for (var second = 0; second < 30; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(reloads, 0);
        expect(logic.navigationId, 0);
        expect(logic.autoWatchEnabled, isTrue);
        expect(logic.loginConfirmed, isTrue);
        expect(
          notices,
          contains(
            'Không đọc được tiến độ video qua Accessibility; đã dừng nuôi. '
            'Đang chờ đọc lại trạng thái trên trang hiện tại; giữ nguyên thời hạn nuôi.',
          ),
        );
        final readsBeforeRecovery = accessibility.reads;
        accessibility.recovered = true; // Metadata returns without navigation.
        await tester.pump(const Duration(seconds: 3));
        expect(accessibility.reads, greaterThan(readsBeforeRecovery));
        expect(reloads, 0);
        await tester.pump(const Duration(minutes: 9, seconds: 26));
        expect(logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(seconds: 1));
        expect(logic.autoWatchEnabled, isFalse);
        logic.onDelete();
        await tester.pump();
        browser.dispose();
        settings.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final scenario in ['playback', 'snapshot', 'draft', 'http']) {
    testWidgets('queued $scenario errors retain the deadline and finish once', (
      tester,
    ) async {
      final settings = CaptchaSettingsStore();
      await settings.load();
      final accessibility = _Accessibility()
        ..draft = scenario == 'draft'
        ..failReads = scenario == 'snapshot'
        ..recovered = scenario == 'http';
      final results = <TikTokFlowResult>[];
      final logic = _Controller(
        accessibility,
        settings,
        tester.binding.clock.now,
        automatic: true,
        results: results,
      )..onInit();
      final browser = BrowserController.test(87);
      var reloads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUrl') return 'https://www.tiktok.com/';
        if (call.method == 'loadUrl' || call.method == 'reload') {
          reloads++;
          logic.onLoadStart(browser, Uri.parse('https://www.tiktok.com/'));
          unawaited(logic.startAutoWatch());
        }
        return null;
      });
      await logic.onWebViewCreated(browser);
      logic.loginConfirmed = true;
      await logic.toggleAutoWatch();
      // Duplicate page/lifecycle callbacks must observe one failure only.
      await logic.startAutoWatch();
      await logic.startAutoWatch();
      if (scenario == 'http') logic.showPageFailure(WebViewFailure.http(503));
      for (var second = 0; second < 100; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(logic.autoWatchEnabled, isTrue);
      expect(results, isEmpty);
      expect(reloads, 0);
      expect(logic.navigationId, 0);
      await tester.pump(const Duration(minutes: 8, seconds: 19));
      expect(results, isEmpty);
      expect(logic.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(results, [TikTokFlowResult.nurtureCompleted]);
      expect(logic.autoWatchEnabled, isFalse);
      final finishedReloads = reloads;
      await tester.pump(const Duration(minutes: 1));
      expect(reloads, finishedReloads);
      expect(results, hasLength(1));
      logic.onDelete();
      await tester.pump();
      browser.dispose();
      settings.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('a manual run resumes after a lingering verification dialog', (
    tester,
  ) async {
    final settings = CaptchaSettingsStore();
    await settings.load();
    final accessibility = _Accessibility()
      ..recovered = true
      ..dialog = true;
    final logic = _Controller(accessibility, settings, tester.binding.clock.now)
      ..onInit();
    final browser = BrowserController.test(87);
    var reloads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUrl') return 'https://www.tiktok.com/';
      if (call.method == 'loadUrl' || call.method == 'reload') reloads++;
      return null;
    });
    await logic.onWebViewCreated(browser);
    logic.loginConfirmed = true;
    await logic.toggleAutoWatch();
    final notices = <String>[];
    logic.onNotice = (notice) => notices.add(notice.message);
    for (var second = 0; second < 30; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(logic.autoWatchEnabled, isTrue);
    expect(
      notices,
      contains(
        'TikTok đang mở hộp thoại (Verifying...); tạm dừng nuôi. '
        'Đang chờ đọc lại trạng thái trên trang hiện tại; giữ nguyên thời hạn nuôi.',
      ),
    );
    accessibility.dialog = false;
    final readsAfterDialog = accessibility.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(accessibility.reads, greaterThan(readsAfterDialog));
    expect(logic.autoWatchEnabled, isTrue);
    expect(reloads, 0);
    expect(logic.navigationId, 0);
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('repeated start callbacks schedule one in-place recovery', (
    tester,
  ) async {
    final settings = CaptchaSettingsStore();
    await settings.load();
    final accessibility = _Accessibility();
    final logic = _Controller(
      accessibility,
      settings,
      tester.binding.clock.now,
      automatic: true,
    )..onInit();
    final browser = BrowserController.test(87);
    var reloads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUrl') return 'https://www.tiktok.com/';
      if (call.method == 'loadUrl' || call.method == 'reload') {
        reloads++;
        accessibility.recovered = true;
        logic.onLoadStart(browser, Uri.parse('https://www.tiktok.com/'));
        unawaited(logic.startAutoWatch());
      }
      return null;
    });
    await logic.onWebViewCreated(browser);
    logic.loginConfirmed = true;
    await logic.toggleAutoWatch();
    final notices = <String>[];
    logic.onNotice = (notice) => notices.add(notice.message);
    await Future.wait([logic.startAutoWatch(), logic.startAutoWatch()]);
    for (var second = 0; second < 30; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(reloads, 0);
    expect(
      notices.where((message) => message.contains('Đang chờ đọc lại')),
      hasLength(1),
    );
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final failure in ['mainframe', 'proxy-warning', 'ip-lookup']) {
    testWidgets('queued proxy policy handles $failure', (tester) async {
      final settings = CaptchaSettingsStore();
      await settings.load();
      final results = <TikTokFlowResult>[];
      final logic = _Controller(
        _Accessibility()..recovered = true,
        settings,
        tester.binding.clock.now,
        automatic: true,
        results: results,
        proxy: WebViewProxy(uri: Uri.parse('http://127.0.0.1:8080')),
      )..onInit();
      final browser = BrowserController.test(87);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUrl') return 'https://www.tiktok.com/';
        return null;
      });
      await logic.onWebViewCreated(browser);
      logic.loginConfirmed = true;
      await logic.toggleAutoWatch();
      for (var i = 0; i < 2; i++) {
        if (failure == 'mainframe') {
          logic.showPageFailure(WebViewFailure.proxyAuth);
        } else if (failure == 'proxy-warning') {
          logic.showProxyWarning(
            const WebViewFailure(
              'Proxy unavailable',
              'Cannot connect',
              code: 'ERR_PROXY_CONNECTION_FAILED',
              isConnectionFailure: true,
            ),
          );
        } else {
          logic.showProxyWarning(WebViewFailure.ipUnverified, ipCheck: true);
        }
      }
      expect(logic.autoWatchEnabled, failure == 'ip-lookup');
      expect(logic.autoRunFailing, failure != 'ip-lookup');
      await tester.pump(TikTokController.autoFailureDelay);
      expect(
        results,
        failure == 'ip-lookup' ? isEmpty : [TikTokFlowResult.failed],
      );
      await tester.pump(const Duration(minutes: 11));
      expect(results, hasLength(1));
      expect(
        results.single,
        failure == 'ip-lookup'
            ? TikTokFlowResult.nurtureCompleted
            : TikTokFlowResult.failed,
      );
      logic.onDelete();
      await tester.pump();
      browser.dispose();
      settings.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final draft in [false, true]) {
    testWidgets(
      'repeated recovery keeps the document and preserves drafts (draft=$draft)',
      (tester) async {
        final settings = CaptchaSettingsStore();
        await settings.load();
        final accessibility = _Accessibility()..draft = draft;
        final logic = _Controller(
          accessibility,
          settings,
          tester.binding.clock.now,
        )..onInit();
        final browser = BrowserController.test(87);
        var reloads = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getUrl') return 'https://www.tiktok.com/';
          if (call.method == 'loadUrl' || call.method == 'reload') {
            reloads++;
            logic.onLoadStart(browser, Uri.parse('https://www.tiktok.com/'));
            unawaited(logic.startAutoWatch());
          }
          return null;
        });
        await logic.onWebViewCreated(browser);
        logic.loginConfirmed = true;
        await logic.toggleAutoWatch();
        for (var second = 0; second < 75; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(reloads, 0);
        expect(logic.navigationId, 0);
        expect(logic.autoWatchEnabled, isTrue);
        expect(logic.loginConfirmed, isTrue);
        if (draft) {
          expect((await accessibility.snapshot()).hiddenNodes.single.length, 5);
        }
        logic.onDelete();
        await tester.pump();
        browser.dispose();
        settings.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
