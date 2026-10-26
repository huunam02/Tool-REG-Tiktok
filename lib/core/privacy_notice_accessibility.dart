import 'dart:ui';

import 'signup_accessibility.dart';

/// Closes TikTok's one-time privacy notice ("Your privacy is our priority"),
/// shown to an account right after signup or on its first logins. It is
/// modal, so the page behind it is missing from the tree until Got it is
/// tapped.
class PrivacyNoticeAccessibility {
  PrivacyNoticeAccessibility({
    required this.accessibility,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SignupAccessibility accessibility;
  final DateTime Function() _now;

  static final title = RegExp(
    r'^your privacy is our priority$',
    caseSensitive: false,
  );
  static final label = RegExp(r'^got it$', caseSensitive: false);

  /// An ignored tap is retried a few times, then left for the user.
  static const retryAfter = Duration(seconds: 5);
  static const maxTaps = 3;
  int _taps = 0;
  DateTime? _lastTap;

  /// The visible Got it button of the notice, if the notice is on screen.
  static SignupNode? button(SignupSnapshot snapshot) {
    final web = snapshot.viewport.bounds;
    if (!snapshot.ready || web.isEmpty || !snapshot.contains(title)) {
      return null;
    }
    final visible = snapshot.nodes
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

  /// Taps Got it when the notice is shown. Returns whether it tapped.
  Future<bool> check() async {
    final last = _lastTap;
    if (last != null && _now().difference(last) < retryAfter) return false;
    final snapshot = await accessibility.snapshot();
    final node = button(snapshot);
    if (node == null) {
      _taps = 0;
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
