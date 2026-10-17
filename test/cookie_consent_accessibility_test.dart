import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/cookie_consent_accessibility.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

void main() {
  const allowBounds = [553, 2350, 1053, 2398];

  Map<String, dynamic> node(
    String text,
    List<int> bounds, {
    bool clickable = false,
  }) => {
    'id': text,
    'text': text,
    'bounds': bounds,
    'enabled': false, // Android WebView reports the banner as disabled.
    'clickable': clickable,
  };

  List<Map<String, dynamic>> banner() => [
    node('Allow cookies from TikTok on this browser?', [0, 2230, 1080, 2260]),
    node('Decline optional cookies', [33, 2350, 538, 2398], clickable: true),
    node('Allow all', allowBounds, clickable: true),
    node('Allow all', [800, 2360, 860, 2390]), // The button's TextView.
  ];

  test('taps the clickable Allow all of the cookie banner', () async {
    final accessibility = _FakeAccessibility()..nodes = banner();
    final consent = CookieConsentAccessibility(accessibility: accessibility);
    expect(await consent.check(), isTrue);
    expect(accessibility.taps, [SignupNode.rectFrom(allowBounds).center]);
  });

  test('ignores pages without a cookie banner', () async {
    final accessibility = _FakeAccessibility()
      ..nodes = [node('Allow all', allowBounds, clickable: true)];
    final consent = CookieConsentAccessibility(accessibility: accessibility);
    expect(await consent.check(), isFalse);
    expect(accessibility.taps, isEmpty);
  });

  test('retries an ignored tap after a pause, at most three times', () async {
    var now = DateTime(2026);
    final accessibility = _FakeAccessibility()..nodes = banner();
    final consent = CookieConsentAccessibility(
      accessibility: accessibility,
      now: () => now,
    );
    expect(await consent.check(), isTrue);
    expect(await consent.check(), isFalse); // Too soon.
    for (var i = 0; i < 4; i++) {
      now = now.add(CookieConsentAccessibility.retryAfter);
      await consent.check();
    }
    expect(accessibility.taps, hasLength(CookieConsentAccessibility.maxTaps));

    // Once the banner is gone, a later banner is handled again.
    accessibility.nodes = [];
    now = now.add(CookieConsentAccessibility.retryAfter);
    expect(await consent.check(), isFalse);
    accessibility.nodes = banner();
    now = now.add(CookieConsentAccessibility.retryAfter);
    expect(await consent.check(), isTrue);
  });

  test('does not tap a button outside the WebView', () async {
    final accessibility = _FakeAccessibility()
      ..nodes = [
        ...banner().where((n) => n['text'] != 'Allow all'),
        node('Allow all', [553, 2430, 1053, 2470], clickable: true),
      ];
    final consent = CookieConsentAccessibility(accessibility: accessibility);
    expect(await consent.check(), isFalse);
    expect(accessibility.taps, isEmpty);
  });

  test('matches the accepted button labels only', () {
    for (final label in [
      'Allow all',
      'allow all cookies',
      'Accept all',
      'Accept all cookies',
    ]) {
      expect(CookieConsentAccessibility.label.hasMatch(label), isTrue);
    }
    for (final label in ['Decline optional cookies', 'Allow', 'Allow all?']) {
      expect(CookieConsentAccessibility.label.hasMatch(label), isFalse);
    }
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
