import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

import '../../core/accessibility_permission.dart';

export '../../core/accessibility_permission.dart'
    show supportsAccessibilityPermission;

/// Checks on the main screen, independently of account/proxy configuration.
class AccessibilityPermissionPrompt extends StatefulWidget {
  const AccessibilityPermissionPrompt({
    super.key,
    required this.child,
    this.isEnabled,
    this.requestPermission,
  });

  final Widget child;
  final Future<bool> Function()? isEnabled;
  final Future<bool> Function()? requestPermission;

  @override
  State<AccessibilityPermissionPrompt> createState() =>
      _AccessibilityPermissionPromptState();
}

class _AccessibilityPermissionPromptState
    extends State<AccessibilityPermissionPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (supportsAccessibilityPermission || widget.isEnabled != null)) {
        showAccessibilityPermissionDialog(
          context,
          onlyIfDisabled: true,
          isEnabled: widget.isEnabled,
          requestPermission: widget.requestPermission,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showAccessibilityPermissionDialog(
  BuildContext context, {
  bool onlyIfDisabled = false,
  Future<bool> Function()? isEnabled,
  Future<bool> Function()? requestPermission,
}) async {
  final check =
      isEnabled ?? FlutterAccessibilityService.isAccessibilityPermissionEnabled;
  final request =
      requestPermission ??
      FlutterAccessibilityService.requestAccessibilityPermission;
  bool? enabled;
  try {
    enabled = await check();
  } catch (_) {
    // A startup check failure does not establish that permission was revoked.
    // The user can still inspect/open accessibility from Settings.
    if (onlyIfDisabled) return;
  }
  if (!context.mounted || onlyIfDisabled && enabled == true) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AccessibilityPermissionDialog(
      enabled: enabled,
      check: check,
      request: request,
    ),
  );
}

class _AccessibilityPermissionDialog extends StatefulWidget {
  const _AccessibilityPermissionDialog({
    required this.enabled,
    required this.check,
    required this.request,
  });

  final bool? enabled;
  final Future<bool> Function() check;
  final Future<bool> Function() request;

  @override
  State<_AccessibilityPermissionDialog> createState() =>
      _AccessibilityPermissionDialogState();
}

class _AccessibilityPermissionDialogState
    extends State<_AccessibilityPermissionDialog> {
  bool _opening = false;
  String? _message;

  Future<void> _openSettings() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _message = null;
    });
    try {
      // Wait for the settings Activity to return before checking permission.
      await widget.request();
      if (!mounted) return;
      final enabled = await widget.check();
      if (!mounted) return;
      if (enabled) {
        Navigator.of(context).pop();
        return;
      }
      setState(
        () => _message =
            'Quyền Trợ năng chưa được bật. '
            'Trong Cài đặt, chọn Tool TikTok rồi bật Sử dụng dịch vụ.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Không mở được Cài đặt Trợ năng. '
              'Hãy mở Cài đặt Android → Trợ năng → Tool TikTok để bật dịch vụ.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('accessibilityPermissionDialog'),
    title: Text(
      widget.enabled == null
          ? 'Kiểm tra quyền Trợ năng'
          : widget.enabled!
          ? 'Trợ năng đã bật'
          : 'Bật quyền Trợ năng',
    ),
    content: Text(
      widget.enabled == true
          ? 'Tool TikTok đã có quyền Trợ năng để bấm nút Send code.'
          : _message ??
                (widget.enabled == null
                    ? 'Chưa kiểm tra được trạng thái quyền Trợ năng. Bạn có thể mở Cài đặt để kiểm tra.'
                    : 'Tool TikTok cần quyền Trợ năng tự động thao tác bấm trên màn hình.\n\n'
                          'Nhấn Mở cài đặt → chọn Tool TikTok → bật Sử dụng dịch vụ, rồi quay lại ứng dụng.'),
    ),
    actions: [
      TextButton(
        onPressed: _opening ? null : () => Navigator.of(context).pop(),
        child: Text(widget.enabled == true ? 'Đóng' : 'Để sau'),
      ),
      if (widget.enabled != true)
        FilledButton(
          key: const Key('openAccessibilitySettings'),
          onPressed: _opening ? null : _openSettings,
          child: Text(_opening ? 'Đang mở…' : 'Mở cài đặt'),
        ),
    ],
  );
}
