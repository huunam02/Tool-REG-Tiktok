import 'package:flutter/material.dart';

import 'widgets/settings_style.dart';

class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  /// Every feature, grouped as the app is used; steps are numbered across
  /// sections.
  static const _sections = [
    (
      'Chuẩn bị',
      [
        (
          'Bật quyền Trợ năng',
          'Android: vào Cài đặt và bật Quyền Trợ năng. App dùng Trợ năng để '
              'thao tác TikTok (nhập liệu, bấm nút, vuốt video). Nếu vừa cài '
              'lại app, hãy bật lại quyền này.',
        ),
        (
          'API OTP, CAPTCHA, từ khóa và bình luận',
          'API lấy OTP email, key giải CAPTCHA, danh sách từ khóa tìm kiếm và '
              'danh sách bình luận được quản lý qua Firebase Remote Config. '
              'Tab Cấu hình hiển thị từ khóa và bình luận đang dùng (chỉ xem).',
        ),
      ],
    ),
    (
      'Quản lý cấu hình',
      [
        (
          'Thêm cấu hình',
          'Tab Cấu hình → Quản lý cấu hình → Thêm. Bấm Import data để nhập '
              'Từ file (Excel .xlsx/.xls hoặc TXT) hoặc Dán từ clipboard. Mỗi '
              'dòng một cấu hình: host:port:user:pass|email|mật khẩu TikTok|'
              'mật khẩu email OTP, thêm |1 nếu tài khoản đã đăng ký (|0 nếu '
              'chưa). Nhiều dòng tạo nhiều cấu hình cùng lúc.',
        ),
        (
          'Thông tin của mỗi cấu hình',
          'Proxy HTTP/HTTPS; User-Agent (bấm Đổi User-Agent để lấy mới); '
              'Múi giờ WebView (Tra theo proxy, hoặc để trống để tự tra khi '
              'mở); Thiết bị (GPU) điện thoại được chọn ngẫu nhiên và giữ cố '
              'định, bấm Đổi để chọn máy khác; công tắc Đã đăng ký; ô Nuôi '
              'sau khi đăng ký.',
        ),
        (
          'Cấu hình nuôi',
          'Mỗi cấu hình có tỷ lệ Thả tim, Bình luận, Xem lâu (không vuốt '
              'ngay) và thời gian nuôi tối thiểu – tối đa. Mặc định: tim 30%, '
              'bình luận 20%, xem lâu 50%, nuôi 2–3 phút; bấm Mặc định để điền '
              'lại. Video được thả tim hoặc bình luận luôn xem hết; video còn '
              'lại xem lâu theo tỷ lệ, nếu không thì vuốt sau vài giây.',
        ),
        (
          'Menu ⋮ của cấu hình',
          'Kiểm tra IP: xóa phiên cũ, nạp proxy, User-Agent, múi giờ và GPU '
              'của cấu hình rồi mở WhatIsMyBrowser để xem trang web nhận được '
              'gì (không đánh dấu Đã dùng). Sửa: đổi thông tin. Xóa: bỏ cấu '
              'hình khỏi danh sách. Lọc danh sách theo Tất cả, Chưa dùng, '
              'Đã dùng.',
        ),
      ],
    ),
    (
      'Chạy tự động',
      [
        (
          'Tab Đăng ký',
          'Liệt kê cấu hình chưa đăng ký. Chạm một cấu hình để đặt Chạy '
              'trước, rồi bấm Chạy đăng ký lần lượt tài khoản. Với mỗi tài '
              'khoản, app xóa phiên cũ, nạp cấu hình và proxy, đăng ký, lấy '
              'OTP qua API và tự giải CAPTCHA. Nếu bật Nuôi sau khi đăng ký, '
              'tài khoản mới được nuôi theo cấu hình nuôi; sau đó giữ màn hình '
              '1–2 phút, đăng xuất, nghỉ 5–15 giây rồi sang cấu hình tiếp theo.',
        ),
        (
          'Tab Nuôi',
          'Liệt kê tài khoản đã đăng ký kèm thống kê: số lần nuôi, lần nuôi '
              'cuối, thời gian xem, video đã xem, thả tim, bình luận. Chạm một '
              'tài khoản để Chạy trước, rồi bấm Chạy nuôi lần lượt các tài '
              'khoản. Mỗi tài khoản được đăng nhập, nuôi ngẫu nhiên news feed '
              'hoặc tìm kiếm từ khóa theo cấu hình nuôi, giữ màn hình 1–2 phút '
              'rồi đăng xuất.',
        ),
        (
          'Tab Cấu hình lỗi',
          'Cấu hình đăng ký thất bại nằm ở đây kèm nhật ký lỗi (lý do và bước '
              'lỗi). Đăng ký thường bỏ qua các cấu hình này. Bấm Chạy đăng ký '
              'lần lượt lại tài khoản để thử lại (vẫn nuôi sau đăng ký theo '
              'cấu hình nuôi), hoặc Bỏ khỏi danh sách lỗi để đưa về tab Đăng ký.',
        ),
        (
          'Dừng và giới hạn thời gian',
          'Khi đang tự chạy, thanh trạng thái hiện cấu hình đang chạy và nút '
              'Dừng. Cấu hình nào quá giới hạn thời gian (15 phút, tự kéo dài '
              'theo thời gian nuôi tối đa) sẽ bị dừng để chạy cấu hình tiếp '
              'theo; nếu đang đăng ký thì cấu hình đó vào tab Cấu hình lỗi.',
        ),
      ],
    ),
    (
      'Màn TikTok',
      [
        (
          'Auto nuôi',
          'Nút Auto nuôi bật hoặc tắt việc tự xem video, thả tim và bình luận '
              'theo cấu hình nuôi. Chỉ bật được sau khi đăng nhập thành công. '
              'CAPTCHA xuất hiện khi nuôi sẽ được giải tự động qua API. Nút '
              'Tải lại mở lại trang.',
        ),
      ],
    ),
    (
      'Dữ liệu',
      [
        (
          'Xem trước và Xuất Excel',
          'Cài đặt → Xuất dữ liệu Excel. Xem trước hiển thị đúng bảng sẽ lưu; '
              'Xuất Excel lưu file .xlsx. Sheet Data có mỗi cấu hình một hàng: '
              'proxy, tài khoản, trạng thái, User-Agent, múi giờ, thiết bị GPU, '
              'cấu hình nuôi và thống kê nuôi. File này import lại được và '
              'khôi phục cả cấu hình nuôi lẫn thiết bị GPU.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    var number = 0;
    return Theme(
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
                      'Bật Trợ năng → thêm cấu hình trong Quản lý cấu hình → '
                      'chỉnh cấu hình nuôi → chạy ở tab Đăng ký hoặc Nuôi → '
                      'theo dõi tab Cấu hình lỗi → xuất Excel để lưu dữ liệu.',
                      style: TextStyle(
                        color: SettingsStyle.muted,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              for (final (title, steps) in _sections) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: SettingsStyle.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                for (final (stepTitle, description) in steps) ...[
                  _GuideStep(
                    number: '${++number}',
                    title: stepTitle,
                    description: description,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              const SettingsPanel(
                child: Text(
                  'Bảo mật: WebRTC luôn bị chặn nên trang web không đọc được IP '
                  'nội bộ của máy. Mỗi cấu hình có proxy, User-Agent, múi giờ và '
                  'thiết bị GPU riêng. Mỗi lần tự chạy hoặc Kiểm tra IP đều bắt '
                  'đầu bằng phiên WebView sạch (xóa cookie và dữ liệu trang).',
                  style: TextStyle(color: SettingsStyle.muted, height: 1.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
