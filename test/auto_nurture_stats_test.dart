import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';

import 'support/memory_nurture_store.dart';
import 'support/memory_proxy_store.dart';

class _View extends PlatformInAppWebViewController {
  _View()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  final callbacks = <String, JavaScriptHandlerCallback>{};
  Map<String, dynamic>? config;
  Map<String, Object?>? finalSnapshot;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {}

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    callbacks[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoLoginStepScript)) return 'login-success';
    if (source.startsWith('window.__manualViewingConfig = ')) {
      config = jsonDecode(
        source
            .split('\n')
            .first
            .substring('window.__manualViewingConfig = '.length)
            .replaceFirst(RegExp(r';$'), ''),
      );
    }
    if (source == 'window.__manualViewing?.stop() ?? null' ||
        source == 'window.__manualViewing?.setActive(false) ?? null') {
      final result = finalSnapshot;
      finalSnapshot = null;
      return result;
    }
    return true;
  }

  Map<String, Object?> snapshot(
    int sequence, {
    int videos = 1,
    int comments = 0,
  }) => {
    'session': config!['session'],
    'segment': config!['segment'],
    'sequence': sequence,
    'watch_ms': videos * 2500,
    'videos': videos,
    'full_videos': 0,
    'skipped_videos': videos,
    'comments': comments,
  };

  Future<void> emit(Map<String, Object?> value) async =>
      callbacks['FlutterNurtureStats']!([value]);
}

void main() {
  late TikTokController logic;
  late _View view;
  late MemoryNurtureRepository repository;
  late InAppWebViewController controller;

  const identity = MethodChannel('test_tiktok/webview_identity');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(identity, (_) async => 'Chrome/134.0.0.0');
  });

  Future<void> initialize() async {
    repository = MemoryNurtureRepository(() async => []);
    view = _View();
    logic = TikTokController(
      configuration: AppConfiguration(
        configurationId: 42,
        userAgent: 'agent',
        comments: ['A comment'],
        signupEmail: 'signup@example.com',
        signupPassword: 'password',
        loginUsername: ' Account@example.com ',
        loginPassword: 'password',
      ),
      nurtureRepository: repository,
      proxyStore: MemoryProxyStore(),
      useAccessibility: false,
    )..onInit();
    controller = InAppWebViewController.fromPlatform(platform: view);
    await logic.onWebViewCreated(controller);
    logic.loginConfirmed = true;
    logic.autoWatchEnabled = true;
  }

  tearDown(() {
    logic.onDelete();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(identity, null);
  });

  testWidgets(
    'each view and confirmed comment updates the active account before exit',
    (tester) async {
      await initialize();
      await logic.startAutoWatch();
      expect(view.config!['handler'], 'FlutterNurtureStats');
      expect(view.config!['allowTransparentVideo'], isTrue);
      final session = repository.sessions.values.single;
      expect(session.email, 'Account@example.com');
      expect(session.configurationId, 42);
      final first = view.snapshot(1);
      await view.emit(first);
      expect((await repository.listAccounts()).single.totals.videos, 1);
      // The notification alone is not evidence of a persisted comment.
      logic.handleAutoWatchMessage('comment-sent');
      expect((await repository.listAccounts()).single.totals.comments, 0);
      final comment = view.snapshot(2, comments: 1);
      await view.emit(comment);
      expect((await repository.listAccounts()).single.totals.comments, 1);
      await view.emit(first);
      await view.emit(comment);
      await view.emit({...comment, 'session': 'another-account'});
      expect((await repository.listAccounts()).single.totals.videos, 1);
      expect((await repository.listAccounts()).single.totals.comments, 1);
      expect(repository.phases.values.single, 'running');
    },
  );

  testWidgets(
    'reloads and pause/resume add segments without duplicate totals',
    (tester) async {
      await initialize();
      await logic.startAutoWatch();
      await view.emit(view.snapshot(1, comments: 1));
      final oldSegment = view.config!['segment'];
      await logic.startAutoWatch();
      expect(view.config!['segment'], oldSegment);
      logic.onLoadStart(controller, WebUri('https://www.tiktok.com/'));
      await logic.startAutoWatch();
      expect(view.config!['segment'], isNot(oldSegment));
      await view.emit(view.snapshot(1));
      view.finalSnapshot = view.snapshot(2, comments: 1);
      await logic.stopAutoWatch();
      expect(repository.phases.values.single, 'paused');
      expect((await repository.listAccounts()).single.totals.videos, 2);
      expect((await repository.listAccounts()).single.totals.comments, 2);
      final pausedSegment = view.config!['segment'];
      await logic.startAutoWatch();
      expect(view.config!['segment'], pausedSegment);
      await view.emit(view.snapshot(3, videos: 2, comments: 1));
      expect(repository.sessions, hasLength(1));
      expect((await repository.listAccounts()).single.totals.videos, 3);
      expect(repository.phases.values.single, 'running');
    },
  );

  testWidgets('closing flushes the final snapshot and rejects later progress', (
    tester,
  ) async {
    await initialize();
    await logic.startAutoWatch();
    await view.emit(view.snapshot(1));
    view.finalSnapshot = view.snapshot(2, videos: 2, comments: 1);
    final lateSnapshot = view.snapshot(3, videos: 3, comments: 2);
    logic.onDelete();
    await tester.pump();
    expect(repository.phases.values.single, 'stopped');
    expect((await repository.listAccounts()).single.totals.videos, 2);
    expect((await repository.listAccounts()).single.totals.comments, 1);
    await view.emit(lateSnapshot);
    expect((await repository.listAccounts()).single.totals.videos, 2);
  });

  testWidgets(
    'timed completion saves progress before returning to the account list',
    (tester) async {
      await initialize();
      logic.autoWatchEnabled = false;
      logic.loginConfirmed = false;
      final results = <TikTokFlowResult>[];
      // The existing controller's completion notice follows the same awaited save path.
      logic.onNotice = (notice) {
        if (notice.message == 'Đã nuôi xong.') {
          expectSync(repository.totals.values.single.comments, 1);
          expectSync(repository.phases.values.single, 'completed');
          results.add(TikTokFlowResult.nurtureCompleted);
        }
      };
      final login = logic.autoLogin();
      await tester.pump();
      for (var i = 0; i < 100 && logic.autoLoginBusy; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await login;
      view.finalSnapshot = view.snapshot(1, comments: 1);
      // Sessions last 2–3 minutes.
      await tester.pump(const Duration(minutes: 3));
      expect(results, [TikTokFlowResult.nurtureCompleted]);
    },
  );
}
