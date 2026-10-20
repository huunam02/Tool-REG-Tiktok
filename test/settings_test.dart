import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/accessibility_permission.dart';
import 'package:test_tiktok/core/desktop_user_agents.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/settings_page.dart';
import 'package:test_tiktok/screen/usage_guide_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfig.configs = {
      ...RemoteConfig.defaults,
      'otp_api_url': 'https://remote.example.com/api/code',
    };
  });
  tearDown(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });

  testWidgets('accessibility switch follows system permission on resume', (
    tester,
  ) async {
    var enabled = true;
    var requests = 0;
    await _pumpAccessibilitySettings(
      tester,
      AccessibilityPermissionService(
        supported: true,
        isEnabled: () async => enabled,
        openSettings: () async {
          requests++;
          enabled = false;
          return false;
        },
      ),
    );
    final toggle = find.byKey(const Key('accessibilitySettings'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'accessibility switch waits for a verified grant and remains off when cancelled',
    (tester) async {
      var enabled = false;
      var requests = 0;
      final settingsReturned = Completer<bool>();
      await _pumpAccessibilitySettings(
        tester,
        AccessibilityPermissionService(
          supported: true,
          isEnabled: () async => enabled,
          openSettings: () async {
            requests++;
            if (requests == 1) return settingsReturned.future;
            return true;
          },
        ),
      );
      final toggle = find.byKey(const Key('accessibilitySettings'));
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      enabled = true;
      settingsReturned.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);

      enabled = false;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission check failure still allows opening Android settings',
    (tester) async {
      var checkFailed = true;
      await _pumpAccessibilitySettings(
        tester,
        AccessibilityPermissionService(
          supported: true,
          isEnabled: () async {
            if (checkFailed) throw StateError('Permission unavailable');
            return true;
          },
          openSettings: () async {
            checkFailed = false;
            return true;
          },
        ),
      );
      expect(find.textContaining('Không thể kiểm tra quyền'), findsOneWidget);
      final toggle = find.byKey(const Key('accessibilitySettings'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(find.textContaining('Không thể kiểm tra quyền'), findsNothing);
    },
  );

  testWidgets('unsupported platforms hide accessibility without native calls', (
    tester,
  ) async {
    await _pumpAccessibilitySettings(
      tester,
      AccessibilityPermissionService(
        supported: false,
        isEnabled: () async => throw StateError('Should not check'),
        openSettings: () async => throw StateError('Should not open'),
      ),
    );
    expect(find.byKey(const Key('accessibilitySettings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'accessibility switch fits enlarged text and closes a pending check',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final check = Completer<bool>();
      await _pumpAccessibilitySettings(
        tester,
        AccessibilityPermissionService(
          supported: true,
          isEnabled: () => check.future,
        ),
        enlargedText: true,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('accessibilitySettings')),
        150,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('accessibilitySettings')),
            )
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      check.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings hides API configuration and opens usage guide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const settingsStore = OtpSettingsStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          userAgent: desktopUserAgents.first,
          proxyStore: MemoryProxyStore(),
          otpSettingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    expect(find.byKey(const Key('openOtpSettings')), findsNothing);
    expect(find.byKey(const Key('openCaptchaSettings')), findsNothing);
    expect(find.text('Cấu hình OTP Email API'), findsNothing);
    expect(find.text('Cấu hình CAPTCHA API'), findsNothing);
    final saved = await settingsStore.load();
    expect(saved.url, 'https://remote.example.com/api/code');

    await tester.scrollUntilVisible(
      find.byKey(const Key('openUsageGuide')),
      150,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openUsageGuide')));
    await tester.pumpAndSettle();
    expect(find.byType(UsageGuidePage), findsOneWidget);
    expect(find.text('Bắt đầu nhanh'), findsOneWidget);
    expect(find.text('Bật quyền Trợ năng'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final homeController = tester
        .state<GetBuilderState<HomeController>>(
          find.byType(GetBuilder<HomeController>),
        )
        .controller!;
    expect(homeController.otpSettings.url, saved.url);
    for (final action in [
      TikTokLaunchAction.signup,
      TikTokLaunchAction.login,
    ]) {
      expect(homeController.otpApiFor(action)!.url.toString(), saved.url);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAccessibilitySettings(
  WidgetTester tester,
  AccessibilityPermissionService service, {
  bool enlargedText = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: enlargedText
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            )
          : null,
      home: SettingsPage(accessibilityPermission: service),
    ),
  );
  await tester.pumpAndSettle();
}
