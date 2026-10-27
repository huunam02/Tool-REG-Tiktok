import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';

const signupDesignSize = Size(400, 800);

/// Signup runs in a desktop-shaped window: maximized Firefox on a 1920 x 1080
/// screen shows pages at 1920 x 955 CSS px, so one design unit is one CSS
/// px. Each layout has its own recorded points; live Accessibility bounds
/// determine where gestures land after scaling and centering the frame.
const signupLandscapeDesignSize = Size(1920, 955);

/// The design space a frame or page of this size uses, or null.
Size? signupDesignFor(double width, double height) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }
  final aspect = width / height;
  if ((aspect - 0.5).abs() < 0.003) return signupDesignSize;
  final landscape =
      signupLandscapeDesignSize.width / signupLandscapeDesignSize.height;
  // The native frame height may differ from the box by a few pixels.
  return (aspect - landscape).abs() < 0.02 ? signupLandscapeDesignSize : null;
}

class SignupViewport {
  const SignupViewport(this.bounds);
  final Rect bounds;
  Size? get design => signupDesignFor(bounds.width, bounds.height);
  bool get valid => design != null;
  bool get landscape => design == signupLandscapeDesignSize;
  Offset toScreen(Offset point) {
    final size = design;
    if (size == null ||
        !point.dx.isFinite ||
        !point.dy.isFinite ||
        point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= size.width ||
        point.dy >= size.height) {
      throw StateError('Khung WebView hoặc tọa độ không đúng chuẩn.');
    }
    return bounds.topLeft +
        Offset(
          point.dx * bounds.width / size.width,
          point.dy * bounds.height / size.height,
        );
  }

  Offset fromScreen(Offset point) {
    final size = design ?? signupDesignSize;
    return Offset(
      (point.dx - bounds.left) * size.width / bounds.width,
      (point.dy - bounds.top) * size.height / bounds.height,
    );
  }

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

  static Rect fit(Size available, [Size design = signupDesignSize]) {
    final scale = math.min(
      available.width / design.width,
      available.height / design.height,
    );
    final size = design * scale;
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
      inputType = (data['inputType'] as num?)?.toInt() ?? 0,
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
  final int length, inputType;
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
      serviceConnected = data['serviceConnected'] != false,
      keyboardVisible = data['keyboardVisible'] == true,
      viewport = SignupViewport(
        data['webBounds'] == null
            ? Rect.zero
            : SignupNode.rectFrom(data['webBounds']),
      ),
      nodes = ((data['nodes'] as List?) ?? [])
          .map((e) => SignupNode(Map<String, dynamic>.from(e)))
          .toList(),
      hiddenNodes = ((data['hidden'] as List?) ?? [])
          .map((e) => SignupNode(Map<String, dynamic>.from(e)))
          .toList();
  final bool ready;

  /// False when Android lists the service as enabled but has not bound it.
  final bool serviceConnected;
  final bool keyboardVisible;
  final SignupViewport viewport;
  final List<SignupNode> nodes;

  /// Metadata for faded playback controls; never used as gesture targets.
  final List<SignupNode> hiddenNodes;
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

  /// A slider drag as in tiktok_rotate_captcha_guide.md (press, move, hold,
  /// release) that ends exactly on [to]. A fast fling is taken by GeckoView
  /// as a pan and the slider stops part-way. TikTok also scores the track:
  /// a straight constant-speed line is rejected even on the right angle, so
  /// the hand speeds up and slows down, wobbles, and settles from a small
  /// overshoot.
  Future<void> dragScreen(
    Rect bounds,
    Offset from,
    Offset to, {
    math.Random? random,
  }) => _perform(() async {
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
    final r = random ?? math.Random();
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    GesturePoint at(Offset p) => GesturePoint(
      p.dx.clamp(bounds.left, bounds.right - 1),
      p.dy.clamp(bounds.top, bounds.bottom - 1),
    );
    final dx = to.dx - from.dx;
    final overshoot = dx.sign * between(3, 9);
    final steps = 18 + r.nextInt(8);
    final stepMs = between(700, 1200) / steps;
    final track = <Offset>[from];
    var wobble = 0.0;
    for (var i = 1; i <= steps; i++) {
      // Equal time slices over an ease-in-out curve: slow, fast, slow.
      final t = i / steps;
      final eased = t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
      wobble = (wobble + between(-1.2, 1.2)).clamp(-3.0, 3.0);
      track.add(Offset(from.dx + (dx + overshoot) * eased, from.dy + wobble));
    }
    track
      ..add(Offset.lerp(track.last, to, .6)!)
      ..add(to);
    final completed =
        await FlutterAccessibilityService.dispatchContinuousGesture([
          // Below Gecko's long-press delay, so no context menu or drag.
          GestureStroke(path: [at(from)], duration: between(80, 180).round()),
          for (var i = 1; i < track.length; i++)
            GestureStroke(
              path: [at(track[i - 1]), at(track[i])],
              duration: i > steps
                  ? between(60, 120).round()
                  : math.max(8, (stepMs * between(.8, 1.2)).round()),
            ),
          GestureStroke(path: [at(to)], duration: between(150, 350).round()),
        ]);
    if (!completed) {
      throw StateError('Accessibility chưa hoàn tất thao tác kéo.');
    }
  });

  Future<Map<String, dynamic>> paste(String text, String field) => _perform(
    () => FlutterAccessibilityService.signupPasteFocused(text, field),
  );
  Future<void> setKeyboardSuppressed(bool suppressed) => _perform(() async {
    if (!await FlutterAccessibilityService.signupSetKeyboardSuppressed(
      suppressed,
    )) {
      throw StateError('Không điều khiển được bàn phím để nhập dữ liệu.');
    }
  });

  /// Refresh an already-owned keyboard lease without running CAPTCHA hooks
  /// concurrently with the gesture or paste that currently owns them.
  Future<void> renewKeyboardSuppression() async {
    if (!await FlutterAccessibilityService.signupSetKeyboardSuppressed(true)) {
      throw StateError('Không giữ được bàn phím ẩn khi chờ OTP.');
    }
  }

  /// Ends a held lease, also without CAPTCHA hooks (cleanup paths).
  Future<void> releaseKeyboardSuppression() async {
    await FlutterAccessibilityService.signupSetKeyboardSuppressed(false);
  }

  /// Why no WebView is readable (windows, WebView/Gecko nodes); diagnostics
  /// only, never used to pick a target.
  Future<String> diagnoseWeb() =>
      FlutterAccessibilityService.signupDiagnoseWeb();

  Future<bool> submitComment() =>
      _perform(FlutterAccessibilityService.signupSubmitComment);

  Future<Map<String, dynamic>> revealCommentPost(SignupNode editor) => _perform(
    () => FlutterAccessibilityService.signupRevealCommentPost(editor.id, [
      editor.bounds.left,
      editor.bounds.top,
      editor.bounds.right,
      editor.bounds.bottom,
    ]),
  );

  Future<bool> clearOtp(String expected) =>
      _perform(() => FlutterAccessibilityService.signupClearOtp(expected));

  Future<void> dismissKeyboard() => _perform(() async {
    if (!await FlutterAccessibilityService.signupDismissKeyboard()) {
      throw StateError('Không đóng được bàn phím.');
    }
  });
}
