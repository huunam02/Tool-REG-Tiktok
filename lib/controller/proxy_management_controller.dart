import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/proxy_store.dart';
import '../core/proxy_draft.dart';
import 'app_controller.dart';

enum ProxyUsageFilter { all, unused, used }

class ProxyManagementController extends AppController {
  ProxyManagementController({required this.store});
  final ProxyStore store;

  List<SavedProxy> proxies = [];
  ProxyProfile? current;
  int? selectedId;
  bool busy = true;
  bool loadFailed = false;
  bool resettingSession = false;
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
    final current = await store.getCurrentProfile();
    if (!active) return;
    mutate(() {
      this.proxies = proxies;
      this.current = current;
      loadFailed = false;
      if (!proxies.any((entry) => entry.id == selectedId)) {
        selectedId = null;
        for (final entry in proxies) {
          if (sameProfile(entry, current)) {
            selectedId = entry.id;
            break;
          }
        }
      }
      if (!visibleProxies.any((entry) => entry.id == selectedId)) {
        selectedId = null;
      }
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
        error is _SessionResetFailure
            ? 'Không thể xóa phiên. Cấu hình đang sử dụng chưa thay đổi. Hãy thử lại.'
            : 'Không thể đọc hoặc lưu cấu hình. Hãy thử lại.',
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
      final savedId = await store.save(
        id: id,
        name: draft.name,
        proxy: draft.proxy,
        userAgent: draft.userAgent,
        timeZoneId: draft.timeZoneId,
        account: draft.account,
        statusAccount: draft.statusAccount,
        nurtureAfterSignup: draft.nurtureAfterSignup,
      );
      selectedId = savedId;
      filter = ProxyUsageFilter.all;
      search.clear();
      await reload();
    });
  }

  Future<void> saveDrafts(List<ProxyDraft>? drafts) async {
    if (drafts == null || drafts.isEmpty || !active) return;
    await _perform(() async {
      final ids = await store.saveDrafts(drafts);
      selectedId = ids.last;
      filter = ProxyUsageFilter.all;
      search.clear();
      await reload();
      if (drafts.length > 1) notify('Đã lưu ${drafts.length} cấu hình.');
    });
  }

  Future<void> delete(SavedProxy entry) async {
    await _perform(() async {
      await store.delete(entry.id);
      await reload();
    });
  }

  Future<bool> use(SavedProxy? entry) async {
    var saved = false;
    if (busy) return false;
    try {
      await _perform(() async {
        final current = await store.getCurrentProfile();
        if (!active) return;
        final changed = entry != null && !sameProfile(current, entry);
        if (changed) {
          mutate(() => resettingSession = true);
          try {
            await clearAppSession();
          } catch (_) {
            throw const _SessionResetFailure();
          }
        }
        if (!active) return;
        if (entry == null) {
          await store.setCurrent(null);
        } else {
          await store.useSaved(entry.id);
        }
        saved = true;
      });
    } finally {
      if (active) mutate(() => resettingSession = false);
    }
    return saved;
  }

  bool isActive(SavedProxy entry) => sameProfile(entry, current);

  String displayName(SavedProxy entry) =>
      entry.account?.email ?? proxyLabel(entry.proxy);

  void setFilter(ProxyUsageFilter value) => mutate(() {
    filter = value;
    selectedId = null;
  });

  void select(SavedProxy entry) => mutate(() {
    selectedId = selectedId == entry.id ? null : entry.id;
  });

  void searchChanged(String _) => mutate(() => selectedId = null);

  Future<void> retry() => _perform(reload);
}

class _SessionResetFailure implements Exception {
  const _SessionResetFailure();
}
