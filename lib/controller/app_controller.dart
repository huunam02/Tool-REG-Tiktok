import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class ControllerNotice {
  const ControllerNotice(this.message,
      {this.duration = const Duration(seconds: 4),
      this.actionLabel,
      this.onAction});

  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
}

abstract class AppController extends GetxController {
  bool get active => !isClosed;
  ValueChanged<ControllerNotice>? onNotice;

  /// Publish a complete state change in a single GetBuilder update.
  void mutate(VoidCallback change) {
    if (!active) return;
    change();
    update();
  }

  void notify(String message,
      {Duration duration = const Duration(seconds: 4),
      String? actionLabel,
      VoidCallback? onAction}) {
    if (!active) return;
    onNotice?.call(ControllerNotice(message,
        duration: duration, actionLabel: actionLabel, onAction: onAction));
  }

  @override
  void onClose() {
    onNotice = null;
    super.onClose();
  }
}
