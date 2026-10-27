import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/signup_coordinate_runner.dart';
import 'package:test_tiktok/screen/widgets/signup_viewport.dart';

void main() {
  final profile = SignupCoordinateProfile(
    jsonDecode(File('assets/signup-coordinate-profile.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('a 1920x955 frame is the landscape desktop design', () {
    final viewport = SignupViewport(const Rect.fromLTWH(436, 382, 1920, 955));
    expect(viewport.valid, isTrue);
    expect(viewport.landscape, isTrue);
    // One design unit is one CSS px, which is one device pixel at 1 dppx.
    expect(viewport.toScreen(const Offset(960, 638)), const Offset(1396, 1020));
    // The phone frame keeps its 1:2 design.
    final phone = SignupViewport(const Rect.fromLTWH(0, 0, 1080, 2160));
    expect(phone.valid, isTrue);
    expect(phone.landscape, isFalse);
  });

  test('desktop points are used only in the desktop frame', () {
    final desktop = profile.points(desktop: true);
    expect(
      desktop.keys,
      containsAll(['open-login', 'send-code', 'skip-username']),
    );
    for (final name in desktop.keys) {
      final point = profile.point(name, desktop: true)!;
      expect(
        point.dx,
        inInclusiveRange(0, signupLandscapeDesignSize.width - 1),
      );
      expect(
        point.dy,
        inInclusiveRange(0, signupLandscapeDesignSize.height - 1),
      );
    }
    expect(profile.point('open-login'), const Offset(371.13, 19.31));
    expect(profile.point('open-login', desktop: true), const Offset(1848, 48));
    // A step without a desktop point is found by its label alone.
    expect(profile.point('otp-paste-menu', desktop: true), isNull);
  });

  test('the frame width keeps the page exactly 1920 CSS px wide', () {
    expect(desktopFramePixels(2333 / 4, 4), 1920); // S8 landscape
    // Narrower screens get a width Gecko scales by whole app units.
    final narrow = desktopFramePixels(1600 / 2.625, 2.625);
    expect(narrow, lessThanOrEqualTo(1600));
    expect(desktopCssWidth * 60 % narrow, 0);
  });
}
