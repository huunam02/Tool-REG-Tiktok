import 'dart:async';

import 'package:flutter/widgets.dart';

import '../accessibility_permission.dart';
import '../data_file_export.dart';
import '../proxy_store.dart';
import 'app_controller.dart';

class SettingsController extends AppController with WidgetsBindingObserver {
  SettingsController({
    AccessibilityPermissionService? accessibilityPermission,
    ProxyStore? proxyStore,
  }) : proxyStore = proxyStore ?? ProxyStore.instance,
       accessibilityPermission =
           accessibilityPermission ?? AccessibilityPermissionService();

  final ProxyStore proxyStore;
  bool exporting = false;
  bool previewing = false;

  /// Xem trước and Xuất Excel never run at the same time.
  bool get dataBusy => exporting || previewing;
  final AccessibilityPermissionService accessibilityPermission;
  bool? accessibilityEnabled;

  /// Enabled in Android settings but not bound (needs off and on again).
  bool accessibilityStalled = false;
  bool checkingAccessibility = false;
  bool openingAccessibilitySettings = false;
  String? accessibilityError;
  bool get accessibilityBusy =>
      checkingAccessibility || openingAccessibilitySettings;

  /// The rows Xuất Excel would save right now; null when there is nothing to
  /// show or reading failed (already reported).
  Future<DataExportPreview?> loadPreview() async {
    if (!active || dataBusy) return null;
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => previewing = true);
    try {
      final configurations = await proxyStore.list();
      final accounts = await proxyStore.nurture.listAccounts();
      if (!active) return null;
      if (configurations.isEmpty && accounts.isEmpty) {
        notify('Chưa có dữ liệu cấu hình hoặc nuôi Account để xem trước.');
        return null;
      }
      return DataExportPreview(
        configurations: configurations,
        accounts: accounts,
      );
    } catch (_) {
      if (active) notify('Không thể đọc dữ liệu để xem trước. Hãy thử lại.');
      return null;
    } finally {
      if (active) mutate(() => previewing = false);
    }
  }

  Future<void> exportExcel() async {
    if (!active || dataBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => exporting = true);
    try {
      final configurations = await proxyStore.list();
      final accounts = await proxyStore.nurture.listAccounts();
      if (!active) return;
      if (configurations.isEmpty && accounts.isEmpty) {
        notify('Chưa có dữ liệu cấu hình hoặc nuôi Account để xuất.');
        return;
      }
      final bytes = encodeDataExport(
        configurations: configurations,
        accounts: accounts,
      );
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final saved = await saveDataExportFile(
        'tiktok_data_$timestamp.xlsx',
        bytes,
      );
      if (saved && active) {
        notify(
          'Đã xuất ${configurations.length} cấu hình và ${accounts.length} tài khoản nuôi.',
        );
      }
    } catch (_) {
      if (active) notify('Không thể xuất Excel. Hãy thử lại.');
    } finally {
      if (active) mutate(() => exporting = false);
    }
  }

  @override
  void onInit() {
    super.onInit();
    if (accessibilityPermission.supported) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(refreshAccessibilityPermission());
    }
  }

  @override
  void onClose() {
    if (accessibilityPermission.supported) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !openingAccessibilitySettings) {
      unawaited(refreshAccessibilityPermission());
    }
  }

  Future<void> refreshAccessibilityPermission() async {
    if (!active ||
        !accessibilityPermission.supported ||
        checkingAccessibility) {
      return;
    }
    mutate(() {
      checkingAccessibility = true;
      accessibilityError = null;
    });
    try {
      final enabled = await accessibilityPermission.isEnabled();
      final running = enabled && await accessibilityPermission.isRunning();
      mutate(() {
        accessibilityEnabled = running;
        accessibilityStalled = enabled && !running;
      });
    } catch (_) {
      mutate(() {
        accessibilityEnabled = null;
        accessibilityError =
            'Không thể kiểm tra quyền. Chạm để mở Cài đặt Trợ năng.';
      });
    } finally {
      mutate(() => checkingAccessibility = false);
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!active || !accessibilityPermission.supported || accessibilityBusy) {
      return;
    }
    mutate(() => openingAccessibilitySettings = true);
    try {
      await accessibilityPermission.openSettings();
    } catch (_) {
      if (active) notify('Không mở được Cài đặt Trợ năng. Hãy thử lại.');
    } finally {
      if (active) {
        await refreshAccessibilityPermission();
        mutate(() => openingAccessibilitySettings = false);
      }
    }
  }
}
