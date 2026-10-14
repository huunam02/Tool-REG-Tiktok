import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/gesture_description.dart';

enum SendCodeTapFailure {
  notStarted,
  targetUnavailable,
  gestureIncomplete,
  gestureTimedOut,
}

/// Taps the live DOM target returned by the app's native WebView bridge.
/// DOM lookup adds a small random offset within the button before hit-testing.
/// The bridge verifies origin, attempt, focus, hit-testing and visible bounds;
/// dispatchGesture does not require an Accessibility node or ACTION_CLICK.
class SendCodeAccessibility {
  SendCodeAccessibility({Future<bool> Function(Offset)? tap})
    : _tap = tap ?? _dispatchTap;

  static Future<bool> _dispatchTap(Offset target) =>
      FlutterAccessibilityService.dispatchGesture(
        GestureDescription(
          strokes: [
            GestureStroke(
              path: [GesturePoint(target.dx, target.dy)],
              startTime: 0,
              duration: 140,
            ),
          ],
        ),
      );

  final Future<bool> Function(Offset) _tap;
  bool _started = false;
  bool _busy = false;
  int _generation = 0;
  SendCodeTapFailure? lastFailure;

  String? get failureMessage => failureMessageFor('Send code');

  String? failureMessageFor(String buttonLabel) => switch (lastFailure) {
    SendCodeTapFailure.targetUnavailable =>
      'Không lấy được tọa độ nút $buttonLabel đang hiển thị. Hãy kiểm tra biểu mẫu TikTok.',
    SendCodeTapFailure.gestureIncomplete =>
      'Android chưa hoàn tất cú chạm $buttonLabel. Hãy kiểm tra dịch vụ Trợ năng.',
    SendCodeTapFailure.gestureTimedOut =>
      'Android chưa trả kết quả cú chạm $buttonLabel. App đã dừng thao tác.',
    SendCodeTapFailure.notStarted => 'Chưa chuẩn bị dịch vụ chạm $buttonLabel.',
    null => null,
  };

  void start() {
    _started = true;
  }

  Future<bool> clickSendCode({required Future<Offset?> Function() getTarget}) =>
      tapButton(getTarget: getTarget, buttonLabel: 'Send code');

  Future<bool> tapButton({
    required Future<Offset?> Function() getTarget,
    required String buttonLabel,
  }) async {
    if (!_started) {
      lastFailure = SendCodeTapFailure.notStarted;
      return false;
    }
    if (_busy) return false;
    _busy = true;
    lastFailure = null;
    final generation = _generation;
    var dispatching = false;
    try {
      // Read after the signup delay. A System UI accessibility event cannot
      // discard a valid DOM target or block dispatching the gesture.
      final target = await getTarget();
      if (!_started || generation != _generation) return false;
      if (target == null ||
          !target.dx.isFinite ||
          !target.dy.isFinite ||
          target.dx < 0 ||
          target.dy < 0) {
        lastFailure = SendCodeTapFailure.targetUnavailable;
        debugPrint(
          '[$buttonLabel] Target unavailable; gesture not dispatched.',
        );
        return false;
      }
      debugPrint(
        '[$buttonLabel] Dispatching 140ms tap at '
        '(${target.dx.toStringAsFixed(1)}, ${target.dy.toStringAsFixed(1)}).',
      );
      dispatching = true;
      final completed = await _tap(target).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          lastFailure = SendCodeTapFailure.gestureTimedOut;
          return false;
        },
      );
      if (!completed) lastFailure ??= SendCodeTapFailure.gestureIncomplete;
      debugPrint(
        '[$buttonLabel] Tap result: ${lastFailure?.name ?? 'completed'}.',
      );
      return completed;
    } catch (error) {
      lastFailure = dispatching
          ? SendCodeTapFailure.gestureIncomplete
          : SendCodeTapFailure.targetUnavailable;
      debugPrint('[$buttonLabel] Tap failed (${error.runtimeType}).');
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _started = false;
    _generation++;
  }
}
