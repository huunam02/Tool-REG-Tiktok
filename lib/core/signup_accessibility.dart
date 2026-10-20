import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';

const signupDesignSize = Size(400, 800);

class SignupViewport {
  const SignupViewport(this.bounds);
  final Rect bounds;
  bool get valid =>
      bounds.width > 0 &&
      bounds.height > 0 &&
      (bounds.width / bounds.height - 0.5).abs() < 0.003;
  Offset toScreen(Offset point) {
    if (!valid ||
        !point.dx.isFinite ||
        !point.dy.isFinite ||
        point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= 400 ||
        point.dy >= 800) {
      throw StateError('Khung WebView hoặc tọa độ không đúng chuẩn.');
    }
    return bounds.topLeft +
        Offset(point.dx * bounds.width / 400, point.dy * bounds.height / 800);
  }

  Offset fromScreen(Offset point) => Offset(
    (point.dx - bounds.left) * 400 / bounds.width,
    (point.dy - bounds.top) * 800 / bounds.height,
  );

  /// Design point that lands on [control] (physical pixels) on this device.
  /// The recorded point is kept while it is still on the visible control;
  /// otherwise the live node decides, because another phone's fonts, WebView
  /// or screen size can shift a control away from its recorded position.
  Offset tapPoint(Rect control, [Offset? recorded]) {
    final visible = control.intersect(bounds);
    if (!valid || visible.width < 1 || visible.height < 1) {
      throw StateError('Control nằm ngoài khung WebView.');
    }
    if (recorded != null) {
      try {
        if (visible.contains(toScreen(recorded))) return recorded;
      } on StateError {
        // Out of the design range: fall back to the live node below.
      }
    }
    final center = fromScreen(visible.center);
    toScreen(center); // Validate the design range before any gesture.
    return center;
  }

