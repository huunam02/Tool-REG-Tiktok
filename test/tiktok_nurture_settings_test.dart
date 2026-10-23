import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

void main() {
  AppConfiguration configuration(NurtureSettings settings) => AppConfiguration(
    userAgent: 'test',
    comments: const [],
    signupEmail: '',
    signupPassword: '',
    loginUsername: 'person@example.com',
    loginPassword: '',
    nurtureSettings: settings,
  );

  test('the TikTok screen nurtures for the configuration\'s minutes', () {
    final logic = TikTokController(
      configuration: configuration(
        const NurtureSettings(minMinutes: 10, maxMinutes: 20),
      ),
      launchAction: TikTokLaunchAction.login,
    );
    expect(logic.minNurtureDuration, const Duration(minutes: 10));
    expect(logic.maxNurtureDuration, const Duration(minutes: 20));
  });

  testWidgets('a long configured session is not cut by the 15-minute limit', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final results = <TikTokFlowResult>[];
    final notices = <String>[];
    final logic = TikTokController(
      configuration: configuration(
        const NurtureSettings(minMinutes: 20, maxMinutes: 30),
      ),
      launchAction: TikTokLaunchAction.login,
      useAccessibility: true,
      autoAdvance: true,
      onFlowFinished: results.add,
      now: tester.binding.clock.now,
    )..onInit();
    logic.onNotice = (notice) => notices.add(notice.message);
    await tester.pump(const Duration(minutes: 41));
    expect(results, isEmpty);
    // 30 minutes of nurture plus 12 for login and page loading.
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(notices, contains('Quá 42 phút chưa xong cấu hình này.'));
    logic.onDelete();
    await tester.pump(const Duration(minutes: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
