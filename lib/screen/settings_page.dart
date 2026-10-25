import 'package:flutter/material.dart';

import '../core/controller/settings_controller.dart';
import '../core/accessibility_permission.dart';
import '../core/proxy_store.dart';
import 'data_export_preview_page.dart';
import 'usage_guide_page.dart';
import 'widgets/controller_scope.dart';
import 'widgets/settings_style.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.accessibilityPermission,
    this.proxyStore,
  });

  final AccessibilityPermissionService? accessibilityPermission;
  final ProxyStore? proxyStore;

  @override
  Widget build(BuildContext context) => ControllerScope<SettingsController>(
    controller: SettingsController(
      accessibilityPermission: accessibilityPermission,
      proxyStore: proxyStore,
    ),
    builder: (controller) => _SettingsView(controller),
  );
}

class _SettingsView extends StatelessWidget {
  const _SettingsView(this.controller);

  final SettingsController controller;

  Future<void> _openGuide(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const UsageGuidePage()));

  Future<void> _preview(BuildContext context) async {
    final preview = await controller.loadPreview();
    if (preview == null || !context.mounted) return;
    final export = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DataExportPreviewPage(preview: preview),
      ),
    );
    if (export == true) await controller.exportExcel();
  }

  static const _progress = SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

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
            // Automation needs it first, so it leads the page.
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
                                (controller.accessibilityStalled
                                    ? 'Đã bật nhưng dịch vụ chưa chạy. Chạm để tắt rồi bật lại Trợ năng; nếu vẫn không chạy, khởi động lại điện thoại.'
                                    : controller.accessibilityEnabled == true
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('previewExcel'),
                          onPressed: controller.dataBusy
                              ? null
                              : () => _preview(context),
                          icon: controller.previewing
                              ? _progress
                              : const Icon(Icons.visibility_outlined),
                          label: Text(
                            controller.previewing ? 'Đang tải…' : 'Xem trước',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('exportExcel'),
                          onPressed: controller.dataBusy
                              ? null
                              : controller.exportExcel,
                          icon: controller.exporting
                              ? _progress
                              : const Icon(Icons.file_download_outlined),
                          label: Text(
                            controller.exporting ? 'Đang xuất…' : 'Xuất Excel',
                          ),
                        ),
                      ),
                    ],
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
