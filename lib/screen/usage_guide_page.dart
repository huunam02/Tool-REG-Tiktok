import 'package:flutter/material.dart';

import 'widgets/settings_style.dart';

class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  static const _steps = [
    (
      '1',
      'Cấu hình OTP Email API',
      'Mở Cài đặt → Cấu hình OTP Email API, kiểm tra URL và token rồi lưu.'
    ),
    (
      '2',
      'Chuẩn bị proxy',
      'Vào Quản lý Proxy, tạo proxy cùng User-Agent và chọn proxy cần sử dụng.'
    ),
    (
      '3',
      'Nhập thông tin tài khoản',
      'Điền email, mật khẩu TikTok và mật khẩu hộp thư trong tab Đăng ký hoặc Đăng nhập.'
    ),
    (
      '4',
      'Chạy tác vụ',
      'Bấm nút chạy ở cuối màn hình. App sẽ mở TikTok bằng proxy và User-Agent đã chọn.'
    ),
  ];

  @override
  Widget build(BuildContext context) => Theme(
        data: SettingsStyle.theme(context),
        child: Scaffold(
          appBar: AppBar(title: const Text('Hướng dẫn sử dụng')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                const SettingsPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bắt đầu nhanh',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Thực hiện lần lượt các bước bên dưới để chạy đăng ký, đăng nhập hoặc tự động xem TikTok.',
                        style: TextStyle(
                          color: SettingsStyle.muted,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final step in _steps) ...[
                  _GuideStep(
                    number: step.$1,
                    title: step.$2,
                    description: step.$3,
                  ),
                  const SizedBox(height: 12),
                ],
                const SettingsPanel(
                  child: Text(
                    'Cookie và phiên TikTok được giữ khi mở lại app. App chỉ xóa phiên khi bạn áp dụng một proxy khác.',
                    style: TextStyle(
                      color: SettingsStyle.muted,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => SettingsPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SettingsStyle.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                number,
                style: const TextStyle(
                  color: SettingsStyle.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      color: SettingsStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
