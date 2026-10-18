import 'package:flutter/foundation.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/proxy_draft.dart';
import 'package:test_tiktok/core/nurture_store.dart';
import 'package:test_tiktok/core/signup_failure.dart';
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
  bool? currentAccountLoggedIn;
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
              nurtureAfterSignup: entries.any(
                (entry) => entry.id == currentId && entry.nurtureAfterSignup,
              ),
            ),
    );
  }

  @override
  Future<void> setCurrent(WebViewProxy? proxy) async {
    if (failWrites) throw StateError('Storage unavailable');
    final previousId = currentId;
    final previousProxy = current;
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
    if (currentId != previousId || !sameProxy(previousProxy, proxy)) {
      currentAccountLoggedIn = false;
    }
  }

  @override
  Future<List<SavedProxy>> list() async => List.of(entries.reversed);

  @override
  Future<void> useSaved(int id) async {
    if (failWrites) throw StateError('Storage unavailable');
    final entry = entries.singleWhere((entry) => entry.id == id);
    if (currentId != id ||
        !sameProxy(current, entry.proxy) ||
        currentUserAgent != entry.userAgent ||
        currentTimeZoneId != entry.timeZoneId ||
        !sameAccount(currentAccount, entry.account)) {
      currentAccountLoggedIn = false;
    }
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
  Future<bool> canReuseCurrentAccountSession() async =>
      currentAccountLoggedIn != false;

  @override
  Future<bool> setCurrentAccountLoggedIn(
    int configurationId,
    String email,
    bool loggedIn,
  ) async {
    if (failWrites) throw StateError('Storage unavailable');
    if (currentId != configurationId || currentAccount?.email != email.trim()) {
      return false;
    }
    currentAccountLoggedIn = loggedIn;
    return true;
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
    bool? nurtureAfterSignup,
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
        nurtureAfterSignup:
            nurtureAfterSignup ?? old?.nurtureAfterSignup ?? false,
        signupFailed: _signupFailedOverride ?? old?.signupFailed ?? false,
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
          nurtureAfterSignup: draft.nurtureAfterSignup,
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
        nurtureAfterSignup: entry.nurtureAfterSignup,
        signupFailed: entry.signupFailed,
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
  Future<bool> markRegistered(int id, String email) async {
    if (failWrites) throw StateError('Storage unavailable');
    final matches = entries.where(
      (entry) => entry.id == id && entry.account?.email == email.trim(),
    );
    if (email.trim().isEmpty || matches.isEmpty) return false;
    final entry = matches.single;
    _signupFailedOverride = false;
    try {
      await save(
        id: id,
        name: entry.name,
        proxy: entry.proxy,
        statusAccount: AccountStatus.registered,
      );
    } finally {
      _signupFailedOverride = null;
    }
    return true;
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
      nurtureAfterSignup: entry.nurtureAfterSignup,
      signupFailed: entry.signupFailed,
    );
  }

  final signupFailures = <SignupFailure>[];
  bool? _signupFailedOverride;
  int _nextFailureId = 1;

  Future<void> _setSignupFailed(SavedProxy entry, bool failed) async {
    _signupFailedOverride = failed;
    try {
      await save(id: entry.id, name: entry.name, proxy: entry.proxy);
    } finally {
      _signupFailedOverride = null;
    }
  }

  @override
  Future<bool> recordSignupFailure(
    int id,
    String email, {
    required String message,
    String step = '',
    DateTime? at,
  }) async {
    if (failWrites) throw StateError('Storage unavailable');
    final matches = entries.where(
      (entry) =>
          entry.id == id &&
          entry.account?.email == email.trim() &&
          entry.statusAccount == AccountStatus.unregistered,
    );
    if (email.trim().isEmpty || matches.isEmpty) return false;
    signupFailures.add(
      SignupFailure(
        id: _nextFailureId++,
        configurationId: id,
        email: email.trim(),
        message: message,
        step: step,
        createdAt: at ?? DateTime.now(),
      ),
    );
    await _setSignupFailed(matches.single, true);
    return true;
  }

  @override
  Future<List<FailedConfiguration>> listFailedConfigurations({
    int logLimit = 20,
  }) async {
    final failed = [
      for (final entry in entries.reversed)
        if (entry.signupFailed &&
            entry.statusAccount == AccountStatus.unregistered)
          FailedConfiguration(
            configuration: entry,
            failureCount: signupFailures
                .where((failure) => failure.configurationId == entry.id)
                .length,
            failures: signupFailures.reversed
                .where((failure) => failure.configurationId == entry.id)
                .take(logLimit)
                .toList(),
          ),
    ];
    return failed;
  }

  @override
  Future<void> clearSignupFailure(int id) async {
    final entry = entries.singleWhere((entry) => entry.id == id);
    await _setSignupFailed(entry, false);
  }
}
