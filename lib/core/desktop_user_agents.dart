import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android: Chrome desktop 120–140 theo mẫu Linux x86_64.
final List<String> androidDesktopUserAgents = List<String>.unmodifiable([
  for (var version = 120; version <= 140; version++)
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/$version.0.0.0 Safari/537.36',
]);

/// Các nền tảng khác: 84 User-Agent Chrome/Edge desktop 120–140.
final List<String> _otherDesktopUserAgents = List<String>.unmodifiable([
  for (final platform in const [
    'Windows NT 10.0; Win64; x64',
    'Macintosh; Intel Mac OS X 10_15_7',
  ])
    for (var version = 120; version <= 140; version++) ...[
      'Mozilla/5.0 ($platform) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$version.0.0.0 Safari/537.36',
      'Mozilla/5.0 ($platform) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$version.0.0.0 Safari/537.36 Edg/$version.0.0.0',
    ],
]);

List<String> get desktopUserAgents =>
    defaultTargetPlatform == TargetPlatform.android
        ? androidDesktopUserAgents
        : _otherDesktopUserAgents;

const _usedUserAgentsKey = 'desktop_user_agents_used';
const _directUserAgentKey = 'desktop_user_agent_direct';

/// Reuse the same browser identity while keeping the direct connection session.
Future<String> loadDirectDesktopUserAgent() async {
  final preferences = await SharedPreferences.getInstance();
  final stored = preferences.getString(_directUserAgentKey);
  if (stored != null && desktopUserAgents.contains(stored)) return stored;
  final used = preferences.getStringList(_usedUserAgentsKey) ?? [];
  final selected = used.isNotEmpty && desktopUserAgents.contains(used.last)
      ? used.last
      : await selectNextDesktopUserAgent();
  if (!await preferences.setString(_directUserAgentKey, selected)) {
    throw StateError('Cannot persist direct User-Agent');
  }
  return selected;
}

/// Lưu lịch sử ngoài WebView để xóa cookie không làm mất các UA đã dùng.
/// Mỗi vòng dùng hết bộ UA của nền tảng trước khi lặp, kể cả sau khi đóng/mở app.
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
