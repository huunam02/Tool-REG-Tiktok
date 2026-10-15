import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webview_user_agent.dart';
import 'chrome_user_agent.dart';

/// Android phones (including Pixel 9): Chrome's Desktop site uses Linux x64.
final List<String> androidDesktopUserAgents = List<String>.unmodifiable([
  for (final major in recentChromeFullVersions.keys)
    chromeDesktopUserAgent('X11; Linux x86_64', major: major),
]);

/// iOS keeps macOS desktop identities. No generated Windows templates.
final List<String> iosDesktopUserAgents = List<String>.unmodifiable([
  for (final major in recentChromeFullVersions.keys)
    chromeDesktopUserAgent(macChromePlatform, major: major),
]);

List<String> get desktopUserAgents =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? iosDesktopUserAgents
    : androidDesktopUserAgents;

const _usedUserAgentsKey = 'desktop_user_agents_used';
const _directUserAgentKey = 'desktop_user_agent_direct';

/// Reuse the same browser identity while keeping the direct connection session.
Future<String> loadDirectDesktopUserAgent() async {
  final preferences = await SharedPreferences.getInstance();
  final previous = preferences.getString(_directUserAgentKey);
  final stored = previous == null
      ? null
      : normalizeDesktopUserAgentForPlatform(previous);
  if (needsAndroidDesktopIdentity) {
    final used = preferences.getStringList(_usedUserAgentsKey) ?? [];
    final selected = stored != null && stored.trim().isNotEmpty
        ? stored
        : used.isNotEmpty
        ? normalizeDesktopUserAgentForPlatform(used.last)
        : await selectNextDesktopUserAgent();
    final desktopAgent = androidChromeDesktopUserAgent(selected);
    if (!await preferences.setString(_directUserAgentKey, desktopAgent)) {
      throw StateError('Cannot persist direct User-Agent');
    }
    return desktopAgent;
  }
  if (stored != null && desktopUserAgents.contains(stored)) {
    if (stored != previous &&
        !await preferences.setString(_directUserAgentKey, stored)) {
      throw StateError('Cannot persist direct User-Agent');
    }
    return stored;
  }
  final used = (preferences.getStringList(_usedUserAgentsKey) ?? [])
      .map(normalizeDesktopUserAgentForPlatform).toList();
  final selected = used.isNotEmpty && desktopUserAgents.contains(used.last)
      ? used.last
      : await selectNextDesktopUserAgent();
  if (!await preferences.setString(_directUserAgentKey, selected)) {
    throw StateError('Cannot persist direct User-Agent');
  }
  return selected;
}

/// Lưu lịch sử ngoài WebView để xóa cookie không làm mất các UA đã dùng.
/// Randomize Chrome versions without repeating until the platform pool is used.
Future<String> selectNextDesktopUserAgent() async {
  final preferences = await SharedPreferences.getInstance();
  final candidates = desktopUserAgents;
  final history = preferences.getStringList(_usedUserAgentsKey) ?? [];
  var used = <String>[];
  for (final previous in history) {
    final agent = normalizeDesktopUserAgentForPlatform(previous);
    if (!candidates.contains(agent)) continue;
    // Old Linux/Windows templates could advertise the same Chrome version.
    // Retain the last occurrence when moving to the five Linux templates.
    used.remove(agent);
    used.add(agent);
  }
  final last = used.isEmpty ? null : used.last;
  var available = candidates.where((ua) => !used.contains(ua)).toList();
  if (available.isEmpty) {
    used = [];
    // Không lặp lại UA cuối cùng khi bắt đầu vòng mới.
    available = candidates.where((ua) => ua != last).toList();
  }
  final selected = available[Random().nextInt(available.length)];
  if (!await preferences.setStringList(_usedUserAgentsKey, [
    ...used,
    selected,
  ])) {
    throw StateError('Cannot persist User-Agent history');
  }
  if (kDebugMode) {
    debugPrint(
      '[User-Agent] New session (${used.length + 1}/${candidates.length}): $selected',
    );
  }
  return selected;
}
