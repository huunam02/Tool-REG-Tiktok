import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/app_controller.dart';

/// Each view owns its controller, including its initialization and disposal.
class ControllerScope<T extends AppController> extends StatelessWidget {
  const ControllerScope(
      {super.key, required this.controller, required this.builder});

  final T controller;
  final Widget Function(T controller) builder;

  @override
  Widget build(BuildContext context) => GetBuilder<T>(
        init: controller,
        global: false,
        autoRemove: false,
        // GetBuilder's local mode starts the controller but doesn't close it.
        dispose: (state) => state.controller?.onDelete(),
        builder: (logic) {
          logic.onNotice = (notice) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(notice.message),
              duration: notice.duration,
              action: notice.actionLabel == null || notice.onAction == null
                  ? null
                  : SnackBarAction(
                      label: notice.actionLabel!, onPressed: notice.onAction!),
            ));
          };
          return builder(logic);
        },
      );
}
