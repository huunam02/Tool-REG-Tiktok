import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/signup_birthday_menu.dart';

void main() {
  Map<String, dynamic> data() => {
    'field': 'Year',
    'width': 1000,
    'height': 2000,
    'expanded': true,
    'bounds': [550, 900, 660, 1200],
    'scrollable': true,
    'options': [
      {
        'text': '2001',
        'bounds': [550, 930, 650, 960],
      },
    ],
  };
  test('maps HTML CSS geometry to the same design space as Accessibility', () {
    final menu = SignupBirthdayMenu.fromResult(jsonEncode(data()))!;
    expect(menu.bounds, const Rect.fromLTRB(220, 360, 264, 480));
    expect(menu.options.single.bounds.center, const Offset(240, 378));
    expect(menu.options.single.text, '2001');
    expect(menu.expanded, isTrue);
  });
  test('rejects geometry from a different viewport and missing comboboxes', () {
    expect(SignupBirthdayMenu.fromResult(null), isNull);
    expect(
      () => SignupBirthdayMenu.fromResult(data()..['field'] = 'Search'),
      throwsStateError,
    );
    expect(
      () => SignupBirthdayMenu.fromResult(data()..['height'] = 800),
      throwsStateError,
    );
    expect(
      () => buildReadSignupBirthdayMenuScript('Search'),
      throwsArgumentError,
    );
  });
}
