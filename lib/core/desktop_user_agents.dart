import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webview_user_agent.dart';

/// Legacy Android templates, used only if native version discovery is unavailable.
/// Live Android sessions resolve these to the installed Chromium version.
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
  if (needsAndroidDesktopIdentity) {
    final used = preferences.getStringList(_usedUserAgentsKey) ?? [];
    final selected = await resolveWebViewUserAgent(stored ??
        (used.isNotEmpty ? used.last : androidDesktopUserAgents.first));
    if (!await preferences.setString(_directUserAgentKey, selected)) {
      throw StateError('Cannot persist direct User-Agent');
    }
    return selected;
  }
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
/// iOS uses every template before repeating. Android uses the installed engine.
Future<String> selectNextDesktopUserAgent() async {
  final preferences = await SharedPreferences.getInstance();
  if (needsAndroidDesktopIdentity) {
    final selected =
        await resolveWebViewUserAgent(androidDesktopUserAgents.first);
    if (!await preferences.setStringList(_usedUserAgentsKey, [selected])) {
      throw StateError('Cannot persist User-Agent history');
    }
    return selected;
  }
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