  /// The candidate under [recorded], else the nearest one within
  /// [maxDistance] design units. Distances are measured in the 400x800 design
  /// space, so the same limit holds on every screen size.
  SignupNode? nearest(
    Iterable<SignupNode> candidates,
    Offset recorded, {
    double maxDistance = 120,
  }) {
    final visible = [
      for (final node in candidates)
        if (!node.bounds.intersect(bounds).isEmpty) node,
    ];
    final at = toScreen(recorded);
    final hits = visible.where((n) => n.bounds.intersect(bounds).contains(at));
    if (hits.isNotEmpty) return hits.last;
    SignupNode? best;
    var bestDistance = maxDistance;
    for (final node in visible) {
      final distance =
          (fromScreen(node.bounds.intersect(bounds).center) - recorded)
              .distance;
      if (distance <= bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    return best;
  }

  static Rect fit(Size available) {
    final scale = math.min(available.width / 400, available.height / 800);
    final size = signupDesignSize * scale;
    return Rect.fromLTWH(
      (available.width - size.width) / 2,
      (available.height - size.height) / 2,
      size.width,
      size.height,
    );
  }
}

class SignupNode {
  SignupNode(Map<String, dynamic> data)
    : id = data['id'] as String,
      text = '${data['text'] ?? ''}',
      description = '${data['description'] ?? ''}',
      hint = '${data['hint'] ?? ''}',
      className = '${data['className'] ?? ''}',
      enabled = data['enabled'] == true,
      clickable = data['clickable'] == true,
      editable = data['editable'] == true,
      password = data['password'] == true,
      focused = data['focused'] == true,
      selected = data['selected'] == true,
      picker = data['picker'] == true,
      scrollable = data['scrollable'] == true,
      length = (data['length'] as num?)?.toInt() ?? 0,
      bounds = rectFrom(data['bounds']);
  final String id, text, description, hint, className;
  final bool enabled,
      clickable,
      editable,
      password,
      focused,
      selected,
      picker,
      scrollable;
  final int length;
  final Rect bounds;
  String get label =>
      [text, description, hint].where((s) => s.isNotEmpty).join(' ').trim();

  /// The control's accessible name. Older WebViews expose aria-label as the
  /// content description; newer ones (e.g. Android 16) expose it as text.
  String get name => (description.isNotEmpty ? description : text).trim();
  static Rect rectFrom(dynamic raw) {
    final values = (raw as List).cast<num>();
    return Rect.fromLTRB(
      values[0].toDouble(),
      values[1].toDouble(),
      values[2].toDouble(),
      values[3].toDouble(),
    );
  }
}

class SignupSnapshot {
  SignupSnapshot(Map<String, dynamic> data)
    : ready = data['ready'] == true,
      keyboardVisible = data['keyboardVisible'] == true,
      viewport = SignupViewport(
        data['webBounds'] == null
            ? Rect.zero
            : SignupNode.rectFrom(data['webBounds']),
      ),
      nodes = ((data['nodes'] as List?) ?? [])
          .map((e) => SignupNode(Map<String, dynamic>.from(e)))
          .toList();
  final bool ready;
  final bool keyboardVisible;
  final SignupViewport viewport;
  final List<SignupNode> nodes;
  List<SignupNode> get editors =>
      nodes.where((n) => n.editable && n.enabled).toList()..sort(
        (a, b) => a.bounds.top != b.bounds.top
            ? a.bounds.top.compareTo(b.bounds.top)
            : a.bounds.left.compareTo(b.bounds.left),
      );
  SignupNode? find(RegExp pattern, {bool enabled = true}) {
    for (final node in nodes.reversed) {
      if ((!enabled || node.enabled) && pattern.hasMatch(node.label)) {
        return node;
      }
    }
    return null;
  }

  bool contains(RegExp pattern) => find(pattern, enabled: false) != null;
}

class SignupAccessibility {
  SignupAccessibility({this.beforeSnapshot, this.beforeAction});
  final Future<void> Function()? beforeSnapshot, beforeAction;
  int _actionsInFlight = 0;
  bool get actionBusy => _actionsInFlight > 0;

  Future<T> _perform<T>(Future<T> Function() action) async {
    await beforeAction?.call();
    _actionsInFlight++;
    try {
      return await action();
    } finally {
      _actionsInFlight--;
    }
  }

  Future<void> cancelPaste() => FlutterAccessibilityService.signupCancelPaste();
  Future<SignupSnapshot> snapshot() async {
    await beforeSnapshot?.call();
    return SignupSnapshot(await FlutterAccessibilityService.signupSnapshot());
  }

  Future<void> tap(SignupViewport viewport, Offset point) => _perform(() async {
    final physical = viewport.toScreen(point);
    final completed = await FlutterAccessibilityService.dispatchGesture(
      GestureDescription(
        strokes: [
          GestureStroke(
            path: [GesturePoint(physical.dx, physical.dy)],
            startTime: 0,
            duration: 140,
          ),
        ],
      ),
    );
    if (!completed) throw StateError('Accessibility chưa hoàn tất cú chạm.');
  });

  /// Physical coordinates, for WebViews that are not in the 1:2 frame.
  Future<void> tapScreen(Rect bounds, Offset point) => _perform(() async {
    if (!bounds.isFinite ||
        bounds.isEmpty ||
        !point.dx.isFinite ||
        !point.dy.isFinite ||
        !bounds.contains(point)) {
      throw StateError('Điểm chạm nằm ngoài khung WebView.');
    }
    final completed = await FlutterAccessibilityService.dispatchGesture(
      GestureDescription(
        strokes: [
          GestureStroke(
            path: [GesturePoint(point.dx, point.dy)],
            startTime: 0,
            duration: 140,
          ),
        ],
      ),
    );
    if (!completed) throw StateError('Accessibility chưa hoàn tất cú chạm.');
  });

  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async =>
      swipeScreen(
        viewport.bounds,
        viewport.toScreen(from),
        viewport.toScreen(to),
      );

  /// Physical coordinates also support manual WebViews with any aspect ratio.
  Future<void> swipeScreen(Rect bounds, Offset from, Offset to) =>
      _perform(() async {
        if (!bounds.isFinite ||
            bounds.isEmpty ||
            !from.dx.isFinite ||
            !from.dy.isFinite ||
            !to.dx.isFinite ||
            !to.dy.isFinite ||
            !bounds.contains(from) ||
            !bounds.contains(to)) {
          throw StateError('Điểm kéo nằm ngoài khung WebView.');
        }
        final completed = await FlutterAccessibilityService.dispatchGesture(
          GestureDescription(
            strokes: [
              GestureStroke(
                path: [
                  GesturePoint(from.dx, from.dy),
                  GesturePoint(to.dx, to.dy),
                ],
                startTime: 0,
                duration: 450,
              ),
            ],
          ),
        );
        if (!completed) {
          throw StateError('Accessibility chưa hoàn tất thao tác cuộn.');
        }
      });

  Future<Map<String, dynamic>> paste(String text, String field) => _perform(
    () => FlutterAccessibilityService.signupPasteFocused(text, field),
  );
  Future<void> setKeyboardSuppressed(bool suppressed) => _perform(() async {
    if (!await FlutterAccessibilityService.signupSetKeyboardSuppressed(
      suppressed,
    )) {
      throw StateError('Không điều khiển được bàn phím để nhập bình luận.');
    }
  });

  Future<bool> submitComment() =>
      _perform(FlutterAccessibilityService.signupSubmitComment);

  Future<void> dismissKeyboard() => _perform(() async {
    if (!await FlutterAccessibilityService.signupDismissKeyboard()) {
      throw StateError('Không đóng được bàn phím.');
    }
  });
}
