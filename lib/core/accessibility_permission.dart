import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

bool get supportsAccessibilityPermission => !kIsWeb && Platform.isAndroid;

class AccessibilityPermissionService {
  AccessibilityPermissionService({
    bool? supported,
    Future<bool> Function()? isEnabled,
    Future<bool> Function()? openSettings,
  })  : supported = supported ?? supportsAccessibilityPermission,
        _isEnabled = isEnabled ??
            FlutterAccessibilityService.isAccessibilityPermissionEnabled,
        _openSettings = openSettings ??
            FlutterAccessibilityService.requestAccessibilityPermission;

  final bool supported;
  final Future<bool> Function() _isEnabled;
  final Future<bool> Function() _openSettings;

  Future<bool> isEnabled() => _isEnabled();
  Future<bool> openSettings() => _openSettings();
}
