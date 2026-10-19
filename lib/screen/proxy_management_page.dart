import 'package:flutter/material.dart';

import '../controller/proxy_management_controller.dart';
import '../core/proxy_store.dart';
import '../core/app_configuration.dart';
import '../core/configuration_data.dart';
import 'create_proxy_page.dart';
import 'edit_proxy_page.dart';
import 'widgets/controller_scope.dart';
import 'widgets/proxy_form.dart';
import 'widgets/proxy_widgets.dart';

enum _ProxyMenuAction { checkIp, edit, delete }

class ProxyManagementPage extends StatelessWidget {
  const ProxyManagementPage({
    super.key,
    required this.store,
    this.detectTimeZone,
    this.onCheckIp,
  });
  final ProxyStore store;
  final Future<String> Function(WebViewProxy, String)? detectTimeZone;

  /// Kiểm tra IP: load the configuration, then open WhatIsMyBrowser.
  final Future<void> Function(SavedProxy entry)? onCheckIp;

  @override
  Widget build(BuildContext context) =>
      ControllerScope<ProxyManagementController>(
        controller: ProxyManagementController(store: store),
        builder: (logic) =>
            _ProxyManagementView(logic, detectTimeZone, onCheckIp),
      );
}

class _ProxyManagementView extends StatelessWidget {
  const _ProxyManagementView(this.logic, this.detectTimeZone, this.onCheckIp);
  final ProxyManagementController logic;
  final Future<String> Function(WebViewProxy, String)? detectTimeZone;
  final Future<void> Function(SavedProxy entry)? onCheckIp;

  Future<void> _checkIp(SavedProxy entry) async {
    await onCheckIp!(entry);
    // The check selected this configuration; show the list as stored.
    await logic.reload();
  }

  Future<void> _create(BuildContext context) async {
    final drafts = await Navigator.of(context).push<List<ProxyDraft>>(
      MaterialPageRoute(
        builder: (_) => CreateProxyPage(
          generateUserAgent: logic.store.generateUserAgent,
          detectTimeZone: detectTimeZone,
        ),
      ),
    );
    if (context.mounted) await logic.saveDrafts(drafts);
  }

  Future<void> _edit(BuildContext context, SavedProxy entry) async {
    final draft = await Navigator.of(context).push<ProxyDraft>(
      MaterialPageRoute(
        builder: (_) => EditProxyPage(
          entry: entry,
          generateUserAgent: logic.store.generateUserAgent,
          detectTimeZone: detectTimeZone,
        ),
      ),
    );
    if (context.mounted) await logic.saveDraft(draft, id: entry.id);
  }

  Future<void> _delete(BuildContext context, SavedProxy entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình?'),
        content: Text('Xóa “${entry.name}” khỏi danh sách?'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await logic.delete(entry);
  }

  Widget _filters() {
    final used = logic.proxies.where((entry) => entry.hasBeenUsed).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (filter, label) in [
          (ProxyUsageFilter.all, 'Tất cả · ${logic.proxies.length}'),
          (
            ProxyUsageFilter.unused,
            'Chưa dùng · ${logic.proxies.length - used}',
          ),
          (ProxyUsageFilter.used, 'Đã dùng · $used'),
        ])
          ChoiceChip(
            key: Key('filter-${filter.name}'),
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: logic.filter == filter
                    ? ProxyColors.background
                    : ProxyColors.muted,
              ),
            ),
            selected: logic.filter == filter,
            selectedColor: ProxyColors.cyan,
            backgroundColor: ProxyColors.surface,
            side: BorderSide(
              color: logic.filter == filter
                  ? ProxyColors.cyan
                  : ProxyColors.border,
            ),
            showCheckmark: false,
            onSelected: logic.busy ? null : (_) => logic.setFilter(filter),
          ),
      ],
    );
  }

  Widget _proxyCard(BuildContext context, SavedProxy entry) {
    // Configurations are not chosen here: each run picks its own. A card
    // offers Kiểm tra IP, Sửa and Xóa.
    return Container(
      key: Key('savedProxy-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ProxyColors.surface,
        border: Border.all(color: ProxyColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logic.displayName(entry),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    proxyLabel(entry.proxy),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: ProxyColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ProxyUsageBadge(used: entry.hasBeenUsed),
                      ProxyBadge(
                        label: entry.statusAccount.label,
                        color: ProxyColors.cyan,
                      ),
                      if (entry.signupFailed &&
                          entry.statusAccount == AccountStatus.unregistered)
                        const ProxyBadge(
                          label: 'Lỗi đăng ký',
                          color: ProxyColors.red,
                        ),
                      ProxyBadge(
                        label:
                            entry.proxy?.uri.scheme.toUpperCase() ?? 'MẶC ĐỊNH',
                        color: ProxyColors.muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<_ProxyMenuAction>(
              enabled: !logic.busy,
              tooltip: 'Tùy chọn cấu hình',
              onSelected: (action) => switch (action) {
                _ProxyMenuAction.checkIp => _checkIp(entry),
                _ProxyMenuAction.edit => _edit(context, entry),
                _ProxyMenuAction.delete => _delete(context, entry),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _ProxyMenuAction.edit,
                  child: Text('Sửa'),
                ),
                const PopupMenuItem(
                  value: _ProxyMenuAction.delete,
                  child: Text('Xóa'),
                ),
                if (onCheckIp != null)
                  PopupMenuItem(
                    key: Key('checkIp-${entry.id}'),
                    value: _ProxyMenuAction.checkIp,
                    child: const Text('Kiểm tra IP'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = logic.visibleProxies;
    return Theme(
      data: ProxyColors.theme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Quản lý cấu hình',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                key: const Key('addProxy'),
                tooltip: 'Thêm cấu hình',
                onPressed: logic.busy ? null : () => _create(context),
                style: IconButton.styleFrom(
                  foregroundColor: ProxyColors.cyan,
                  backgroundColor: ProxyColors.cyan.withValues(alpha: 0.08),
                  disabledForegroundColor: ProxyColors.muted.withValues(
                    alpha: 0.45,
                  ),
                  side: BorderSide(
                    color: ProxyColors.cyan.withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(40, 40),
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.add_rounded, size: 22),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth > 1012
                ? (constraints.maxWidth - 980) / 2
                : 16.0;
            return CustomScrollView(
              key: const Key('proxyListScroll'),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (logic.busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                        ],
                        if (logic.loadFailed) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: logic.busy ? null : logic.retry,
                            child: const Text('Thử lại'),
                          ),
                        ],
                        TextField(
                          key: const Key('searchProxies'),
                          controller: logic.search,
                          decoration: const InputDecoration(
                            hintText: 'Tìm tên, địa chỉ proxy hoặc email',
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                          onChanged: logic.searchChanged,
                        ),
                        const SizedBox(height: 12),
                        _filters(),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      child: Column(
                        children: [
                          Text(
                            logic.busy
                                ? 'Đang tải cấu hình…'
                                : logic.loadFailed
                                ? 'Không thể tải danh sách cấu hình.'
                                : logic.proxies.isEmpty
                                ? 'Chưa có cấu hình'
                                : 'Không có cấu hình phù hợp.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: ProxyColors.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) =>
                          _proxyCard(context, visible[index]),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }
}
