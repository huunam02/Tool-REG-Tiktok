import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

bool get supportsAccessibilityPermission => !kIsWeb && Platform.isAndroid;

class AccessibilityPermissionService {
  AccessibilityPermissionService({
    bool? supported,
    Future<bool> Function()? isEnabled,
    Future<bool> Function()? isRunning,
    Future<bool> Function()? openSettings,
  }) : supported = supported ?? supportsAccessibilityPermission,
       _isRunning =
           isRunning ??
           FlutterAccessibilityService.isAccessibilityServiceRunning,
       _isEnabled =
           isEnabled ??
           FlutterAccessibilityService.isAccessibilityPermissionEnabled,
       _openSettings =
           openSettings ??
           FlutterAccessibilityService.requestAccessibilityPermission;

  final bool supported;
  final Future<bool> Function() _isEnabled;
  final Future<bool> Function() _isRunning;
  final Future<bool> Function() _openSettings;

  Future<bool> isEnabled() => _isEnabled();

  /// Enabled in Android settings and bound right now. Android can keep the
  /// setting on while the service is not connected (Samsung after an app
  /// update); it needs to be switched off and on again then.
  Future<bool> isRunning() => _isRunning();
  Future<bool> openSettings() => _openSettings();
}
