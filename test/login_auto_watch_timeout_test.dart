import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';
import 'package:test_tiktok/core/scripts/authenticated_session_script.dart';

class _WatchView extends PlatformInAppWebViewController {
  _WatchView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String loginResult = 'login-success';
  String signupResult = 'signup-success';
  bool acceptsWatch = true;
  bool authenticated = false;
  int authChecks = 0;
  int starts = 0;
  int stops = 0;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoLoginStepScript)) return loginResult;
    if (source.contains(autoSignupStepScript)) return signupResult;
    if (source == checkAuthenticatedSessionScript) {
      authChecks++;
      return authenticated;
    }
    if (source.contains(autoWatchStartScript)) {
      starts++;
      return acceptsWatch;
    }
    if (source == autoWatchStopScript) stops++;
    return true;
  }
}

class _Session {
  _Session(WidgetTester tester, {DateTime Function()? now}) {
    logic = TikTokController(
      configuration: AppConfiguration(
        userAgent: 'test-agent',
        comments: ['Test comment'],
        signupEmail: 'signup@example.com',
        signupPassword: 'test-password',
        loginUsername: 'login@example.com',
        loginPassword: 'test-password',
      ),
      now: now ?? tester.binding.clock.now,
      useAccessibility: false,
    )..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: view,
    );
    logic.onNotice = (notice) => notices.add(notice.message);
    addTearDown(() => logic.onDelete());
  }

  late final TikTokController logic;
  final view = _WatchView();
  final notices = <String>[];

  Future<void> login(WidgetTester tester) async {
    final login = logic.autoLogin();
    await tester.pump();
    for (var tick = 0; tick < 500 && logic.autoLoginBusy; tick++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(logic.autoLoginBusy, isFalse);
    await login;
  }

  Future<void> signup(WidgetTester tester) async {
    final signup = logic.autoSignup();
    await tester.pump();
    for (var tick = 0; tick < 500 && logic.autoSignupBusy; tick++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(logic.autoSignupBusy, isFalse);
    await signup;
  }
}

void main() {
  for (final result in ['login-success', 'already-logged-in']) {
    testWidgets('$result starts watching and stops after ten minutes', (
      tester,
    ) async {
      final session = _Session(tester)..view.loginResult = result;
      try {
        await session.login(tester);
        expect(session.logic.autoWatchEnabled, isTrue);
        expect(session.logic.loginConfirmed, isTrue);
        expect(session.view.starts, 1);
        final stops = session.view.stops;
        await tester.pump(
          const Duration(minutes: 9, seconds: 59, milliseconds: 979),
        );
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(milliseconds: 21));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(session.view.stops, stops + 1);
        expect(session.notices.last, 'Đã nuôi xong sau 10 phút.');
        session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(session.view.starts, 1);
      } finally {
        session.logic.onDelete();
      }
    });
  }

  testWidgets('reloading the document keeps the original watch deadline', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.login(tester);
      await tester.pump(const Duration(minutes: 5));
      await session.logic.startAutoWatch();
      expect(session.view.starts, 2);
      await tester.pump(const Duration(minutes: 5));
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(
        session.notices.where((notice) => notice.contains('10 phút')),
        hasLength(1),
      );
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets('returning after a suspended deadline never restarts watching', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 16);
    final session = _Session(tester, now: () => now);
    try {
      await session.login(tester);
      session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      now = now.add(const Duration(minutes: 11));
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.view.starts, 1);
      expect(session.notices.last, 'Đã nuôi xong sau 10 phút.');
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets(
    'stopping early cancels the old timer before a new login session',
    (tester) async {
      final session = _Session(tester);
      try {
        await session.login(tester);
        await tester.pump(const Duration(minutes: 4));
        await session.logic.toggleAutoWatch();
        expect(session.logic.autoWatchEnabled, isFalse);
        await session.login(tester);
        await tester.pump(const Duration(minutes: 6));
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(minutes: 4));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(
          session.notices.where((notice) => notice.contains('10 phút')),
          hasLength(1),
        );
      } finally {
        session.logic.onDelete();
      }
    },
  );

  testWidgets(
    'closing TikTok cancels the timer without later commands or notices',
    (tester) async {
      final session = _Session(tester);
      await session.login(tester);
      session.logic.onDelete();
      await tester.pump();
      final stops = session.view.stops;
      final notices = session.notices.length;
      await tester.pump(const Duration(minutes: 11));
      expect(session.view.stops, stops);
      expect(session.notices, hasLength(notices));
    },
  );

  for (final result in ['signup-success', 'already-logged-in']) {
    testWidgets('signup $result leaves watching under user control', (
      tester,
    ) async {
      final session = _Session(tester)..view.signupResult = result;
      try {
        await session.signup(tester);
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(session.view.starts, 0);
        expect(
          session.notices.single,
          result == 'signup-success'
              ? 'Đăng ký TikTok thành công.'
              : 'Tài khoản TikTok đã đăng nhập.',
        );
        await tester.pump(const Duration(minutes: 15));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(session.view.starts, 0);
      } finally {
        session.logic.onDelete();
      }
    });
  }

  for (final result in [
    'verification-required',
    'verification-requested',
    'draft-exists',
    'paste-failed',
    'login-error',
  ]) {
    testWidgets('manual completion after $result never starts watching', (
      tester,
    ) async {
      final session = _Session(tester)..view.loginResult = result;
      await session.login(tester);
      expect(session.logic.autoLoginBusy, isFalse);
      session.view.authenticated = true;
      await tester.pump(const Duration(seconds: 5));
      session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 15));
      await session.logic.toggleAutoWatch();
      expect(session.logic.loginConfirmed, isFalse);
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.view.authChecks, 0);
      expect(session.view.starts, 0);

      // A successful new automatic attempt is required to enable watching.
      session.view.loginResult = 'login-success';
      await session.login(tester);
      expect(session.logic.loginConfirmed, isTrue);
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.view.starts, 1);
      session.logic.onDelete();
    });
  }

  testWidgets('signup does not start watching after reload or app resume', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.signup(tester);
      await session.logic.startAutoWatch();
      session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 4));
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 15));
      expect(session.view.starts, 0);
      expect(session.logic.autoWatchEnabled, isFalse);
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets('watching is blocked after signup until login succeeds', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.signup(tester);
      await session.logic.toggleAutoWatch();
      expect(session.view.starts, 0);
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.logic.loginConfirmed, isFalse);
      await session.login(tester);
      expect(session.view.starts, 1);
      expect(session.logic.autoWatchEnabled, isTrue);
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets('watching is blocked before login and after a new signup', (
    tester,
  ) async {
    final session = _Session(tester);
    await session.logic.toggleAutoWatch();
    expect(session.view.starts, 0);
    await session.login(tester);
    expect(session.logic.loginConfirmed, isTrue);
    await session.signup(tester);
    expect(session.logic.loginConfirmed, isFalse);
    await session.logic.toggleAutoWatch();
    await tester.pump(const Duration(minutes: 15));
    expect(session.view.starts, 1);
    expect(session.logic.autoWatchEnabled, isFalse);
  });

  testWidgets('a failed signup never schedules automatic watching', (
    tester,
  ) async {
    final session = _Session(tester)..view.signupResult = 'signup-error';
    try {
      await session.signup(tester);
      await tester.pump(const Duration(minutes: 15));
      expect(session.view.starts, 0);
    } finally {
      session.logic.onDelete();
    }
  });

  for (final result in ['login-error', 'verification-required']) {
    testWidgets('$result does not start a timed watch session', (tester) async {
      final session = _Session(tester)..view.loginResult = result;
      try {
        await session.login(tester);
        expect(session.logic.autoWatchEnabled, isFalse);
        await tester.pump(const Duration(minutes: 11));
        expect(session.view.starts, 0);
        expect(
          session.notices.any((notice) => notice.contains('10 phút')),
          isFalse,
        );
      } finally {
        session.logic.onDelete();
      }
    });
  }
}
