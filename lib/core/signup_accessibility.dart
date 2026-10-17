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
  Future<void> cancelPaste() => FlutterAccessibilityService.signupCancelPaste();
  Future<SignupSnapshot> snapshot() async =>
      SignupSnapshot(await FlutterAccessibilityService.signupSnapshot());
  Future<void> tap(SignupViewport viewport, Offset point) async {
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
  }

  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    final a = viewport.toScreen(from), b = viewport.toScreen(to);
    final completed = await FlutterAccessibilityService.dispatchGesture(
      GestureDescription(
        strokes: [
          GestureStroke(
            path: [GesturePoint(a.dx, a.dy), GesturePoint(b.dx, b.dy)],
            startTime: 0,
            duration: 450,
          ),
        ],
      ),
    );
    if (!completed) {
      throw StateError('Accessibility chưa hoàn tất thao tác cuộn.');
    }
  }

  Future<Map<String, dynamic>> paste(String text, String field) =>
      FlutterAccessibilityService.signupPasteFocused(text, field);
  Future<void> setKeyboardSuppressed(bool suppressed) async {
    if (!await FlutterAccessibilityService.signupSetKeyboardSuppressed(
      suppressed,
    )) {
      throw StateError('Không điều khiển được bàn phím để nhập bình luận.');
    }
  }

  Future<void> dismissKeyboard() async {
    if (!await FlutterAccessibilityService.signupDismissKeyboard()) {
      throw StateError('Không đóng được bàn phím.');
    }
  }
}
