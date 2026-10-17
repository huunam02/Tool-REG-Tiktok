import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/accessibility_permission.dart';
import '../core/data_file_export.dart';
import '../core/proxy_store.dart';
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
  final AccessibilityPermissionService accessibilityPermission;
  bool? accessibilityEnabled;
  bool checkingAccessibility = false;
  bool openingAccessibilitySettings = false;
  String? accessibilityError;
  bool get accessibilityBusy =>
      checkingAccessibility || openingAccessibilitySettings;

  Future<void> exportExcel() async {
    if (!active || exporting) return;
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
      mutate(() => accessibilityEnabled = enabled);
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
