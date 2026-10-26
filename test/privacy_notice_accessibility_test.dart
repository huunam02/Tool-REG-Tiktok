import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/privacy_notice_accessibility.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

void main() {
  const gotItBounds = [415, 2300, 1025, 2350];

  Map<String, dynamic> node(
    String text,
    List<int> bounds, {
    bool clickable = false,
  }) => {
    'id': text,
    'text': text,
    'bounds': bounds,
    'enabled': true,
    'clickable': clickable,
  };

  List<Map<String, dynamic>> notice() => [
    node('Your privacy is our priority', [415, 560, 1000, 610]),
    node('Privacy Policy', [810, 690, 945, 715], clickable: true),
    node('Got it', gotItBounds, clickable: true),
    node('Got it', [690, 2310, 750, 2340]), // The button's TextView.
  ];

  test('taps the clickable Got it of the privacy notice', () async {
    final accessibility = _FakeAccessibility()..nodes = notice();
    final privacy = PrivacyNoticeAccessibility(accessibility: accessibility);
    expect(await privacy.check(), isTrue);
    expect(accessibility.taps, [SignupNode.rectFrom(gotItBounds).center]);
  });

  test('ignores a Got it button outside the privacy notice', () async {
    final accessibility = _FakeAccessibility()
      ..nodes = [node('Got it', gotItBounds, clickable: true)];
    final privacy = PrivacyNoticeAccessibility(accessibility: accessibility);
    expect(await privacy.check(), isFalse);
    expect(accessibility.taps, isEmpty);
  });

  test('retries an ignored tap after a pause, at most three times', () async {
    var now = DateTime(2026);
    final accessibility = _FakeAccessibility()..nodes = notice();
    final privacy = PrivacyNoticeAccessibility(
      accessibility: accessibility,
      now: () => now,
    );
    expect(await privacy.check(), isTrue);
    expect(await privacy.check(), isFalse); // Too soon.
    for (var i = 0; i < 4; i++) {
      now = now.add(PrivacyNoticeAccessibility.retryAfter);
      await privacy.check();
    }
    expect(accessibility.taps, hasLength(PrivacyNoticeAccessibility.maxTaps));

    // Once the notice is gone, a later notice is handled again.
    accessibility.nodes = [];
    now = now.add(PrivacyNoticeAccessibility.retryAfter);
    expect(await privacy.check(), isFalse);
    accessibility.nodes = notice();
    now = now.add(PrivacyNoticeAccessibility.retryAfter);
    expect(await privacy.check(), isTrue);
  });

  test('does not tap a button outside the WebView', () async {
    final accessibility = _FakeAccessibility()
      ..nodes = [
        ...notice().where((n) => n['text'] != 'Got it'),
        node('Got it', [415, 2430, 1025, 2470], clickable: true),
      ];
    final privacy = PrivacyNoticeAccessibility(accessibility: accessibility);
    expect(await privacy.check(), isFalse);
    expect(accessibility.taps, isEmpty);
  });
}

class _FakeAccessibility extends SignupAccessibility {
  List<Map<String, dynamic>> nodes = [];
  final taps = <Offset>[];

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot({
    'ready': true,
    'webBounds': [0, 289, 1080, 2424],
    'nodes': nodes,
  });

  @override
  Future<void> tapScreen(Rect bounds, Offset point) async => taps.add(point);
}
