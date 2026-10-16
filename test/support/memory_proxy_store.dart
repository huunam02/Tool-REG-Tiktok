import 'package:flutter/foundation.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/proxy_draft.dart';
import 'package:test_tiktok/core/nurture_store.dart';
import 'memory_nurture_store.dart';

class MemoryProxyStore extends ProxyStore {
  @override
  late final NurtureRepository nurture = MemoryNurtureRepository(
    () async => entries,
  );
  WebViewProxy? current;
  String currentUserAgent = 'cached-proxy-user-agent';
  String currentName = '';
  String currentTimeZoneId = '';
  AccountCredentials? currentAccount;
  AccountStatus currentStatus = AccountStatus.unregistered;
  int? currentId;
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
    return SynchronousFuture(
      current == null && currentAccount == null && currentId == null
          ? null
          : ProxyProfile(
              proxy: current,
              userAgent: currentUserAgent,
              timeZoneId: currentTimeZoneId,
              name: currentName,
              account: currentAccount,
              statusAccount: currentStatus,
              configurationId: currentId,
              hasBeenUsed: true,
            ),
    );
  }

  @override
  Future<void> setCurrent(WebViewProxy? proxy) async {
    if (failWrites) throw StateError('Storage unavailable');
    final saved = entries.where((entry) => sameProxy(entry.proxy, proxy));
    if (saved.isNotEmpty) {
      currentUserAgent = saved.first.userAgent;
      currentName = saved.first.name;
      currentTimeZoneId = saved.first.timeZoneId;
      currentAccount = saved.first.account;
      currentStatus = saved.first.statusAccount;
      currentId = saved.first.id;
      await setUsed(saved.first.id, true);
    } else if (proxy != null && !sameProxy(current, proxy)) {
      currentUserAgent = 'proxy-user-agent-${_nextAgent++}';
    }
    current = proxy;
    if (proxy == null) {
      currentAccount = null;
      currentId = null;
      currentName = '';
      currentTimeZoneId = '';
      currentStatus = AccountStatus.unregistered;
    }
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
    currentTimeZoneId = entry.timeZoneId;
    currentAccount = entry.account;
    currentStatus = entry.statusAccount;
    currentId = entry.id;
    await setUsed(id, true);
  }

  @override
  Future<int> save({
    int? id,
    required String name,
    required WebViewProxy? proxy,
    String? userAgent,
    AccountCredentials? account,
    AccountStatus? statusAccount,
    String? timeZoneId,
  }) async {
    if (failWrites) throw StateError('Storage unavailable');
    account?.validate();
    final existing = entries.where(
      (entry) => id == null
          ? sameProxy(entry.proxy, proxy) &&
                entry.account?.email == account?.email
          : entry.id == id,
    );
    final old = existing.isEmpty ? null : existing.first;
    final savedId = id ?? old?.id ?? _nextId++;
    final selectedUserAgent =
        userAgent?.trim() ??
        old?.userAgent ??
        (sameProxy(current, proxy)
            ? currentUserAgent
            : 'proxy-user-agent-${_nextAgent++}');
    entries.removeWhere((entry) => entry.id == savedId);
    entries.add(
      SavedProxy(
        id: savedId,
        name: name,
        proxy: proxy,
        userAgent: selectedUserAgent,
        timeZoneId:
            timeZoneId ??
            (old != null && sameProxy(old.proxy, proxy) ? old.timeZoneId : ''),
        account: account ?? old?.account,
        statusAccount:
            statusAccount ?? old?.statusAccount ?? AccountStatus.unregistered,
        hasBeenUsed: old?.hasBeenUsed ?? false,
      ),
    );
    final saved = entries.last;
    if (currentId == savedId && old != null && sameProfile(old, saved)) {
      currentName = saved.name;
      currentStatus = saved.statusAccount;
    }
    return savedId;
  }

  @override
  Future<List<int>> saveDrafts(List<ProxyDraft> drafts) async {
    return [
      for (final draft in drafts)
        await save(
          name: draft.name,
          proxy: draft.proxy,
          userAgent: draft.userAgent,
          timeZoneId: draft.timeZoneId,
          account: draft.account,
          statusAccount: draft.statusAccount,
        ),
    ];
  }

  @override
  Future<bool> cacheCurrentTimeZone(
    int id,
    WebViewProxy proxy,
    String zone,
  ) async {
    if (failWrites) throw StateError('Storage unavailable');
    if (currentId != id ||
        !sameProxy(current, proxy) ||
        currentTimeZoneId.isNotEmpty) {
      return false;
    }
    currentTimeZoneId = zone;
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      final entry = entries[index];
      entries[index] = SavedProxy(
        id: entry.id,
        name: entry.name,
        proxy: entry.proxy,
        userAgent: entry.userAgent,
        timeZoneId: zone,
        account: entry.account,
        statusAccount: entry.statusAccount,
        hasBeenUsed: entry.hasBeenUsed,
      );
    }
    return true;
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
      timeZoneId: entry.timeZoneId,
      account: entry.account,
      statusAccount: entry.statusAccount,
      hasBeenUsed: used,
    );
  }
}
