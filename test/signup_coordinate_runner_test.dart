import 'dart:convert';
import 'dart:io';
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

  for (final scenario in [
    'loaded-page',
    'delayed-load',
    'reload-during-wait',
    'transient-webview',
    'moving-button',
    'late-button',
    'never-ready',
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
      if (scenario == 'never-ready') {
        expect(failure, isA<StateError>());
        expect(tappedAt, isNull);
        expect(accessibility.actions, isEmpty);
      } else if (scenario == 'cancel-during-startup') {
        expect(failure, isA<SignupCancelled>());
        expect(tappedAt, isNull);
        expect(accessibility.actions, isEmpty);
      } else {
        final minimumSeconds = switch (scenario) {
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
    'success',
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
  ]) {
    testWidgets('recorded Android Accessibility flow: $scenario', (
      tester,
    ) async {
      final accessibility = _RecordedAccessibility(profile, recording);
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
      var otpRequests = 0;
      var skipped = 0;
      accessibility.rejectSkip = scenario == 'skip-rejected';
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
      for (var i = 0; i < 160 && !finished; i++) {
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
        'leap-day',
        'last-day',
        'earliest-year',
        'html-dropdown',
      ].contains(scenario)) {
        expect(failure, isNull);
        expect(skipped, 1);
        expect(accessibility.state, 'authenticated-home');
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
      for (var i = 0; i < 100 && !finished; i++) {
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
  void Function(String)? afterTap;
  final actions = <String>[];
  final pastes = <String>[];
  @override
  Future<SignupSnapshot> snapshot() async {
    final data =
        jsonDecode(jsonEncode(recording[state])) as Map<String, dynamic>;
    if (state == 'home-ready') onHomeSnapshot?.call(data);
    for (final node in data['nodes'] as List) {
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
  Future<void> tap(SignupViewport viewport, Offset point) async {
    if (picker != null) {
      final physical = viewport.toScreen(point);
      final index = ((physical.dy - 1280) / 60).floor() + optionStart;
      selected[picker!] = allOptions[index];
      actions.add('select-${picker!.toLowerCase()}');
      picker = null;
      return;
    }
    final points = profile.data['points'] as Map;
    final name = points.keys.cast<String>().firstWhere(
      (name) => profile.point(name) == point,
    );
    actions.add(name);
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

  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    actions.add('${picker!.toLowerCase()}-swipe');
    if (freezeDropdown) return;
    optionStart = (optionStart + (from.dy > to.dy ? 4 : -4)).clamp(
      0,
      allOptions.length - 6,
    );
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pastes.add(field);
    if (field == 'email' && rejectEmail) {
      return {'ok': false, 'reason': 'paste-rejected'};
    }
    state = switch (field) {
      'email' => 'email-live',
      'otp' => 'otp-context-paste-result',
      'password' => 'password-ready',
      _ => state,
    };
    if (field == 'otp') afterOtpPaste?.call();
    return {'ok': true};
  }

  @override
  Future<void> dismissKeyboard() async {}
  @override
  Future<void> cancelPaste() async {}
}
