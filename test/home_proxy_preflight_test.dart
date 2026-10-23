import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_proxy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vpn = MethodChannel('test_tiktok/profile_vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(vpn, null);
  });

  HomeController home() {
    const otp = OtpApiSettings(url: 'https://otp.example.test/');
    return HomeController(
        initialUserAgent: 'test agent',
        initialOtpSettings: otp,
        store: MemoryProxyStore(),
      )
      ..userAgent = 'test agent'
      ..otpSettings = otp
      ..loadingProxy = false
      ..currentProxy = ProxyProfile(
        proxy: WebViewProxy.parse('http://proxy.example.test:8080'),
        userAgent: 'test agent',
        timeZoneId: 'Asia/Ho_Chi_Minh',
        account: const AccountCredentials(
          email: 'test@example.test',
          password: 'test password',
          dataMail: 'test mailbox',
        ),
      );
  }

  // Nurture and signup enter the same preflight in openTikTok. Mock only
  // Android's VPN and the public-IP server; exercise the actual launch gate.
  for (final action in [
    TikTokLaunchAction.login,
    TikTokLaunchAction.signup,
    TikTokLaunchAction.browse,
  ]) {
    testWidgets('$action waits for VPN and IP before mounting WebView', (
      tester,
    ) async {
      final events = <String>[];
      final urls = <Uri>[];
      final applied = Completer<void>();
      final ipReply = Completer<http.Response>();
      final closeWebView = Completer<void>();
      AppConfiguration? openedConfiguration;
      TikTokLaunchAction? openedAction;
      messenger.setMockMethodCallHandler(vpn, (call) async {
        events.add('vpn:${call.method}');
        if (call.method == 'start') await applied.future;
        if (call.method == 'status') {
          return {'running': true, 'profileId': 'default'};
        }
        return null;
      });
      final client = MockClient((request) async {
        events.add('ip');
        urls.add(request.url);
        return await ipReply.future;
      });
      final logic = home();
      final opening = http.runWithClient(
        () => logic.openTikTok(action, (configuration, nextAction) async {
          events.add('webview');
          openedConfiguration = configuration;
          openedAction = nextAction;
          await closeWebView.future;
        }, automatic: true),
        () => client,
      );
      await tester.pump();
      expect(events, ['vpn:start']);
      applied.complete();
      await tester.pump();
      expect(events, ['vpn:start', 'ip']);
      expect(urls.single.scheme, 'https');
      expect(urls.single.host, 'api.ipify.org');
      ipReply.complete(http.Response('{"ip":"203.0.113.7"}', 200));
      await tester.pump();
      expect(events, ['vpn:start', 'ip', 'vpn:status', 'webview']);
      expect(openedAction, action);
      expect(openedConfiguration!.proxy!.uri.scheme, 'http');
      expect(logic.opening, isTrue);
      closeWebView.complete();
      await opening;
      expect(events, ['vpn:start', 'ip', 'vpn:status', 'webview', 'vpn:stop']);
      expect(logic.opening, isFalse);
    });

    for (final status in [
      null,
      {'running': false, 'profileId': 'default'},
      {'running': true, 'profileId': 'another-profile'},
    ]) {
      testWidgets(
        '$action rejects a missing, stopped or replaced tunnel: $status',
        (tester) async {
          var opened = false;
          final events = <String>[];
          messenger.setMockMethodCallHandler(vpn, (call) async {
            events.add(call.method);
            return call.method == 'status' ? status : null;
          });
          final logic = home();
          final notices = <String>[];
          logic.onNotice = (notice) => notices.add(notice.message);
          await http.runWithClient(
            () => logic.openTikTok(action, (_, _) async {
              opened = true;
            }, automatic: true),
            () => MockClient(
              (_) async => http.Response('{"ip":"203.0.113.7"}', 200),
            ),
          );
          expect(opened, isFalse);
          expect(events, ['start', 'status', 'stop']);
          expect(notices.single, contains('Đã chặn mở WebView'));
        },
      );
    }

    testWidgets('$action blocks WebView if the VPN fails to apply', (
      tester,
    ) async {
      var ipRequests = 0;
      var webViews = 0;
      final stops = <String>[];
      messenger.setMockMethodCallHandler(vpn, (call) async {
        if (call.method == 'start') {
          throw PlatformException(code: 'vpn_failed', message: 'Proxy failed');
        }
        stops.add(call.method);
        return null;
      });
      final logic = home();
      final notices = <String>[];
      logic.onNotice = (notice) => notices.add(notice.message);
      await http.runWithClient(
        () => logic.openTikTok(action, (_, _) async {
          webViews++;
        }, automatic: true),
        () => MockClient((_) async {
          ipRequests++;
          return http.Response('{"ip":"203.0.113.7"}', 200);
        }),
      );
      expect(ipRequests, 0);
      expect(webViews, 0);
      expect(notices, ['Proxy failed']);
      expect(stops, ['stop']);
      expect(logic.opening, isFalse);
    });

    testWidgets('$action blocks WebView when the IP probe fails', (
      tester,
    ) async {
      var webViews = 0;
      final events = <String>[];
      messenger.setMockMethodCallHandler(vpn, (call) async {
        events.add(call.method);
        return null;
      });
      final logic = home();
      final notices = <String>[];
      logic.onNotice = (notice) => notices.add(notice.message);
      await http.runWithClient(
        () => logic.openTikTok(action, (_, _) async {
          webViews++;
        }, automatic: true),
        () => MockClient((request) async {
          events.add(request.url.host);
          return http.Response('{"ip":"invalid address"}', 200);
        }),
      );
      expect(webViews, 0);
      expect(events, ['start', 'api.ipify.org', 'api64.ipify.org', 'stop']);
      expect(notices.single, contains('Proxy không kết nối được'));
      expect(logic.opening, isFalse);
    });
  }
}
