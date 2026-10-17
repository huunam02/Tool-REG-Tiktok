import 'dart:ui';

import 'signup_accessibility.dart';

/// Accepts TikTok's cookie banner (shown for EU IPs) with an Accessibility
/// gesture. The JS auto-accept script is not injected in Accessibility mode.
class CookieConsentAccessibility {
  CookieConsentAccessibility({
    required this.accessibility,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SignupAccessibility accessibility;
  final DateTime Function() _now;

  static final label = RegExp(
    r'^(accept|allow) all( cookies)?$',
    caseSensitive: false,
  );

  /// An ignored tap is retried a few times, then left for the user.
  static const retryAfter = Duration(seconds: 5);
  static const maxTaps = 3;
  int _taps = 0;
  DateTime? _lastTap;

  /// The visible Allow all button of a cookie banner, if one is on screen.
  static SignupNode? button(SignupSnapshot snapshot) {
    final web = snapshot.viewport.bounds;
    if (!snapshot.ready ||
        web.isEmpty ||
        !snapshot.contains(RegExp('cookie', caseSensitive: false))) {
      return null;
    }
    final visible = snapshot.nodes
        // WebView reports TikTok's banner buttons as disabled although they
        // accept taps, so `enabled` is not required here.
        .where(
          (n) =>
              label.hasMatch(n.label) &&
              n.bounds.intersect(web).width >= 1 &&
              n.bounds.intersect(web).height >= 1,
        )
        .toList();
    // A label is often exposed twice (clickable View and its TextView).
    final clickable = visible.where((n) => n.clickable).toList();
    final pool = clickable.isEmpty ? visible : clickable;
    return pool.length == 1 ? pool.single : null;
  }

  /// Taps Allow all when the banner is shown. Returns whether it tapped.
  Future<bool> check() async {
    final last = _lastTap;
    if (last != null && _now().difference(last) < retryAfter) return false;
    final snapshot = await accessibility.snapshot();
    final node = button(snapshot);
    if (node == null) {
      _taps = 0; // A later banner (e.g. after cookies are cleared) is new.
      return false;
    }
    if (_taps >= maxTaps) return false;
    _taps++;
    _lastTap = _now();
    final Offset target = node.bounds
        .intersect(snapshot.viewport.bounds)
        .center;
    await accessibility.tapScreen(snapshot.viewport.bounds, target);
    return true;
  }
}
