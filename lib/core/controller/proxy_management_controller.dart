import 'package:flutter/material.dart';

import '../proxy_store.dart';
import '../account_sessions.dart';
import '../proxy_draft.dart';
import 'app_controller.dart';

enum ProxyUsageFilter { all, unused, used }

class ProxyManagementController extends AppController {
  ProxyManagementController({required this.store});
  final ProxyStore store;

  List<SavedProxy> proxies = [];
  bool busy = true;
  bool loadFailed = false;
  late final search = TextEditingController();
  ProxyUsageFilter filter = ProxyUsageFilter.all;

  List<SavedProxy> get visibleProxies {
    final query = search.text.trim().toLowerCase();
    return proxies.where((entry) {
      final matchesStatus = switch (filter) {
        ProxyUsageFilter.all => true,
        ProxyUsageFilter.unused => !entry.hasBeenUsed,
        ProxyUsageFilter.used => entry.hasBeenUsed,
      };
      return matchesStatus &&
          (query.isEmpty ||
              '${entry.name} ${proxyLabel(entry.proxy)} ${entry.proxy?.username ?? ''} ${entry.account?.email ?? ''}'
                  .toLowerCase()
                  .contains(query));
    }).toList();
  }

  @override
  void onClose() {
    search.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    _perform(reload);
  }

  Future<void> reload() async {
    final proxies = await store.list();
    if (!active) return;
    mutate(() {
      this.proxies = proxies;
      loadFailed = false;
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    mutate(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (!active) return;
      mutate(() => loadFailed = true);
      notify(
        'Không thể đọc hoặc lưu cấu hình. Hãy thử lại.',
        actionLabel: 'Thử lại',
        onAction: () {
          if (!busy) retry();
        },
      );
    } finally {
      if (active) mutate(() => busy = false);
    }
  }

  Future<void> saveDraft(ProxyDraft? draft, {int? id}) async {
    if (draft == null || !active) return;
    await _perform(() async {
      await store.save(
        id: id,
        name: draft.name,
        proxy: draft.proxy,
        userAgent: draft.userAgent,
        timeZoneId: draft.timeZoneId,
        account: draft.account,
        statusAccount: draft.statusAccount,
        nurtureAfterSignup: draft.nurtureAfterSignup,
        nurtureSettings: draft.nurtureSettings,
        gpuProfileId: draft.gpuProfileId,
      );
      filter = ProxyUsageFilter.all;
      search.clear();
      await reload();
    });
  }

  Future<void> saveDrafts(List<ProxyDraft>? drafts) async {
    if (drafts == null || drafts.isEmpty || !active) return;
    await _perform(() async {
      await store.saveDrafts(drafts);
      filter = ProxyUsageFilter.all;
      search.clear();
      await reload();
      if (drafts.length > 1) notify('Đã lưu ${drafts.length} cấu hình.');
    });
  }

  Future<void> delete(SavedProxy entry) async {
    await _perform(() async {
      await store.delete(entry.id);
      await AccountSessions.delete(entry.id);
      await reload();
    });
  }

  String displayName(SavedProxy entry) =>
      entry.account?.email ?? proxyLabel(entry.proxy);

  void setFilter(ProxyUsageFilter value) => mutate(() => filter = value);

  /// Rebuilds the filtered list as the search text changes.
  void searchChanged(String _) => mutate(() {});

  Future<void> retry() => _perform(reload);
}
