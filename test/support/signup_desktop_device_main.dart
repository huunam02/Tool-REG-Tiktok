// Device preflight: uses the production GeckoView, frame and signup runner.
// ./tool/flutterw build apk --debug --target-platform=android-arm64 \
//   -t test/support/signup_desktop_device_main.dart
// Stops before Send code. No OTP API or account creation is performed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/firefox_user_agent.dart';
import 'package:test_tiktok/core/gecko_browser.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/signup_birthday_menu.dart';
import 'package:test_tiktok/core/signup_coordinate_runner.dart';
import 'package:test_tiktok/screen/widgets/signup_viewport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
  ]);
  runApp(const MaterialApp(home: _DevicePreflight()));
}

@pragma('vm:entry-point')
void accessibilityOverlay() => runApp(const SizedBox.shrink());

class _DevicePreflight extends StatefulWidget {
  const _DevicePreflight();
  @override
  State<_DevicePreflight> createState() => _DevicePreflightState();
}

class _DevicePreflightState extends State<_DevicePreflight> {
  String status = 'Đang kiểm tra đăng ký desktop…';
  bool loaded = false;
  final report = <String, dynamic>{'ok': false, 'stoppedBeforeSendCode': true};
  final steps = <String>[];
  late final accessibility = _DeviceAccessibility(report, save);
  SignupCoordinateRunner? runner;

  Future<void> save() => File(
    '${Directory.systemTemp.path}/signup-desktop-device-result.json',
  ).writeAsString(jsonEncode({...report, 'steps': steps}));

  Future<void> verify(GeckoController browser) async {
    try {
      var running =
          await FlutterAccessibilityService.isAccessibilityServiceRunning();
      for (var i = 0; !running && i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        running =
            await FlutterAccessibilityService.isAccessibilityServiceRunning();
      }
      if (!running) {
        throw StateError('Bật Trợ năng của ứng dụng rồi mở lại bài kiểm tra.');
      }
      // onCreated runs before GeckoController.start loads the first URL.
      for (var i = 0; i < 60; i++) {
        final url = await browser.getUrl();
        if (url?.scheme == 'https' && url?.host == 'www.tiktok.com') break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      runner = SignupCoordinateRunner(
        profile: await SignupCoordinateProfile.load(),
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: firefoxDesktopUserAgent,
          signupEmail: 'desktop-preflight@example.org',
          signupPassword: 'DesktopPreflight12!',
          loginUsername: '',
          loginPassword: '',
          comments: const [],
          birthday: DateTime(2000, 2, 29),
        ),
        isActive: () => mounted,
        isPageReady: () => loaded,
        isTikTok: () async {
          final url = await browser.getUrl();
          return url?.scheme == 'https' && url?.host == 'www.tiktok.com';
        },
        getOtp: () async => throw StateError('Preflight must not request OTP'),
        readBirthdayMenu: (field) async => SignupBirthdayMenu.fromResult(
          await browser.evaluateJavascript(
            source: buildReadSignupBirthdayMenuScript(field),
          ),
        ),
        onStatus: (value) {
          steps.add(value);
          if (mounted) setState(() => status = value);
          unawaited(save());
        },
      );
      await runner!.run(stopBeforeSendCode: true);
      report['identity'] = await browser.evaluateJavascript(
        source: '''JSON.stringify({width:innerWidth,height:innerHeight,
          screen:[screen.width,screen.height],dpr:devicePixelRatio,
          outer:[outerWidth,outerHeight],touch:navigator.maxTouchPoints,
          touchApi:'ontouchstart' in window || typeof TouchEvent != 'undefined',
          orientation:'orientation' in window,
          pointer:['(pointer: fine)','(hover: hover)','(any-pointer: coarse)',
            '(any-hover: none)','(any-pointer: fine)','(any-hover: hover)'].filter(q=>matchMedia(q).matches),
          ua:navigator.userAgent})''',
        // The page realm, as TikTok sees it (the sandbox reads native values).
        pageWorld: true,
      );
      report['ok'] = true;
      if (mounted) setState(() => status = 'PASS — dừng trước Send code');
    } catch (error) {
      report['error'] = '$error';
      if (mounted) setState(() => status = 'FAIL — $error');
    } finally {
      await save();
    }
  }

  @override
  void dispose() {
    runner?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(title: Text(status, style: const TextStyle(fontSize: 14))),
    body: SafeArea(
      child: StandardSignupViewport(
        landscape: true,
        child: GeckoBrowserView(
          initialUrl: 'https://www.tiktok.com/',
          contextId: 'signup-desktop-device-preflight',
          userAgent: firefoxDesktopUserAgent,
          onCreated: (browser) => unawaited(verify(browser)),
          onLoadStart: (_, _) => loaded = false,
          onProgressChanged: (_, _) {},
          onLoadStop: (_, _) => loaded = true,
          onReceivedError: (_, _, error) {
            report['loadError'] = error.description;
          },
        ),
      ),
    ),
  );
}

class _DeviceAccessibility extends SignupAccessibility {
  _DeviceAccessibility(this.report, this.save);
  final Map<String, dynamic> report;
  final Future<void> Function() save;
  final actions = <Map<String, dynamic>>[];

  @override
  Future<SignupSnapshot> snapshot() async {
    final data = await FlutterAccessibilityService.signupSnapshot();
    report['snapshot'] = data;
    await save();
    return SignupSnapshot(data);
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    final screen = viewport.toScreen(point);
    actions.add({
      'tap': [screen.dx, screen.dy],
      'design': [point.dx, point.dy],
    });
    report['actions'] = actions;
    await save();
    await super.tap(viewport, point);
  }

  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    actions.add({
      'swipe': [from.dx, from.dy, to.dx, to.dy],
    });
    report['actions'] = actions;
    await save();
    await super.swipe(viewport, from, to);
  }
}
