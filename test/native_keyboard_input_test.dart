import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';

void main() {
  testWidgets('Android enters Unicode comments without touching the clipboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    final clipboardWrites = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      TikTokController.commentInputChannel,
      (call) async {
        calls.add(call);
        return true;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TikTokController.commentInputChannel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const text = 'Video hay quá 👋';
    final view = _InputView();
    final logic = TikTokController(
      configuration: AppConfiguration(
        userAgent: 'test-agent',
        comments: [text],
        signupEmail: '',
        signupPassword: '',
        loginUsername: '',
        loginPassword: '',
      ),
    )..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: view,
    );
    logic.autoWatchEnabled = true;
    addTearDown(logic.onClose);

    expect(await logic.inputCommentText([text]), isTrue);
    expect(clipboardWrites, isEmpty);
    expect(calls.single.method, 'typeText');
    expect(calls.single.arguments, {'context': 'comment', 'text': text});

    // A different comment, lost focus, or stopped task must not type anything.
    expect(await logic.inputCommentText(['unconfigured comment']), isFalse);
    view.allowInput = false;
    expect(await logic.inputCommentText([text]), isFalse);
    view.allowInput = true;
    logic.autoWatchEnabled = false;
    expect(await logic.inputCommentText([text]), isFalse);
    expect(calls, hasLength(1));
    expect(clipboardWrites, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _InputView extends PlatformInAppWebViewController {
  _InputView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  bool allowInput = true;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => allowInput;
}
