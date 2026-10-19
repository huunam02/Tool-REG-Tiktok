import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/login_coordinate_profile.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const viewport = SignupViewport(Rect.fromLTWH(10, 20, 800, 1600));
  SignupNode node(Rect bounds) => SignupNode({
    'id': 'button',
    'enabled': true,
    'clickable': true,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
  });

  test(
    'first use persists before tapping and next load replays the same point',
    () async {
      final profile = await LoginCoordinateProfile.load();
      const action = 'fixture-persistence';
      final point = await profile.target(
        action,
        viewport,
        node(const Rect.fromLTWH(210, 420, 200, 80)),
      );
      expect(point, const Offset(150, 220));
      final restored = await LoginCoordinateProfile.load();
      // Same control expands asymmetrically; replay uses the original point.
      expect(
        await restored.target(
          action,
          viewport,
          node(const Rect.fromLTWH(190, 410, 300, 100)),
        ),
        point,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          LoginCoordinateProfile.storageKey,
        ),
        contains(action),
      );
    },
  );

  test(
    'moved control is tapped at its live bounds; saved point kept',
    () async {
      final profile = LoginCoordinateProfile({
        'submit-password': const Offset(150, 220),
      });
      const moved = Rect.fromLTWH(210, 800, 200, 80);
      final point = await profile.target(
        'submit-password',
        viewport,
        node(moved),
      );
      expect(viewport.toScreen(point), moved.center);
      expect(profile.points['submit-password'], [150, 220]);
    },
  );

  test('control outside the WebView frame is never tapped', () async {
    final profile = LoginCoordinateProfile({
      'submit-password': const Offset(150, 220),
    });
    await expectLater(
      profile.target(
        'submit-password',
        viewport,
        node(const Rect.fromLTWH(10, 1700, 200, 80)),
      ),
      throwsStateError,
    );
  });

  test('failed persistence prevents recording an action', () async {
    final profile = LoginCoordinateProfile(
      {},
      save: (_) async => throw StateError('disk failure'),
    );
    await expectLater(
      profile.target(
        'send-code',
        viewport,
        node(const Rect.fromLTWH(210, 420, 200, 80)),
      ),
      throwsStateError,
    );
    expect(profile.points, isEmpty);
  });
}
