import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/screen/usage_guide_page.dart';

void main() {
  testWidgets('the guide covers every feature and fits a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: UsageGuidePage()));
    final titles = [
      'Bật quyền Trợ năng',
      'API OTP, CAPTCHA, từ khóa và bình luận',
      'Thêm cấu hình',
      'Thông tin của mỗi cấu hình',
      'Cấu hình nuôi',
      'Menu ⋮ của cấu hình',
      'Tab Đăng ký',
      'Tab Nuôi',
      'Tab Cấu hình lỗi',
      'Dừng và giới hạn thời gian',
      'Auto nuôi',
      'Xem trước và Xuất Excel',
    ];
    for (var i = 0; i < titles.length; i++) {
      await tester.scrollUntilVisible(find.text(titles[i]), 200);
      expect(find.text(titles[i]), findsOneWidget);
      expect(find.text('${i + 1}'), findsWidgets);
    }
    await tester.scrollUntilVisible(
      find.textContaining('WebRTC luôn bị chặn'),
      200,
    );
    expect(tester.takeException(), isNull);
  });
}
