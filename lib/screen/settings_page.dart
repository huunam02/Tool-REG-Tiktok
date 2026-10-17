import 'package:flutter/material.dart';

import '../controller/settings_controller.dart';
import '../core/accessibility_permission.dart';
import '../core/proxy_store.dart';
import 'usage_guide_page.dart';
import 'widgets/controller_scope.dart';
import 'widgets/settings_style.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.accessibilityPermission,
    this.onOpenBrowserCheck,
    this.onOpenIpCheck,
    this.proxyStore,
  });

  final AccessibilityPermissionService? accessibilityPermission;
  final VoidCallback? onOpenBrowserCheck;
  final VoidCallback? onOpenIpCheck;
  final ProxyStore? proxyStore;

  @override
  Widget build(BuildContext context) => ControllerScope<SettingsController>(
    controller: SettingsController(
      accessibilityPermission: accessibilityPermission,
      proxyStore: proxyStore,
    ),
    builder: (controller) =>
        _SettingsView(controller, onOpenBrowserCheck, onOpenIpCheck),
  );
}

class _SettingsView extends StatelessWidget {
  const _SettingsView(
    this.controller,
    this.onOpenBrowserCheck,
    this.onOpenIpCheck,
  );

  final SettingsController controller;
  final VoidCallback? onOpenBrowserCheck;
  final VoidCallback? onOpenIpCheck;

  Future<void> _openGuide(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const UsageGuidePage()));

  @override
  Widget build(BuildContext context) => Theme(
    data: SettingsStyle.theme(context),
    child: Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Text(
              'ỨNG DỤNG',
              style: TextStyle(
                color: SettingsStyle.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            SettingsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Xuất dữ liệu Excel',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Lưu cấu hình và thống kê nuôi Account chung một sheet Excel, mỗi cấu hình một hàng.',
                    style: TextStyle(
                      color: SettingsStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('exportExcel'),
                    onPressed: controller.exporting
                        ? null
                        : controller.exportExcel,
                    icon: controller.exporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: Text(
                      controller.exporting ? 'Đang xuất…' : 'Xuất Excel data',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SettingsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Kiểm tra IP / User-Agent',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Mở WhatIsMyBrowser bằng WebView với cấu hình proxy đang chọn để xem IP và trình duyệt website nhận được.',
                    style: TextStyle(
                      color: SettingsStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('openBrowserCheckSettings'),
                    onPressed: onOpenBrowserCheck,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Kiểm tra IP / User-Agent'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('openIpCheckSettings'),
                    onPressed: onOpenIpCheck,
                    icon: const Icon(Icons.public_outlined),
                    label: const Text('Kiểm tra IP với WhatIsMyIP'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (controller.accessibilityPermission.supported) ...[
              SettingsPanel(
                child: SwitchListTile(
                  key: const Key('accessibilitySettings'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Quyền Trợ năng',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      controller.openingAccessibilitySettings
                          ? 'Đang mở Cài đặt Trợ năng…'
                          : controller.checkingAccessibility
                          ? 'Đang kiểm tra quyền…'
                          : controller.accessibilityError ??
                                (controller.accessibilityEnabled == true
                                    ? 'Đã bật. Chạm để thay đổi trong Cài đặt Android.'
                                    : 'Chưa bật. Bật switch để cấp quyền thao tác trên TikTok.'),
                      style: const TextStyle(
                        color: SettingsStyle.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                  value: controller.accessibilityEnabled ?? false,
                  onChanged: controller.accessibilityBusy
                      ? null
                      : (_) => controller.openAccessibilitySettings(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            SettingsPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hướng dẫn sử dụng',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Các bước cấu hình proxy, tài khoản và chạy tác vụ TikTok.',
                    style: TextStyle(
                      color: SettingsStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    key: const Key('openUsageGuide'),
                    onPressed: () => _openGuide(context),
                    child: const Text('Mở hướng dẫn sử dụng'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
