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
              '${entry.name} ${proxyAddress(entry.proxy)} ${entry.proxy.username}'
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
          if (sameProxy(entry.proxy, current?.proxy) &&
              entry.userAgent == current?.userAgent) {
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
              ? 'Không thể xóa phiên. Proxy đang sử dụng chưa thay đổi. Hãy thử lại.'
              : 'Không thể đọc hoặc lưu proxy. Hãy thử lại.',
          actionLabel: 'Thử lại', onAction: () {
        if (!busy) retry();
      });
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
          userAgent: draft.userAgent);
      selectedId = savedId;
      filter = ProxyUsageFilter.all;
      search.clear();
      await reload();
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
        final changed = entry != null &&
            (!sameProxy(current?.proxy, entry.proxy) ||
                current?.userAgent != entry.userAgent);
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

  bool isActive(SavedProxy entry) =>
      sameProxy(entry.proxy, current?.proxy) &&
      entry.userAgent == current?.userAgent;

  String displayName(SavedProxy entry) =>
      entry.name == proxyAddress(entry.proxy)
          ? entry.proxy.uri.host
          : entry.name;

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
