import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/controller/home_controller.dart';
import 'package:test_tiktok/core/desktop_user_agents.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/otp_settings_page.dart';
import 'package:test_tiktok/screen/settings_page.dart';
import 'package:test_tiktok/screen/usage_guide_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('settings opens OTP configuration and usage guide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const settingsStore = OtpSettingsStore();
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        userAgent: desktopUserAgents.first,
        proxyStore: MemoryProxyStore(),
        otpSettingsStore: settingsStore,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byKey(const Key('openOtpSettings')));
    await tester.pumpAndSettle();
    expect(find.byType(OtpSettingsPage), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.descendant(
            of: find.byKey(const Key('otpApiToken')),
            matching: find.byType(EditableText),
          ))
          .obscureText,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('otpApiUrl')),
      'https://otp.example.com/api/code',
    );
    await tester.enterText(
      find.byKey(const Key('otpApiToken')),
      'saved-reader-token',
    );
    await tester.tap(find.byKey(const Key('saveOtpSettings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    final saved = await settingsStore.load();
    expect(saved.url, 'https://otp.example.com/api/code');
    expect(saved.token, 'saved-reader-token');

    await tester.tap(find.byKey(const Key('openUsageGuide')));
    await tester.pumpAndSettle();
    expect(find.byType(UsageGuidePage), findsOneWidget);
    expect(find.text('Bắt đầu nhanh'), findsOneWidget);
    expect(find.text('Cấu hình OTP Email API'), findsOneWidget);

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
    expect(homeController.otpSettings.token, saved.token);
    expect(tester.takeException(), isNull);
  });
}
