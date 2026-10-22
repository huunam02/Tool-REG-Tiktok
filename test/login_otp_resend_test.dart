import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/login_accessibility_runner.dart';
import 'package:test_tiktok/core/login_coordinate_profile.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

class _OtpForm extends SignupAccessibility {
  DateTime clock = DateTime.utc(2026);
  late DateTime resendReadyAt = clock.add(const Duration(seconds: 25));
  bool rejected = false, authenticated = false, focused = false;
  bool rejectRetry = false, changeDraft = false, wrongPassword = false;
  String value = '';
  int resends = 0, clears = 0, pastes = 0;

  Map<String, dynamic> node(
    String id,
    String text,
    List<int> bounds, {
    bool editable = false,
    bool enabled = true,
  }) => {
    'id': id,
    'text': text,
    'bounds': bounds,
    'enabled': enabled,
    'clickable': true,
    'editable': editable,
    'focused': editable && focused,
    'length': editable ? value.length : 0,
    'hint': editable ? 'Enter 6-digit code' : '',
  };

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot({
    'ready': true,
    'webBounds': [0, 0, 400, 800],
    'nodes': authenticated
        ? [
            node('messages', 'Messages', [10, 10, 50, 30]),
            node('profile', 'Profile', [10, 40, 50, 60]),
          ]
        : [
            node('title', 'Verify email', [60, 200, 300, 240]),
            node('code', '', [80, 300, 280, 330], editable: true),
            node(
              'resend',
              clock.isBefore(resendReadyAt) ? 'Resend code 20s' : 'Resend code',
              [80, 350, 240, 380],
              enabled: !clock.isBefore(resendReadyAt),
            ),
            if (rejected)
              node(
                'error',
                'Verification code is expired or incorrect. Try again.',
                [80, 390, 300, 420],
              ),
            if (wrongPassword)
              node('password-error', 'Incorrect password', [80, 420, 300, 450]),
          ],
  });

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    if (point.dy >= 350 && point.dy < 380) {
      expect(clock.isBefore(resendReadyAt), isFalse);
      resends++;
      rejected = false;
      resendReadyAt = clock.add(const Duration(seconds: 25));
    } else {
      focused = true;
    }
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    expect(field, 'otp');
    pastes++;
    value = text;
    rejected = pastes == 1 || rejectRetry;
    if (changeDraft) value = '333333';
    if (!rejected) authenticated = true;
    return {'ok': true};
  }

  @override
  Future<bool> clearOtp(String expected) async {
    if (value != expected) return false;
    clears++;
    value = '';
    return true;
  }

  Future<void> delay(Duration d) async => clock = clock.add(d);
  @override
  Future<void> setKeyboardSuppressed(bool suppressed) async {}
  @override
  Future<void> dismissKeyboard() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configuration = AppConfiguration(
    userAgent: 'test',
    signupEmail: '',
    signupPassword: '',
    loginUsername: 'person@example.com',
    loginPassword: 'test-password',
    comments: [],
  );

  LoginAccessibilityRunner runner(_OtpForm form, {List<String>? rejected}) {
    var reads = 0;
    return LoginAccessibilityRunner(
      accessibility: form,
      configuration: configuration,
      profile: LoginCoordinateProfile({}),
      isActive: () => true,
      isPageReady: () => true,
      isTikTok: () async => true,
      getOtp: () async => ++reads == 1 ? '111111' : '222222',
      onOtpRejected: rejected?.add,
      onStatus: (_) {},
      now: () => form.clock,
      delay: form.delay,
      random: Random(4),
    );
  }

  test('rejected OTP is cleared, resent once, then login succeeds', () async {
    final form = _OtpForm();
    final rejected = <String>[];
    await runner(form, rejected: rejected).run();
    expect(form.authenticated, isTrue);
    expect([form.clears, form.resends, form.pastes], [1, 1, 2]);
    expect(rejected, ['111111']);
  });

  test('a second invalid OTP stops without another resend', () async {
    final form = _OtpForm()..rejectRetry = true;
    await expectLater(runner(form).run(), throwsA(isA<LoginOtpRejected>()));
    expect([form.clears, form.resends, form.pastes], [1, 1, 2]);
  });

  test('a changed OTP draft is preserved without resend', () async {
    final form = _OtpForm()..changeDraft = true;
    await expectLater(runner(form).run(), throwsStateError);
    expect(form.value, '333333');
    expect([form.clears, form.resends], [0, 0]);
  });

  test('a password error never triggers OTP resend', () async {
    final form = _OtpForm()..wrongPassword = true;
    await expectLater(runner(form).run(), throwsStateError);
    expect([form.clears, form.resends, form.pastes], [0, 0, 0]);
  });
}
