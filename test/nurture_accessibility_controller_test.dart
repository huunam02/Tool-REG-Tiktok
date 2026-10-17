import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_nurture_store.dart';

class _View extends PlatformInAppWebViewController {
  _View()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  final sources = <String>[];
  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    return true;
  }
}

void main() {
  testWidgets(
    'Android nurture finishes at ten minutes without injecting any JS',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('x-slayer/accessibility_channel');
      final calls = <String>[];
      final recording =
          jsonDecode(
                File(
                  'test/fixtures/nurture_accessibility_recording.json',
                ).readAsStringSync(),
              )
              as Map;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'signupSnapshot') {
          return recording['feed'];
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final repository = MemoryNurtureRepository(() async => []);
      final results = <TikTokFlowResult>[];
      final notices = <String>[];
      final view = _View();
      final logic = TikTokController(
        configuration: AppConfiguration(
          userAgent: 'test',
          comments: ['Configured comment'],
          signupEmail: '',
          signupPassword: '',
          loginUsername: 'fixture@example.com',
          loginPassword: '',
        ),
        launchAction: TikTokLaunchAction.login,
        useAccessibility: true,
        now: tester.binding.clock.now,
        nurtureRepository: repository,
        nurtureProfileLoader: () async => NurtureCoordinateProfile({}),
        onFlowFinished: results.add,
      )..onInit();
      addTearDown(() => logic.onDelete());
      logic.webViewController = InAppWebViewController.fromPlatform(
        platform: view,
      );
      logic.loginConfirmed = true;
      logic.onNotice = (notice) => notices.add(notice.message);
      await logic.toggleAutoWatch();
      await tester.pump();
      expect(logic.autoWatchEnabled, isTrue);
      expect(calls, contains('signupSnapshot'));
      expect(view.sources, isEmpty);
      await tester.pump(const Duration(minutes: 10));
      for (var i = 0; i < 25 && results.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(logic.autoWatchEnabled, isFalse);
      expect(
        results,
        [TikTokFlowResult.nurtureCompleted],
        reason:
            'notices=$notices phases=${repository.phases} calls=$calls active=${logic.appActive}',
      );
      expect(repository.phases.values, everyElement('completed'));
      expect(calls, contains('signupCancelPaste'));
      expect(view.sources, isEmpty);
      logic.onDelete();
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
