import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 126 User-Agent desktop: Chrome và Edge phiên bản 120–140,
/// trên Windows, macOS và Linux.
final List<String> desktopUserAgents = List<String>.unmodifiable([
  for (final platform in const [
    'Windows NT 10.0; Win64; x64',
    'Macintosh; Intel Mac OS X 10_15_7',
    'X11; Linux x86_64',
  ])
    for (var version = 120; version <= 140; version++) ...[
      'Mozilla/5.0 ($platform) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$version.0.0.0 Safari/537.36',
      'Mozilla/5.0 ($platform) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$version.0.0.0 Safari/537.36 Edg/$version.0.0.0',
    ],
]);

const _usedUserAgentsKey = 'desktop_user_agents_used';

/// Lưu lịch sử ngoài WebView để xóa cookie không làm mất các UA đã dùng.
/// Mỗi vòng dùng hết 126 chuỗi trước khi lặp, kể cả sau khi đóng/mở app.
Future<String> selectNextDesktopUserAgent() async {
  final preferences = await SharedPreferences.getInstance();
  var used = (preferences.getStringList(_usedUserAgentsKey) ?? [])
      .where(desktopUserAgents.contains)
      .toList();
  final last = used.isEmpty ? null : used.last;
  var available = desktopUserAgents.where((ua) => !used.contains(ua)).toList();
  if (available.isEmpty) {
    used = [];
    // Không lặp lại UA cuối cùng khi bắt đầu vòng mới.
    available = desktopUserAgents.where((ua) => ua != last).toList();
  }
  final selected = available[Random().nextInt(available.length)];
  if (!await preferences
      .setStringList(_usedUserAgentsKey, [...used, selected])) {
    throw StateError('Cannot persist User-Agent history');
  }
  if (kDebugMode) {
    debugPrint(
        '[User-Agent] New session (${used.length + 1}/${desktopUserAgents.length}): $selected');
  }
  return selected;
}
