import 'package:flutter/material.dart';

import '../../core/controller/home_controller.dart';

/// Progress of an automatic run, shown above the tabs with a Stop button.
class AutoRunBanner extends StatelessWidget {
  const AutoRunBanner({super.key, required this.logic});

  final HomeController logic;

  @override
  Widget build(BuildContext context) {
    final progress =
        '${logic.autoRunFinished}/${logic.autoRunTotal} cấu hình · '
        '${logic.autoRunSucceeded} xong, ${logic.autoRunFailed} lỗi';
    return Material(
      color: const Color(0xFF123136),
      child: ListTile(
        key: const Key('autoRunBanner'),
        title: Text(
          logic.autoRunNextAt != null
              ? 'Chuyển sang cấu hình tiếp theo…'
              : switch (logic.autoRun) {
                  AutoRunMode.signup =>
                    'Đang tự đăng ký các cấu hình chưa đăng ký',
                  AutoRunMode.retryFailed =>
                    'Đang đăng ký lại các cấu hình lỗi',
                  _ => 'Đang nuôi toàn bộ tài khoản đã đăng ký',
                },
        ),
        subtitle: Text(
          [
            progress,
            if (logic.autoRunEmail.isNotEmpty) logic.autoRunEmail,
          ].join('\n'),
        ),
        trailing: TextButton(
          key: const Key('stopAutoRun'),
          onPressed: logic.stopAutoRun,
          child: const Text('Dừng'),
        ),
      ),
    );
  }
}
