import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/signup_birthday_menu.dart';
import 'package:test_tiktok/core/signup_coordinate_runner.dart';

void main() {
  late SignupCoordinateProfile profile;
  late Map<String, dynamic> recording;
  setUp(() {
    profile = SignupCoordinateProfile(
      jsonDecode(
        File('assets/signup-coordinate-profile.json').readAsStringSync(),
      ),
    );
    recording = jsonDecode(
      File(
        'test/fixtures/signup_accessibility_recording.json',
      ).readAsStringSync(),
    );
  });

  for (final width in [1920.0, 1280.0, 960.0]) {
    testWidgets('desktop signup follows live fields at frame width $width', (
      tester,
    ) async {
      final accessibility = _RecordedAccessibility(profile, recording)
        ..desktopBounds = Rect.fromLTWH(317, 219, width, width * 955 / 1920)
        ..geckoComboboxes = true
        ..otpNeedsSubmit = true
        ..otpAutofocusKeyboard = true;
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: 'desktop',
          comments: [],
          signupEmail: 'test@example.org',
          signupPassword: 'Example12!a',
          loginUsername: '',
          loginPassword: '',
          birthday: DateTime(2000, 2, 29),
        ),
        isActive: () => true,
        isTikTok: () async => true,
        getOtp: () async => '123456',
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      Object? failure;
      var finished = false;
      final run = runner.run().then<void>(
        (_) => finished = true,
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      );
      for (var i = 0; i < 600 && !finished; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(finished, isTrue);
      await run;
      expect(failure, isNull, reason: '${accessibility.actions}');
      expect(accessibility.state, 'authenticated-home');
      expect(accessibility.pastes, ['email', 'otp', 'password']);
      expect(accessibility.keyboardPolicies, [
        true, // Hold through all account transitions, including OTP autofocus.
        true, true, // Email: suppress and renew.
        true, true, // OTP.
        true, true, // Password.
        false, // Always restore at the end.
      ]);
      expect(accessibility.keyboardRenewals, greaterThan(0));
      expect(
        accessibility.actions.where((a) => a == 'submit-otp'),
        hasLength(1),
      );
      expect(accessibility.selected, {
        'Year': '2000',
        'Month': 'February',
        'Day': '29',
      });
    });
  }

  for (final scenario in [
    'loaded-page',
    'delayed-load',
    'reload-during-wait',
    'transient-webview',
    'moving-button',
    'late-button',
    'never-ready',
    'invalid-frame',
    'service-stalled',
    'webview-missing',
    'cancel-during-startup',
  ]) {
    testWidgets('waits before opening Log in: $scenario', (tester) async {
      final started = tester.binding.clock.now();
      Duration elapsed() => tester.binding.clock.now().difference(started);
      final accessibility = _RecordedAccessibility(profile, recording);
      accessibility.onHomeSnapshot = (data) {
        if (scenario == 'transient-webview' && elapsed().inSeconds < 4) {
          data['ready'] = false;
          data['webBounds'] = [0, 0, 0, 0];
        }
        if (scenario == 'webview-missing') {
          // The service runs but no WebView node is exposed.
          data['ready'] = false;
        }
        if (scenario == 'service-stalled') {
          // Enabled in Android settings but not bound: nothing is readable.
          data['ready'] = false;
          data['serviceConnected'] = false;
        }
        if (scenario == 'invalid-frame') {
          // A WebView frame clipped off its 1:2 ratio is never tapped.
          data['webBounds'] = [0, 210, 1080, 1900];
        }
        final nodes = data['nodes'] as List;
        if (scenario == 'late-button' && elapsed().inSeconds < 6) {
          nodes.removeWhere((n) => n['text'] == 'Log in');
        }
        if (scenario == 'moving-button' &&
            elapsed().inSeconds >= 4 &&
            elapsed().inSeconds < 6) {
          for (final node in nodes) {
            if (node['text'] == 'Log in') {
              node['bounds'] = [950, 323, 1034, 358];
            }
          }
        }
      };
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: '',
          comments: [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: '',
          loginPassword: '',
        ),
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () =>
            scenario != 'never-ready' &&
            (scenario != 'delayed-load' || elapsed().inSeconds >= 4) &&
            (scenario != 'reload-during-wait' ||
                elapsed().inSeconds < 4 ||
                elapsed().inSeconds >= 6),
        getOtp: () async => throw StateError('Must not fetch OTP'),
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      Duration? tappedAt;
      accessibility.afterTap = (name) {
        if (name == 'open-login') {
          tappedAt = elapsed();
          runner.cancel();
        }
      };
      var finished = false;
      Object? failure;
      final run = runner.run().then<void>(
        (_) {
          finished = true;
        },
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      );
      for (var i = 0; i < 650 && !finished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (scenario == 'cancel-during-startup' && elapsed().inSeconds >= 2) {
          runner.cancel();
        }
      }
      expect(finished, isTrue);
      await run;
      if (scenario == 'webview-missing') {
        expect(
          '$failure',
          contains(
            'không đọc được WebView qua Trợ năng [active=app win=2 app=1 '
            'n=40 foreign=0 web=GeckoView v1 c0 d12 942x1884]',
          ),
        );
        expect(accessibility.actions, isEmpty);
      } else if (scenario == 'service-stalled') {
        expect('$failure', contains('dịch vụ Trợ năng chưa chạy'));
        expect(tappedAt, isNull);
        expect(accessibility.actions, isEmpty);
      } else if (scenario == 'invalid-frame') {
        expect(
          '$failure',
          contains('khung WebView 1080×1690 không đúng tỉ lệ chuẩn'),
        );
        expect(tappedAt, isNull);
        expect(accessibility.actions, isEmpty);
      } else if (scenario == 'cancel-during-startup') {
        expect(failure, isA<SignupCancelled>());
        expect(tappedAt, isNull);
        expect(accessibility.actions, isEmpty);
      } else {
        final minimumSeconds = switch (scenario) {
          // No load event: a stable Log in is accepted after 20s.
          'never-ready' => 20,
          'reload-during-wait' => 11,
          'delayed-load' || 'transient-webview' => 9,
          'moving-button' || 'late-button' => 8,
          _ => 5,
        };
        expect(tappedAt, isNotNull);
        expect(
          tappedAt!,
          greaterThanOrEqualTo(Duration(seconds: minimumSeconds)),
        );
        expect(failure, isA<SignupCancelled>());
        expect(accessibility.actions, ['open-login']);
      }
      expect(accessibility.pastes, isEmpty);
    });
  }

  for (final scenario in [
    'login-modal',
    'hidden-home',
    'signup-method',
    'auto-open-login',
    'auto-open-signup',
    'moving-signup-target',
    'missing-signup-target',
    'disabled-signup-target',
    'misaligned-signup-target',
    'page-loading',
    'cancel-modal',
  ]) {
    testWidgets('starts from an open account modal: $scenario', (tester) async {
      final started = tester.binding.clock.now();
      Duration elapsed() => tester.binding.clock.now().difference(started);
      final accessibility = _RecordedAccessibility(profile, recording)
        ..state = scenario.startsWith('auto-open')
            ? 'home-ready'
            : scenario == 'signup-method'
            ? 'signup-method'
            : 'login-modal';
      accessibility.onSnapshot = (data) {
        if (scenario.startsWith('auto-open') &&
            accessibility.state == 'home-ready' &&
            elapsed().inSeconds >= 4) {
          accessibility.state = scenario == 'auto-open-login'
              ? 'login-modal'
              : 'signup-method';
          data
            ..clear()
            ..addAll(jsonDecode(jsonEncode(recording[accessibility.state])));
        }
        if (accessibility.state != 'login-modal') return;
        final nodes = data['nodes'] as List;
        if (scenario == 'hidden-home') {
          nodes.removeWhere((n) => n['text'] == 'Log in');
          // Background navigation must not make the modal look authenticated.
          nodes.add({...nodes.first, 'id': 'background', 'text': 'Messages'});
        }
        if (scenario == 'missing-signup-target') {
          nodes.removeWhere((n) => n['text'] == 'Sign up');
        }
        for (final node in nodes) {
          if (node['text'] != 'Sign up') continue;
          if (scenario == 'disabled-signup-target') node['enabled'] = false;
          if (scenario == 'misaligned-signup-target') {
            node['bounds'] = [10, 10, 50, 50];
          }
          if (scenario == 'moving-signup-target' &&
              elapsed().inSeconds >= 4 &&
              elapsed().inSeconds < 6) {
            node['bounds'] = [597, 1616, 656, 1636];
          }
        }
      };
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: '',
          comments: [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: '',
          loginPassword: '',
        ),
        isActive: () => true,
        isTikTok: () async => true,
        isPageReady: () => scenario != 'page-loading',
        getOtp: () async => throw StateError('Must not fetch OTP'),
        onStatus: (_) {},
        now: tester.binding.clock.now,
      );
      Duration? firstTapAt;
      accessibility.afterTap = (name) {
        firstTapAt ??= elapsed();
        if (name == 'signup-phone-email') runner.cancel();
      };
      Object? failure;
      var finished = false;
      final run = runner.run().then<void>(
        (_) => finished = true,
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      );
      for (var i = 0; i < 650 && !finished; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (scenario == 'cancel-modal' && elapsed().inSeconds >= 2) {
          runner.cancel();
        }
      }
      expect(finished, isTrue);
      await run;
      if (scenario.endsWith('signup-target') &&
          scenario != 'moving-signup-target') {
        expect(failure, isA<StateError>());
        expect(accessibility.actions, isEmpty);
        if (scenario == 'disabled-signup-target') {
          expect('$failure', contains('nút "Sign up" đang bị tắt'));
        }
        if (scenario == 'missing-signup-target') {
          expect('$failure', contains('không thấy nút "Sign up"'));
        }
      } else if (scenario == 'cancel-modal') {
        expect(failure, isA<SignupCancelled>());
        expect(accessibility.actions, isEmpty);
      } else {
        expect(failure, isA<SignupCancelled>());
        expect(
          accessibility.actions,
          scenario == 'signup-method' || scenario == 'auto-open-signup'
              ? ['signup-phone-email']
              : ['open-signup', 'signup-phone-email'],
        );
        final minimumSeconds = scenario == 'page-loading'
            ? 20
            : scenario == 'moving-signup-target'
            ? 8
            : scenario.startsWith('auto-open')
            ? 6
            : 5;
        expect(
          firstTapAt,
          greaterThanOrEqualTo(Duration(seconds: minimumSeconds)),
        );
      }
      expect(runner.alreadyLoggedIn, isFalse);
      expect(accessibility.pastes, isEmpty);
    });
  }

  for (final scenario in [
    'success',
    'resume-login-modal',
    'resume-signup-method',
    'paste-rejected',
    'cancel-after-otp',
    'skip-rejected',
    'birthday-readback-mismatch',
    'leap-day',
    'last-day',
    'earliest-year',
    'dropdown-not-moving',
    'html-dropdown',
    'html-dropdown-not-moving',
    'gecko-combobox',
    'transient-after-otp',
    'transient-after-skip',
    'login-required-after-skip',
    'signed-out-after-skip',
    'signed-out-before-sign-in',
  ]) {
    testWidgets('recorded Android Accessibility flow: $scenario', (
      tester,
    ) async {
      final accessibility = _RecordedAccessibility(profile, recording);
      if (scenario.startsWith('resume-')) {
        accessibility.state = scenario.substring('resume-'.length);
      }
      final configuration = AppConfiguration(
        userAgent: 'test',
        comments: [],
        signupEmail: 'test@example.org',
        signupPassword: 'Example12!a',
        loginUsername: '',
        loginPassword: '',
        birthday: switch (scenario) {
          'leap-day' => DateTime(2000, 2, 29),
          'last-day' => DateTime(1999, 12, 31),
          'earliest-year' => DateTime(1960, 4, 30),
          'html-dropdown' => DateTime(2000, 2, 29),
          _ => DateTime(2001, 2, 3),
        },
      );
      if (scenario == 'paste-rejected') accessibility.rejectEmail = true;
      accessibility.failBirthdayReadback =
          scenario == 'birthday-readback-mismatch';
      accessibility.freezeDropdown = scenario.endsWith('dropdown-not-moving');
      accessibility.hideNativeOptions = scenario.startsWith('html-');
      accessibility.geckoComboboxes = scenario == 'gecko-combobox';
      var missingReads = 0;
      accessibility.onSnapshot = (data) {
        final transition = scenario == 'transient-after-otp'
            ? 'otp-context-paste-result'
            : scenario == 'transient-after-skip'
            ? 'authenticated-home'
            : null;
        if (transition != null &&
            accessibility.state == transition &&
            missingReads++ < 3) {
          data['ready'] = false;
          data['webBounds'] = [0, 0, 0, 0];
        }
      };
      var otpRequests = 0;
      var skipped = 0;
      accessibility.rejectSkip = scenario == 'skip-rejected';
      if (scenario == 'login-required-after-skip') {
        accessibility.afterTap = (name) {
          if (name == 'skip-username') accessibility.state = 'login-modal';
        };
      }
      // TikTok closes the modal on a signed-out feed: for good, or briefly
      // before the reload that signs the page in.
      var signedOutReads = 0;
      if (scenario.startsWith('signed-out-')) {
        accessibility.afterTap = (name) {
          if (name == 'skip-username') accessibility.state = 'home-ready';
        };
        final onSnapshot = accessibility.onSnapshot;
        accessibility.onSnapshot = (data) {
          onSnapshot?.call(data);
          if (scenario == 'signed-out-before-sign-in' &&
              accessibility.state == 'home-ready' &&
              skipped == 1 &&
              ++signedOutReads == 3) {
            accessibility.state = 'authenticated-home';
          }
        };
      }
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: configuration,
        isActive: () => true,
        isTikTok: () async => true,
        getOtp: () async {
          expectSync(accessibility.actions, contains('send-code'));
          otpRequests++;
          return '123456';
        },
        onStatus: (_) {},
        onUsernameSkipped: () async {
          expectSync(accessibility.actions.last, 'skip-username');
          skipped++;
        },
        readBirthdayMenu: accessibility.readBirthdayMenu,
        now: tester.binding.clock.now,
      );
      if (scenario == 'cancel-after-otp') {
        accessibility.afterOtpPaste = runner.cancel;
      }
      Object? failure;
      var finished = false;
      final run = runner.run().then(
        (_) {
          finished = true;
        },
        onError: (Object error) {
          failure = error;
          finished = true;
        },
      );
      for (var i = 0; i < 600 && !finished; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        finished,
        isTrue,
        reason:
            'state=${accessibility.state}, actions=${accessibility.actions}',
      );
      await run;
      if ([
        'success',
        'resume-login-modal',
        'resume-signup-method',
        'leap-day',
        'last-day',
        'earliest-year',
        'html-dropdown',
        'gecko-combobox',
        'transient-after-otp',
        'transient-after-skip',
        'login-required-after-skip',
        'signed-out-after-skip',
        'signed-out-before-sign-in',
      ].contains(scenario)) {
        expect(failure, isNull);
        expect(skipped, 1);
        final requiresLogin = [
          'login-required-after-skip',
          'signed-out-after-skip',
        ].contains(scenario);
        expect(
          accessibility.state,
          switch (scenario) {
            'login-required-after-skip' => 'login-modal',
            'signed-out-after-skip' => 'home-ready',
            _ => 'authenticated-home',
          },
        );
        expect(runner.requiresLogin, requiresLogin);
        expect(otpRequests, 1);
        expect(accessibility.pastes, ['email', 'otp', 'password']);
        expect(
          accessibility.selected['Year'],
          '${configuration.birthday!.year}',
        );
        expect(accessibility.selected['Day'], '${configuration.birthday!.day}');
        expect(
          accessibility.actions.where((s) => s == 'send-code'),
          hasLength(1),
        );
        expect(
          accessibility.actions.where((s) => s == 'submit-password'),
          hasLength(1),
        );
        expect(
          accessibility.actions.where((s) => s == 'skip-username'),
          hasLength(1),
        );
      } else if (scenario == 'skip-rejected') {
        expect(failure, isA<StateError>());
        expect(skipped, 0);
        expect(accessibility.state, 'signup-result-settled');
      } else {
        expect(failure, isNotNull);
        expect(skipped, 0);
        expect(accessibility.actions, isNot(contains('submit-password')));
        if (scenario != 'cancel-after-otp') {
          expect(accessibility.actions, isNot(contains('send-code')));
          expect(otpRequests, 0);
        } else {
          expect(failure, isA<SignupCancelled>());
          expect(accessibility.actions, isNot(contains('focus-password')));
        }
      }
    });
  }

  testWidgets(
    'resumes the HTML year menu already open on the birthday screen',
    (tester) async {
      final accessibility = _RecordedAccessibility(profile, recording)
        ..state = 'email-birthday'
        ..picker = 'Year'
        ..hideNativeOptions = true;
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: '',
          comments: [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: '',
          loginPassword: '',
          birthday: DateTime(1960, 12, 31),
        ),
        isActive: () => true,
        isTikTok: () async => true,
        getOtp: () async => throw StateError('Must not fetch OTP'),
        onStatus: (_) {},
        readBirthdayMenu: accessibility.readBirthdayMenu,
        now: tester.binding.clock.now,
      );
      var finished = false;
      final run = runner.selectBirthday().whenComplete(() {
        finished = true;
      });
      for (var i = 0; i < 300 && !finished; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await run;
      expect(accessibility.selected, {
        'Year': '1960',
        'Month': 'December',
        'Day': '31',
      });
      expect(accessibility.actions, isNot(contains('open-year')));
      expect(accessibility.actions, isNot(contains('send-code')));
      expect(accessibility.pastes, isEmpty);
    },
  );

  for (final html in [false, true]) {
    for (final missedSwipes in [1, 2]) {
      testWidgets('recovers $missedSwipes missed birthday swipes, HTML=$html', (
        tester,
      ) async {
        final accessibility = _RecordedAccessibility(profile, recording)
          ..state = 'email-birthday'
          ..picker = 'Year'
          ..hideNativeOptions = html
          ..ignoredSwipes = missedSwipes;
        final runner = SignupCoordinateRunner(
          profile: profile,
          accessibility: accessibility,
          configuration: AppConfiguration(
            userAgent: '',
            comments: [],
            signupEmail: '',
            signupPassword: '',
            loginUsername: '',
            loginPassword: '',
            birthday: DateTime(1971, 7, 6),
          ),
          isActive: () => true,
          isTikTok: () async => true,
          getOtp: () async => throw StateError('Must not fetch OTP'),
          onStatus: (_) {},
          readBirthdayMenu: accessibility.readBirthdayMenu,
          now: tester.binding.clock.now,
        );
        var finished = false;
        final run = runner.selectBirthday().whenComplete(() => finished = true);
        for (var i = 0; i < 350 && !finished; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(finished, isTrue);
        await run;
        expect(accessibility.selected, {
          'Year': '1971',
          'Month': 'July',
          'Day': '6',
        });
        expect(accessibility.actions, isNot(contains('send-code')));
        expect(accessibility.pastes, isEmpty);
      });
    }
  }

  testWidgets(
    'already authenticated recording does not send code or paste data',
    (tester) async {
      final accessibility = _RecordedAccessibility(profile, recording)
        ..state = 'authenticated-home';
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: accessibility,
        configuration: AppConfiguration(
          userAgent: '',
          comments: [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: '',
          loginPassword: '',
        ),
        isActive: () => true,
        isTikTok: () async => true,
        getOtp: () async => throw StateError('Must not fetch OTP'),
        onStatus: (_) {},
      );
      await runner.run();
      expect(runner.alreadyLoggedIn, isTrue);
      expect(accessibility.actions, isEmpty);
      expect(accessibility.pastes, isEmpty);
    },
  );

  for (final maximum in [false, true]) {
    testWidgets(
      'birthday actions wait ${maximum ? 3 : 1}s, other signup actions '
      '${maximum ? 7 : 2}s and post-OTP 650ms',
      (tester) async {
        final accessibility = _RecordedAccessibility(profile, recording);
        final actions = <({String name, DateTime at})>[];
        accessibility.onAction = (name) =>
            actions.add((name: name, at: tester.binding.clock.now()));
        final runner = SignupCoordinateRunner(
          profile: profile,
          accessibility: accessibility,
          configuration: AppConfiguration(
            userAgent: 'agent',
            comments: [],
            signupEmail: 'test@example.org',
            signupPassword: 'Example12!a',
            loginUsername: '',
            loginPassword: '',
            birthday: DateTime(2001, 2, 3),
          ),
          isActive: () => true,
          isTikTok: () async => true,
          getOtp: () async => '123456',
          onStatus: (_) {},
          now: tester.binding.clock.now,
          random: _BoundaryRandom(maximum),
        );
        var finished = false;
        final run = runner.run().whenComplete(() => finished = true);
        for (var i = 0; i < 10000 && !finished; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(finished, isTrue);
        await run;
        expect(accessibility.state, 'authenticated-home');
        expect(actions.any((action) => action.name.endsWith('-swipe')), isTrue);
        expect(actions.any((action) => action.name == 'paste-email'), isTrue);
        expect(
          actions.any((action) => action.name == 'paste-password'),
          isTrue,
        );
        for (var i = 1; i < actions.length; i++) {
          final previous = actions[i - 1];
          final next = actions[i];
          expect(
            next.at.difference(previous.at),
            previous.name == 'paste-otp'
                ? const Duration(milliseconds: 650)
                : RegExp(
                    r'^(open|select)-(year|month|day)$|^(year|month|day)-swipe$',
                  ).hasMatch(previous.name)
                ? Duration(seconds: maximum ? 3 : 1)
                : Duration(seconds: maximum ? 7 : 2),
            reason: '${previous.name} → ${next.name}',
          );
        }
      },
    );
  }

  testWidgets('cancelling during an action delay prevents the next gesture', (
    tester,
  ) async {
    final accessibility = _RecordedAccessibility(profile, recording);
    final runner = SignupCoordinateRunner(
      profile: profile,
      accessibility: accessibility,
      configuration: AppConfiguration(
        userAgent: '',
        comments: [],
        signupEmail: 'test@example.org',
        signupPassword: 'Example12!a',
        loginUsername: '',
        loginPassword: '',
      ),
      isActive: () => true,
      isTikTok: () async => true,
      getOtp: () async => throw StateError('Must not fetch OTP'),
      onStatus: (_) {},
      now: tester.binding.clock.now,
      random: _BoundaryRandom(true),
    );
    Object? failure;
    final run = runner.run().catchError((Object error) {
      failure = error;
    });
    while (accessibility.actions.isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    runner.cancel();
    await tester.pump(const Duration(seconds: 7));
    await run;
    expect(failure, isA<SignupCancelled>());
    expect(accessibility.actions, ['open-login']);
    expect(accessibility.pastes, isEmpty);
  });

  testWidgets('a covered app pauses gestures and continues when uncovered', (
    tester,
  ) async {
    final accessibility = _RecordedAccessibility(profile, recording);
    var foreground = true;
    final runner = SignupCoordinateRunner(
      profile: profile,
      accessibility: accessibility,
      configuration: AppConfiguration(
        userAgent: '',
        comments: [],
        signupEmail: 'test@example.org',
        signupPassword: 'Example12!a',
        loginUsername: '',
        loginPassword: '',
      ),
      isActive: () => true,
      isForeground: () => foreground,
      isTikTok: () async => true,
      getOtp: () async => throw StateError('Must not fetch OTP'),
      onStatus: (_) {},
      now: tester.binding.clock.now,
      random: _BoundaryRandom(true),
    );
    Object? failure;
    final run = runner.run().catchError((Object error) {
      failure = error;
    });
    while (accessibility.actions.isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    foreground = false;
    await tester.pump(const Duration(seconds: 30));
    expect(accessibility.actions, ['open-login']);
    expect(failure, isNull);

    foreground = true;
    while (accessibility.actions.length < 2) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    runner.cancel();
    await tester.pump(const Duration(seconds: 7));
    await run;
    expect(failure, isA<SignupCancelled>());
  });

  Future<(Object?, _RecordedAccessibility, int)> runSignup(
    WidgetTester tester, {
    double shiftY = 0,
    required List<Object> otpResults,
    void Function(_RecordedAccessibility)? setup,
  }) async {
    final accessibility = _RecordedAccessibility(profile, recording)
      ..shiftY = shiftY;
    setup?.call(accessibility);
    var otpRequests = 0;
    final runner = SignupCoordinateRunner(
      profile: profile,
      accessibility: accessibility,
      configuration: AppConfiguration(
        userAgent: 'test',
        comments: [],
        signupEmail: 'test@example.org',
        signupPassword: 'Example12!a',
        loginUsername: '',
        loginPassword: '',
        birthday: DateTime(2001, 2, 3),
      ),
      isActive: () => true,
      isTikTok: () async => true,
      getOtp: () async {
        final result = otpResults[otpRequests++];
        if (result is SignupOtpTimeout) {
          accessibility.resendReady = true; // TikTok's countdown has ended.
          throw result;
        }
        return result as String;
      },
      onStatus: (_) {},
      readBirthdayMenu: accessibility.readBirthdayMenu,
      now: tester.binding.clock.now,
    );
    Object? failure;
    var finished = false;
    final run = runner.run().then(
      (_) {
        finished = true;
      },
      onError: (Object error) {
        failure = error;
        finished = true;
      },
    );
    for (var i = 0; i < 900 && !finished; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(finished, isTrue, reason: 'actions=${accessibility.actions}');
    await run;
    return (failure, accessibility, otpRequests);
  }

  testWidgets('another device shifts every control off its recorded point', (
    tester,
  ) async {
    // 45 physical px ≈ 17 design units: more than the header Log in button.
    final (failure, accessibility, _) = await runSignup(
      tester,
      shiftY: 45,
      otpResults: ['123456'],
    );
    expect(failure, isNull, reason: '${accessibility.actions}');
    expect(accessibility.state, 'authenticated-home');
    expect(accessibility.liveNodeTaps, greaterThan(0));
    expect(accessibility.pastes, ['email', 'otp', 'password']);
    expect(accessibility.actions.where((a) => a == 'send-code'), hasLength(1));
  });

  testWidgets('a dropped Log in tap is retried before opening signup', (
    tester,
  ) async {
    var loginTaps = 0;
    final (failure, accessibility, _) = await runSignup(
      tester,
      otpResults: ['123456'],
      setup: (accessibility) => accessibility.afterTap = (name) {
        // TikTok ignores the first tap while the page still hydrates.
        if (name == 'open-login' && ++loginTaps == 1) {
          accessibility.state = 'home-ready';
        }
      },
    );
    expect(failure, isNull, reason: '${accessibility.actions}');
    expect(accessibility.state, 'authenticated-home');
    expect(accessibility.actions.where((a) => a == 'open-login'), hasLength(2));
    expect(
      accessibility.actions.where((a) => a == 'open-signup'),
      hasLength(1),
    );
  });

  testWidgets('Log in that never opens the dialog stops after three taps', (
    tester,
  ) async {
    final (failure, accessibility, _) = await runSignup(
      tester,
      otpResults: [],
      setup: (accessibility) => accessibility.afterTap = (name) {
        if (name == 'open-login') accessibility.state = 'home-ready';
      },
    );
    expect(
      failure,
      isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('Đang mở hộp đăng nhập'),
      ),
    );
    expect(accessibility.actions, ['open-login', 'open-login', 'open-login']);
    expect(accessibility.pastes, isEmpty);
  });

  testWidgets('OTP API timeout resends the code once and fetches it again', (
    tester,
  ) async {
    final (failure, accessibility, otpRequests) = await runSignup(
      tester,
      otpResults: [SignupOtpTimeout(), '123456'],
    );
    expect(failure, isNull);
    expect(otpRequests, 2);
    expect(
      accessibility.actions.where((a) => a == 'resend-code'),
      hasLength(1),
    );
    expect(
      accessibility.actions.indexOf('resend-code'),
      greaterThan(accessibility.actions.indexOf('send-code')),
    );
    expect(accessibility.state, 'authenticated-home');
  });

  testWidgets('a second OTP timeout stops without resending again', (
    tester,
  ) async {
    final (failure, accessibility, otpRequests) = await runSignup(
      tester,
      otpResults: [SignupOtpTimeout(), SignupOtpTimeout()],
    );
    expect(failure, isA<StateError>());
    expect('$failure', contains('Đã gửi lại mã 1 lần'));
    expect(otpRequests, 2);
    expect(
      accessibility.actions.where((a) => a == 'resend-code'),
      hasLength(1),
    );
    expect(accessibility.pastes, ['email']);
    expect(accessibility.actions, isNot(contains('submit-password')));
  });

  for (final scenario in ['on-load', 'mid-form', 'stays-open']) {
    testWidgets('cookie banner is accepted once: $scenario', (tester) async {
      final (failure, accessibility, _) = await runSignup(
        tester,
        otpResults: ['123456'],
        setup: (a) {
          a.cookieBanner = scenario != 'mid-form';
          a.cookieBannerStays = scenario == 'stays-open';
          if (scenario == 'mid-form') {
            a.onAction = (name) {
              if (name == 'use-email') a.cookieBanner = true;
            };
          }
        },
      );
      expect(failure, isNull, reason: '${accessibility.actions}');
      expect(accessibility.state, 'authenticated-home');
      expect(
        accessibility.actions.where((a) => a == 'accept-cookies'),
        hasLength(1),
      );
      final accepted = accessibility.actions.indexOf('accept-cookies');
      if (scenario == 'mid-form') {
        expect(accessibility.actions[accepted - 1], 'use-email');
      } else {
        expect(accepted, 0);
      }
      expect(accessibility.pastes, ['email', 'otp', 'password']);
    });
  }

  for (final after in ['submit-password', 'skip-username']) {
    testWidgets('the new-account privacy notice is dismissed after $after', (
      tester,
    ) async {
      final (failure, accessibility, _) = await runSignup(
        tester,
        otpResults: ['123456'],
        setup: (a) => a.onAction = (name) {
          if (name == after) a.privacyNotice = true;
        },
      );
      expect(failure, isNull, reason: '${accessibility.actions}');
      expect(accessibility.state, 'authenticated-home');
      expect(
        accessibility.actions.where((a) => a == 'dismiss-privacy'),
        hasLength(1),
      );
      expect(
        accessibility.actions[accessibility.actions.indexOf('dismiss-privacy') -
            1],
        after,
      );
    });
  }
}

class _BoundaryRandom implements Random {
  _BoundaryRandom(this.maximum);
  final bool maximum;
  @override
  int nextInt(int max) => maximum ? max - 1 : 0;
  @override
  bool nextBool() => maximum;
  @override
  double nextDouble() => maximum ? 0.999999 : 0;
}

class _RecordedAccessibility extends SignupAccessibility {
  _RecordedAccessibility(this.profile, this.recording);
  final SignupCoordinateProfile profile;
  final Map<String, dynamic> recording;
  String state = 'home-ready';
  bool rejectEmail = false;
  bool rejectSkip = false;
  bool failBirthdayReadback = false;
  bool freezeDropdown = false;
  bool hideNativeOptions = false;
  Rect? desktopBounds;
  bool otpNeedsSubmit = false;
  bool otpPasted = false;
  bool otpAutofocusKeyboard = false;
  bool keyboardHidden = false;
  int keyboardRenewals = 0;
  String? focusedId;
  final keyboardPolicies = <bool>[];
  static const phoneViewport = SignupViewport(
    Rect.fromLTRB(6, 289, 1073, 2423),
  );

  @override
  Future<String> diagnoseWeb() async =>
      'active=app win=2 app=1 n=40 foreign=0 web=GeckoView v1 c0 d12 942x1884';

  /// GeckoView exposes a combobox as an EditText named "`<field>`. Double-tap
  /// for more options", with its selected value in a child node.
  bool geckoComboboxes = false;
  int ignoredSwipes = 0;
  String? picker;
  int optionStart = 0;
  final selected = <String, String>{};
  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  List<String> get allOptions => switch (picker) {
    'Month' => months,
    'Day' => List.generate(
      DateTime(
        int.parse(selected['Year'] ?? '2001'),
        months.indexOf(selected['Month'] ?? 'January') + 2,
        0,
      ).day,
      (i) => '${i + 1}',
    ),
    _ => List.generate(127, (i) => '${2026 - i}'),
  };
  void Function()? afterOtpPaste;
  void Function(Map<String, dynamic>)? onHomeSnapshot;
  void Function(Map<String, dynamic>)? onSnapshot;
  void Function(String)? afterTap;
  void Function(String)? onAction;
  final actions = <String>[];
  final pastes = <String>[];

  /// Another device's fonts/WebView: every control sits this many physical
  /// pixels lower than on the calibration phone.
  double shiftY = 0;

  /// Taps that did not use a recorded point verbatim.
  int liveNodeTaps = 0;
  bool resendReady = false;
  bool resent = false;

  /// TikTok's bottom cookie banner; [cookieBannerStays] ignores the tap.
  bool cookieBanner = false;
  bool cookieBannerStays = false;
  static const _cookieButton = [560, 2340, 1060, 2400];

  /// TikTok's one-time privacy notice for a new account. It is modal, so
  /// only the notice is in the tree while it is open.
  bool privacyNotice = false;
  static const _privacyButton = [380, 2300, 700, 2350];

  List<dynamic> _shifted(List<dynamic> nodes, List<dynamic> web) => [
    for (final node in nodes)
      if (shiftY == 0 || '${node['bounds']}' == '$web')
        node
      else
        {
          ...node as Map,
          'bounds': [
            for (var i = 0; i < 4; i++)
              (node['bounds'][i] as num) + (i.isOdd ? shiftY : 0),
          ],
        },
  ];

  @override
  Future<SignupSnapshot> snapshot() async {
    final data =
        jsonDecode(jsonEncode(recording[state])) as Map<String, dynamic>;
    if (state == 'home-ready') onHomeSnapshot?.call(data);
    onSnapshot?.call(data);
    data['nodes'] = _shifted(data['nodes'] as List, data['webBounds'] as List);
    if (privacyNotice) {
      data['nodes'] = [
        for (final node in data['nodes'] as List)
          if ('${node['bounds']}' == '${data['webBounds']}') node,
        {
          'id': 'privacy.title',
          'text': 'Your privacy is our priority',
          'bounds': [380, 560, 1000, 610],
          'enabled': true,
        },
        {
          'id': 'privacy.ok',
          'text': 'Got it',
          'bounds': _privacyButton,
          'className': 'android.widget.Button',
          'enabled': true,
          'clickable': true,
        },
      ];
    }
    if (cookieBanner) {
      (data['nodes'] as List)
        ..add({
          'id': 'cookie.title',
          'text': 'Allow cookies from TikTok on this browser?',
          'bounds': [23, 2235, 1056, 2260],
          'enabled': true,
        })
        // Android WebView reports the banner button as disabled.
        ..add({
          'id': 'cookie.allow',
          'text': 'Allow all',
          'bounds': _cookieButton,
          'className': 'android.widget.Button',
          'enabled': false,
          'clickable': true,
        });
    }
    for (final node in data['nodes'] as List) {
      if (focusedId != null) node['focused'] = node['id'] == focusedId;
      if (node['text'] == 'Resend code') {
        node['enabled'] = resendReady && !resent;
      }
      if ('${node['className']}'.endsWith('Spinner')) {
        for (final field in selected.keys) {
          if ('${node['hint']}'.startsWith(field)) {
            node['text'] = failBirthdayReadback && field == 'Year'
                ? '1998'
                : selected[field];
          }
        }
      }
    }
    if (geckoComboboxes) {
      final values = <Map<String, dynamic>>[];
      for (final node in data['nodes'] as List) {
        if (!'${node['className']}'.endsWith('Spinner')) continue;
        final field = '${node['hint']}';
        values.add({
          'id': '${node['id']}.value',
          'text': node['text'],
          'bounds': node['bounds'],
          'className': 'android.view.View',
          'enabled': true,
        });
        node
          ..['className'] = 'android.widget.EditText'
          ..['text'] = '$field. Double-tap for more options'
          ..['hint'] = '';
      }
      (data['nodes'] as List).addAll(values);
    }
    if (picker != null && !hideNativeOptions) {
      final options = allOptions.skip(optionStart).take(6).toList();
      Map<String, dynamic> node(String text, List<int> bounds, String type) => {
        'id': 'picker.$text',
        'text': text,
        'bounds': bounds,
        'className': type,
        'enabled': true,
        'picker': true,
        'scrollable': type.endsWith('ListView'),
      };
      (data['nodes'] as List).add(
        node('', [350, 1280, 730, 1700], 'android.widget.ListView'),
      );
      for (var i = 0; i < options.length; i++) {
        (data['nodes'] as List).add(
          node(options[i], [
            350,
            1280 + i * 60,
            730,
            1340 + i * 60,
          ], 'android.widget.CheckedTextView'),
        );
      }
    }
    if (otpNeedsSubmit && otpPasted && state == 'otp-form') {
      (data['nodes'] as List).add({
        'id': 'otp.next',
        'text': 'Next',
        'enabled': true,
        'clickable': true,
        'bounds': [400, 1700, 700, 1800],
      });
    }
    if (desktopBounds case final frame?) {
      // Keep the header search box exposed while an account modal is open.
      (data['nodes'] as List).add({
        'id': 'header.search',
        'hint': 'Search',
        'editable': true,
        'enabled': true,
        'bounds': [300, 300, 650, 350],
      });
      List<double> scale(dynamic raw) {
        final r = SignupNode.rectFrom(raw);
        final a = phoneViewport.fromScreen(r.topLeft);
        final b = phoneViewport.fromScreen(r.bottomRight);
        return [
          frame.left + a.dx * frame.width / 400,
          frame.top + a.dy * frame.height / 800,
          frame.left + b.dx * frame.width / 400,
          frame.top + b.dy * frame.height / 800,
        ];
      }

      data['webBounds'] = scale(data['webBounds']);
      for (final n in data['nodes'] as List) {
        n['bounds'] = scale(n['bounds']);
      }
    }
    if (otpAutofocusKeyboard && state == 'otp-form' && !keyboardHidden) {
      // Real Gecko OTP autofocus opens the numeric IME immediately after
      // Send code, hiding the form before the runner can see Resend code.
      data['keyboardVisible'] = true;
      data['nodes'] = [];
    }
    return SignupSnapshot(data);
  }

  Future<SignupBirthdayMenu?> readBirthdayMenu(String field) async {
    if (!hideNativeOptions) return null;
    const viewport = SignupViewport(Rect.fromLTRB(6, 289, 1073, 2423));
    Rect toDesign(Rect r) => Rect.fromPoints(
      viewport.fromScreen(r.topLeft),
      viewport.fromScreen(r.bottomRight),
    );
    return SignupBirthdayMenu(
      field: field,
      expanded: picker == field,
      bounds: toDesign(const Rect.fromLTRB(350, 1280, 730, 1700)),
      scrollable: true,
      options: picker != field
          ? []
          : [
              for (
                var i = 0;
                i < allOptions.skip(optionStart).take(6).length;
                i++
              )
                SignupBirthdayOption(
                  allOptions[optionStart + i],
                  toDesign(
                    Rect.fromLTRB(350, 1280 + i * 60, 730, 1340 + i * 60),
                  ),
                ),
            ],
    );
  }

  @override
  Future<void> tapScreen(Rect bounds, Offset point) async {
    if (privacyNotice && SignupNode.rectFrom(_privacyButton).contains(point)) {
      actions.add('dismiss-privacy');
      privacyNotice = false;
      return;
    }
    if (!cookieBanner || !SignupNode.rectFrom(_cookieButton).contains(point)) {
      throw StateError('Screen tap at $point hit no cookie button.');
    }
    actions.add('accept-cookies');
    onAction?.call('accept-cookies');
    if (!cookieBannerStays) cookieBanner = false;
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    if (desktopBounds != null) {
      point = Offset(point.dx * 400 / 1920, point.dy * 800 / 955);
      viewport = phoneViewport;
    }
    if (otpNeedsSubmit &&
        otpPasted &&
        state == 'otp-form' &&
        const Rect.fromLTRB(
          400,
          1700,
          700,
          1800,
        ).contains(viewport.toScreen(point))) {
      actions.add('submit-otp');
      state = 'otp-context-paste-result';
      return;
    }
    if (picker != null) {
      final physical = viewport.toScreen(point);
      final index = ((physical.dy - 1280) / 60).floor() + optionStart;
      selected[picker!] = allOptions[index];
      final name = 'select-${picker!.toLowerCase()}';
      actions.add(name);
      onAction?.call(name);
      picker = null;
      return;
    }
    final name = _actionAt(viewport, point);
    if (name.startsWith('focus-')) {
      final at = viewport.toScreen(point) - Offset(0, shiftY);
      focusedId =
          (recording[state]['nodes'] as List).firstWhere(
                (n) =>
                    n['editable'] == true &&
                    SignupNode.rectFrom(n['bounds']).contains(at),
              )['id']
              as String;
    }
    actions.add(name);
    onAction?.call(name);
    if (name == 'resend-code') resent = true;
    if (name == 'skip-username' && rejectSkip) {
      throw StateError('Skip gesture failed');
    }
    if (['open-month', 'open-day', 'open-year'].contains(name)) {
      picker = name == 'open-month'
          ? 'Month'
          : name == 'open-day'
          ? 'Day'
          : 'Year';
      optionStart = 0;
    }
    state = switch (name) {
      'open-login' => 'login-modal',
      'open-signup' => 'signup-method',
      'signup-phone-email' => 'phone-form',
      'use-email' => 'email-birthday',
      'select-month' => 'month-selected',
      'select-day' => 'day-selected',
      'select-year' => 'birthday-verified',
      'send-code' => 'otp-form',
      'submit-password' => 'signup-result-settled',
      'skip-username' => 'authenticated-home',
      _ => state,
    };
    afterTap?.call(name);
  }

  /// The recorded step whose control was tapped. A tap away from the
  /// recorded point is resolved through the control under it.
  String _actionAt(SignupViewport viewport, Offset point) {
    final names = (profile.data['points'] as Map).keys.cast<String>();
    for (final name in names) {
      if (profile.point(name) == point) return name;
    }
    liveNodeTaps++;
    final at = viewport.toScreen(point) - Offset(0, shiftY);
    final hits =
        [
              for (final raw in recording[state]['nodes'] as List)
                SignupNode(Map<String, dynamic>.from(raw)),
            ]
            .where((n) => n.bounds.contains(at) && n.bounds != viewport.bounds)
            .toList()
          ..sort(
            (a, b) => (a.bounds.width * a.bounds.height).compareTo(
              b.bounds.width * b.bounds.height,
            ),
          );
    for (final node in hits) {
      if (node.label == 'Resend code') return 'resend-code';
      // Dropdown options are handled above, not by recorded points.
      for (final name in names.where((n) => !n.startsWith('select-'))) {
        if (node.bounds.contains(viewport.toScreen(profile.point(name)!))) {
          return name;
        }
      }
    }
    throw StateError('Tap at $at hit no recorded control in $state.');
  }

  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    actions.add('${picker!.toLowerCase()}-swipe');
    onAction?.call('${picker!.toLowerCase()}-swipe');
    if (ignoredSwipes > 0) {
      ignoredSwipes--;
      return;
    }
    if (freezeDropdown) return;
    optionStart = (optionStart + (from.dy > to.dy ? 4 : -4)).clamp(
      0,
      allOptions.length - 6,
    );
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pastes.add(field);
    onAction?.call('paste-$field');
    if (field == 'email' && rejectEmail) {
      return {'ok': false, 'reason': 'paste-rejected'};
    }
    state = switch (field) {
      'email' => 'email-live',
      'otp' => otpNeedsSubmit ? 'otp-form' : 'otp-context-paste-result',
      'password' => 'password-ready',
      _ => state,
    };
    if (field == 'otp') otpPasted = true;
    if (field == 'otp') afterOtpPaste?.call();
    return {'ok': true};
  }

  @override
  Future<void> dismissKeyboard() async {}
  @override
  Future<void> setKeyboardSuppressed(bool value) async {
    keyboardPolicies.add(value);
    keyboardHidden = value;
  }

  @override
  Future<void> renewKeyboardSuppression() async {
    keyboardRenewals++;
    keyboardHidden = true;
  }

  @override
  Future<void> cancelPaste() async {}
}
