import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/accessibility_permission.dart';
import '../core/otp_settings_store.dart';
import 'app_controller.dart';

class SettingsController extends AppController with WidgetsBindingObserver {
  SettingsController({
    required OtpApiSettings initialSettings,
    required this.store,
    required this.onSettingsChanged,
    AccessibilityPermissionService? accessibilityPermission,
  })  : otpSettings = initialSettings,
        accessibilityPermission =
            accessibilityPermission ?? AccessibilityPermissionService();

  final OtpSettingsStore store;
  final ValueChanged<OtpApiSettings> onSettingsChanged;
  OtpApiSettings otpSettings;
  final AccessibilityPermissionService accessibilityPermission;
  bool? accessibilityEnabled;
  bool checkingAccessibility = false;
  bool openingAccessibilitySettings = false;
  String? accessibilityError;
  bool get accessibilityBusy =>
      checkingAccessibility || openingAccessibilitySettings;

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

  void applyOtpSettings(OtpApiSettings settings) => mutate(() {
        otpSettings = settings;
        onSettingsChanged(settings);
      });
}
