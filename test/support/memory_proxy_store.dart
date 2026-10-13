import 'package:flutter/foundation.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';

class MemoryProxyStore extends ProxyStore {
  WebViewProxy? current;
  String currentUserAgent = 'cached-proxy-user-agent';
  String currentName = '';
  final entries = <SavedProxy>[];
  bool failWrites = false;
  bool failReads = false;
  int _nextId = 1;
  int _nextAgent = 1;

  @override
  Future<String> generateUserAgent() =>
      SynchronousFuture('proxy-user-agent-${_nextAgent++}');

  @override
  Future<WebViewProxy?> getCurrent() {
    if (failReads) throw StateError('Storage unavailable');
    return SynchronousFuture(current);
  }

  @override
  Future<ProxyProfile?> getCurrentProfile() {
    if (failReads) throw StateError('Storage unavailable');
    return SynchronousFuture(current == null
        ? null
        : ProxyProfile(
            proxy: current!,
            userAgent: currentUserAgent,
            name: currentName,
            hasBeenUsed: true));
  }

  @override
  Future<void> setCurrent(WebViewProxy? proxy) async {
    if (failWrites) throw StateError('Storage unavailable');
    final saved = entries.where((entry) => sameProxy(entry.proxy, proxy));
    if (saved.isNotEmpty) {
      currentUserAgent = saved.first.userAgent;
      currentName = saved.first.name;
      await setUsed(saved.first.id, true);
    } else if (proxy != null && !sameProxy(current, proxy)) {
      currentUserAgent = 'proxy-user-agent-${_nextAgent++}';
    }
    current = proxy;
  }

  @override
  Future<List<SavedProxy>> list() async => List.of(entries.reversed);

  @override
  Future<void> useSaved(int id) async {
    if (failWrites) throw StateError('Storage unavailable');
    final entry = entries.singleWhere((entry) => entry.id == id);
    current = entry.proxy;
    currentUserAgent = entry.userAgent;
    currentName = entry.name;
    await setUsed(id, true);
  }

  @override
  Future<int> save(
      {int? id,
      required String name,
      required WebViewProxy proxy,
      String? userAgent}) async {
    if (failWrites) throw StateError('Storage unavailable');
    final existing = entries.where(
        (entry) => id == null ? sameProxy(entry.proxy, proxy) : entry.id == id);
    final old = existing.isEmpty ? null : existing.first;
    final savedId = id ?? old?.id ?? _nextId++;
    final selectedUserAgent = userAgent?.trim() ??
        old?.userAgent ??
        (sameProxy(current, proxy)
            ? currentUserAgent
            : 'proxy-user-agent-${_nextAgent++}');
    entries.removeWhere((entry) => entry.id == savedId);
    entries.add(SavedProxy(
        id: savedId,
        name: name,
        proxy: proxy,
        userAgent: selectedUserAgent,
        hasBeenUsed: old?.hasBeenUsed ?? false));
    return savedId;
  }

  @override
  Future<void> delete(int id) async {
    if (failWrites) throw StateError('Storage unavailable');
    entries.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<void> setUsed(int id, bool used) async {
    if (failWrites) throw StateError('Storage unavailable');
    final index = entries.indexWhere((entry) => entry.id == id);
    final entry = entries[index];
    entries[index] = SavedProxy(
        id: entry.id,
        name: entry.name,
        proxy: entry.proxy,
        userAgent: entry.userAgent,
        hasBeenUsed: used);
  }
}
