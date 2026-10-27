import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/signup_birthday_menu.dart';

void main() {
  final geometry = SignupBirthdayGeometry.fromJson(
    (jsonDecode(
          File('assets/signup-coordinate-profile.json').readAsStringSync(),
        )
        as Map)['desktop']['birthdayMenu'],
  )!;
  final today = DateTime(2026, 10, 27);

  ({int swipes, double tapY})? plan(String field, int target) =>
      geometry.plan(field, geometry.index(field, target, today));

  void expectPlan(String field, int target, int swipes, double tapY) {
    final result = plan(field, target)!;
    expect(result.swipes, swipes);
    expect(result.tapY, closeTo(tapY, 1));
  }

  // Rows measured on the Galaxy S8 AVD on 2026-10-27 (design px).
  test('early rows are tapped without scrolling', () {
    expectPlan('Year', 2025, 0, 421.9);
    expectPlan('Month', 3, 0, 490.1);
    expectPlan('Day', 8, 0, 660.5);
  });

  test('year 1979 lands where 11 live swipes put it', () {
    // Live: 1979 at 561.2-595.3 after 11 swipes.
    expectPlan('Year', 1979, 11, 578.3);
  });

  test('November stops at the end of the month list', () {
    // Live: one swipe scrolled only 88.2 px; November at 657.4-691.5.
    expectPlan('Month', 11, 1, 674.5);
    // December is clipped to a sliver above the visible edge.
    expect(plan('Month', 12)!.tapY, closeTo(693.3, 0.5));
  });

  test('a day is placed only where every list length agrees', () {
    // Live: day 20 at 667.5 after three swipes, so 539.2 after four.
    expectPlan('Day', 20, 4, 556.3);
    // 28 to 31 days end the list at different points: read it instead.
    expect(plan('Day', 29), isNull);
  });

  test('targets before the first row have no plan', () {
    expect(plan('Year', 2026), isNull);
    expect(geometry.plan('Hour', 1), isNull);
  });
}
