import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';

class _WatchView extends PlatformInAppWebViewController {
  _WatchView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String loginResult = 'login-success';
  String signupResult = 'signup-success';
  bool acceptsWatch = true;
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
        expect(session.view.starts, 1);
        final stops = session.view.stops;
        await tester.pump(
          const Duration(minutes: 9, seconds: 59, milliseconds: 979),
        );
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(milliseconds: 21));
        expect(session.logic.autoWatchEnabled, isFalse);
        expect(session.view.stops, stops + 1);
        expect(session.notices.last, 'Đã tự tắt Auto nuôi sau 10 phút.');
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
      expect(session.notices.last, 'Đã tự tắt Auto nuôi sau 10 phút.');
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

  testWidgets('signup waits 2–3 minutes, then watches for ten minutes', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.signup(tester);
      expect(session.logic.waitingToAutoWatch, isTrue);
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.view.starts, 0);
      final wait = session.logic.autoWatchStartsAt!.difference(
        tester.binding.clock.now(),
      );
      expect(
        wait,
        greaterThanOrEqualTo(
          const Duration(minutes: 2) - const Duration(milliseconds: 20),
        ),
      );
      expect(wait, lessThanOrEqualTo(const Duration(minutes: 3)));
      await tester.pump(wait - const Duration(milliseconds: 1));
      expect(session.view.starts, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(session.logic.waitingToAutoWatch, isFalse);
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.view.starts, 1);
      await tester.pump(const Duration(minutes: 9, seconds: 59));
      expect(session.logic.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(session.logic.autoWatchEnabled, isFalse);
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets(
    'signup hold survives reload and begins only when back in the app',
    (tester) async {
      final session = _Session(tester);
      try {
        await session.signup(tester);
        final startsAt = session.logic.autoWatchStartsAt;
        await tester.pump(const Duration(minutes: 1));
        await session.logic.startAutoWatch();
        expect(session.logic.autoWatchStartsAt, startsAt);
        session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump(const Duration(minutes: 4));
        expect(session.view.starts, 0);
        expect(session.logic.waitingToAutoWatch, isTrue);
        session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(session.view.starts, 1);
        expect(session.logic.autoWatchEnabled, isTrue);
        await tester.pump(const Duration(minutes: 10));
        expect(session.logic.autoWatchEnabled, isFalse);
      } finally {
        session.logic.onDelete();
      }
    },
  );

  testWidgets(
    'cancelling or closing a signup hold prevents its scheduled watcher',
    (tester) async {
      for (final close in [false, true]) {
        final session = _Session(tester);
        try {
          await session.signup(tester);
          if (close) {
            session.logic.onDelete();
          } else {
            session.logic.cancelAutoWatchHold();
          }
          await tester.pump(const Duration(minutes: 15));
          expect(session.view.starts, 0);
          expect(session.logic.waitingToAutoWatch, isFalse);
        } finally {
          session.logic.onDelete();
        }
      }
    },
  );

  testWidgets('starting during the signup hold still stops after ten minutes', (
    tester,
  ) async {
    final session = _Session(tester);
    try {
      await session.signup(tester);
      await session.logic.toggleAutoWatch();
      expect(session.logic.waitingToAutoWatch, isFalse);
      expect(session.view.starts, 1);
      await tester.pump(const Duration(minutes: 3));
      expect(session.view.starts, 1);
      expect(session.logic.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(minutes: 7));
      expect(session.logic.autoWatchEnabled, isFalse);
    } finally {
      session.logic.onDelete();
    }
  });

  testWidgets('a failed signup never schedules automatic watching', (
    tester,
  ) async {
    final session = _Session(tester)..view.signupResult = 'signup-error';
    try {
      await session.signup(tester);
      expect(session.logic.waitingToAutoWatch, isFalse);
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
