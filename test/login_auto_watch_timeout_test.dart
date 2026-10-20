import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';
import 'package:test_tiktok/core/scripts/authenticated_session_script.dart';
import 'support/memory_nurture_store.dart';

class _WatchView extends PlatformInAppWebViewController {
  _WatchView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String loginResult = 'login-success';
  String signupResult = 'signup-success';
  bool acceptsWatch = true;
  bool authenticated = false;
  Completer<bool>? authentication;
  int authChecks = 0;
  int starts = 0;
  int stops = 0;
  int loginChecks = 0;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoLoginStepScript)) {
      loginChecks++;
      return loginResult;
    }
    if (source.contains(autoSignupStepScript)) return signupResult;
    if (source == checkAuthenticatedSessionScript) {
      authChecks++;
      if (authentication != null) return authentication!.future;
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

/// Always draws the longest (3-minute) or shortest (2-minute) session.
class _LongestRandom implements Random {
  _LongestRandom({this.shortest = false});
  final bool shortest;
  @override
  int nextInt(int max) => shortest ? 0 : max - 1;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

class _Session {
  _Session(
    WidgetTester tester, {
    DateTime Function()? now,
    TikTokLaunchAction launchAction = TikTokLaunchAction.login,
    bool startWithNurture = false,
    List<String> comments = const ['Test comment'],
    bool shortestNurture = false,
  }) {
    logic = TikTokController(
      configuration: AppConfiguration(
        userAgent: 'test-agent',
        comments: comments,
        signupEmail: 'signup@example.com',
        signupPassword: 'test-password',
        loginUsername: 'login@example.com',
        loginPassword: 'test-password',
      ),
      now: now ?? tester.binding.clock.now,
      workflowRandom: _LongestRandom(shortest: shortestNurture),
      launchAction: launchAction,
      startWithNurture: startWithNurture,
      useAccessibility: false,
      nurtureRepository: MemoryNurtureRepository(() async => []),
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
  testWidgets(
    'empty remote comments allow nurturing without automatic comments',
    (tester) async {
      final session = _Session(tester, comments: const []);
      session.logic.loginConfirmed = true;
      await session.logic.toggleAutoWatch();
      await tester.pump();
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.view.starts, 1);
      expect(session.notices, isEmpty);
      session.logic.onDelete();
      await tester.pump();
    },
  );

  testWidgets(
    'retained session starts another nurture session without logging in',
    (tester) async {
      final session = _Session(
        tester,
        launchAction: TikTokLaunchAction.browse,
        startWithNurture: true,
      );
      session.view.authenticated = true;
      session.logic.initialPageLoaded = true;
      await session.logic.runInitialAction();
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.view.authChecks, 1);
      expect(session.view.loginChecks, 0);
      await tester.pump(const Duration(minutes: 3));
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.notices.last, 'Đã nuôi xong.');
    },
  );

  testWidgets('an expired retained session logs in again before nurturing', (
    tester,
  ) async {
    final session = _Session(
      tester,
      launchAction: TikTokLaunchAction.browse,
      startWithNurture: true,
    );
    session.logic.initialPageLoaded = true;
    final run = session.logic.runInitialAction();
    for (var attempt = 0; attempt <= 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await run;
    expect(session.logic.autoWatchEnabled, isTrue);
    expect(session.logic.loginConfirmed, isTrue);
    expect(session.logic.autoWatchBusy, isFalse);
    expect(session.view.starts, 1);
    expect(session.view.loginChecks, greaterThan(0));
    await tester.pump(const Duration(minutes: 3));
    session.logic.onDelete();
  });

  testWidgets('manual browsing only starts nurturing when the user enables it', (
    tester,
  ) async {
    final session = _Session(tester, launchAction: TikTokLaunchAction.browse);
    session.view.authenticated = true;
    session.logic.initialPageLoaded = true;
    await session.logic.runInitialAction();
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.view.starts, 0);
    expect(session.view.authChecks, 0);
    await session.logic.toggleAutoWatch();
    expect(session.logic.loginConfirmed, isTrue);
    expect(session.logic.autoWatchEnabled, isTrue);
    expect(session.view.authChecks, 1);
    expect(session.view.loginChecks, 0);
    expect(session.view.starts, 1);
    await session.logic.toggleAutoWatch();
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.view.authChecks, 1);
    // Recheck the actual session on every manual start, including after logout.
    session.view.authenticated = false;
    await session.logic.toggleAutoWatch();
    expect(session.logic.loginConfirmed, isFalse);
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.view.starts, 1);
    expect(session.notices.last, contains('Hãy đăng nhập TikTok'));
    // Signing in directly on the page is enough; automatic login is optional.
    session.view.authenticated = true;
    await session.logic.toggleAutoWatch();
    expect(session.logic.autoWatchEnabled, isTrue);
    expect(session.view.starts, 2);
    expect(session.view.loginChecks, 0);
  });

  testWidgets('manual browsing cannot nurture before TikTok is logged in', (
    tester,
  ) async {
    final session = _Session(tester, launchAction: TikTokLaunchAction.browse);
    await session.logic.toggleAutoWatch();
    expect(session.logic.loginConfirmed, isFalse);
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.logic.autoWatchBusy, isFalse);
    expect(session.view.authChecks, 1);
    expect(session.view.starts, 0);
    expect(session.view.loginChecks, 0);
    expect(session.notices.last, contains('Hãy đăng nhập TikTok'));
  });

  testWidgets('manual session confirmation cannot start on a different page', (
    tester,
  ) async {
    final session = _Session(tester, launchAction: TikTokLaunchAction.browse);
    session.view.authentication = Completer<bool>();
    final starting = session.logic.toggleAutoWatch();
    await tester.pump();
    expect(session.logic.autoWatchBusy, isTrue);
    await session.logic.toggleAutoWatch();
    expect(session.view.authChecks, 1);
    session.logic.navigationId++;
    session.view.authentication!.complete(true);
    await starting;
    expect(session.logic.loginConfirmed, isFalse);
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.logic.autoWatchBusy, isFalse);
    expect(session.view.starts, 0);
  });

  for (final result in ['login-success', 'already-logged-in']) {
    testWidgets('$result starts watching and stops after three minutes', (
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
          const Duration(minutes: 2, seconds: 59, milliseconds: 979),
        );
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(milliseconds: 21));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(session.view.stops, stops + 1);
        expect(session.notices.last, 'Đã nuôi xong.');
        session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(session.view.starts, 1);
      } finally {
        session.logic.onDelete();
      }
    });
  }

  testWidgets('the shortest nurture draw stops after two minutes', (
    tester,
  ) async {
    final session = _Session(tester, shortestNurture: true);
    try {
      await session.login(tester);
      await tester.pump(
        const Duration(minutes: 1, seconds: 59, milliseconds: 979),
      );
      expect(session.logic.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(milliseconds: 21));
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.notices.last, 'Đã nuôi xong.');
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets('reloading the document keeps the original watch deadline', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.login(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 30));
      await session.logic.startAutoWatch();
      expect(session.view.starts, 2);
      await tester.pump(const Duration(minutes: 1, seconds: 30));
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(
        session.notices.where((notice) => notice == 'Đã nuôi xong.'),
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
      now = now.add(const Duration(minutes: 4));
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.view.starts, 1);
      expect(session.notices.last, 'Đã nuôi xong.');
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
        await tester.pump(const Duration(minutes: 1));
        await session.logic.toggleAutoWatch();
        expect(session.logic.autoWatchEnabled, isFalse);
        await session.login(tester);
        await tester.pump(const Duration(minutes: 2, seconds: 30));
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(seconds: 30));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(
          session.notices.where((notice) => notice == 'Đã nuôi xong.'),
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
        expect(session.notices.contains('Đã nuôi xong.'), isFalse);
      } finally {
        session.logic.onDelete();
      }
    });
  }
}
