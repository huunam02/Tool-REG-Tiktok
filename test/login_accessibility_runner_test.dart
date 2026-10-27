import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/login_accessibility_runner.dart';
import 'package:test_tiktok/core/login_coordinate_profile.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

/// Bounds and roles recorded through ADB on the desktop login form.
class _DesktopPasswordForm extends SignupAccessibility {
  DateTime clock = DateTime.utc(2026);
  String? focus;
  final values = <String, String>{};
  final taps = <String>[];
  bool authenticated = false;
  bool continueEnabled = true;

  Map<String, dynamic> node(
    String id,
    String label,
    List<int> bounds, {
    String role = 'android.view.View',
    String? field,
    bool enabled = true,
  }) => {
    'id': id,
    'text': field == null ? label : '',
    'hint': field == null ? '' : label,
    'className': field == null ? role : 'android.widget.EditText',
    'bounds': bounds,
    'clickable': true,
    'enabled': enabled,
    'editable': field != null,
    'password': field == 'password',
    'focused': field != null && focus == field,
    'length': values[field]?.length ?? 0,
  };

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot({
    'ready': true,
    'webBounds': [0, 1186, 1440, 1902],
    'nodes': authenticated
        ? [
            node('messages', 'Messages', [15, 1300, 100, 1330]),
            node('profile', 'Profile', [15, 1340, 100, 1370]),
            node('search', 'Trending topic', [
              72,
              1242,
              248,
              1257,
            ], field: 'search'),
          ]
        : [
            // Signed-in sidebar labels can remain behind an account dialog.
            node('messages', 'Messages', [15, 1300, 100, 1330]),
            node('profile', 'Profile', [15, 1340, 100, 1370]),
            node('dialog', 'Log in', [
              560,
              1333,
              881,
              1755,
            ], role: 'android.app.Dialog'),
            node('dialog.heading', 'Log in', [600, 1381, 840, 1410]),
            node('dialog.email', 'Username or email', [
              590,
              1490,
              851,
              1526,
            ], field: 'email'),
            node('dialog.password', 'Password', [
              590,
              1535,
              851,
              1571,
            ], field: 'password'),
            node(
              'dialog.continue',
              'Continue',
              [590, 1623, 851, 1657],
              role: 'android.widget.Button',
              enabled: continueEnabled,
            ),
            // A background login below the editor must not submit the form.
            node('sidebar.login', 'Log in', [
              15,
              1660,
              165,
              1690,
            ], role: 'android.widget.Button'),
          ],
  });

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {
    final screen = viewport.toScreen(point);
    final s = await snapshot();
    final target = s.nodes.lastWhere(
      (n) => n.className != 'android.app.Dialog' && n.bounds.contains(screen),
    );
    taps.add(target.id);
    if (target.id == 'dialog.continue') {
      authenticated = true;
    } else if (target.editable) {
      focus = target.password ? 'password' : 'email';
    }
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    values[field] = text;
    return {'ok': true};
  }

  @override
  Future<void> setKeyboardSuppressed(bool suppressed) async {}
  @override
  Future<void> renewKeyboardSuppression() async {}
  @override
  Future<void> releaseKeyboardSuppression() async {}
  @override
  Future<void> dismissKeyboard() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the email switch matches the desktop and phone labels', () {
    for (final label in [
      'Use email or username',
      'Use email',
      'Username or email',
      'Email / Username',
    ]) {
      expect(LoginAccessibilityRunner.useEmailLabel.hasMatch(label), isTrue);
    }
    for (final label in ['Use phone or email', 'Use password', 'Email']) {
      expect(LoginAccessibilityRunner.useEmailLabel.hasMatch(label), isFalse);
    }
  });

  for (final enabled in [true, false]) {
    test(
      'desktop password submit ignores clickable title (enabled=$enabled)',
      () async {
        final form = _DesktopPasswordForm()..continueEnabled = enabled;
        final runner = LoginAccessibilityRunner(
          accessibility: form,
          configuration: AppConfiguration(
            userAgent: 'test',
            signupEmail: '',
            signupPassword: '',
            loginUsername: 'person@example.com',
            loginPassword: 'test-password',
            comments: [],
          ),
          profile: LoginCoordinateProfile({
            'desktop/submit-password': const Offset(960, 279.4),
          }),
          isActive: () => true,
          isPageReady: () => true,
          isTikTok: () async => true,
          getOtp: () async => throw StateError('Unexpected OTP request'),
          onStatus: (_) {},
          now: () => form.clock,
          delay: (duration) async => form.clock = form.clock.add(duration),
          random: Random(4),
        );
        if (enabled) {
          await runner.run();
          expect(form.authenticated, isTrue);
          expect(
            form.taps.where((id) => id == 'dialog.continue'),
            hasLength(1),
          );
        } else {
          await expectLater(runner.run(), throwsStateError);
          expect(form.authenticated, isFalse);
        }
        expect(form.taps, isNot(contains('dialog.heading')));
        expect(form.taps, isNot(contains('sidebar.login')));
      },
    );
  }
}
