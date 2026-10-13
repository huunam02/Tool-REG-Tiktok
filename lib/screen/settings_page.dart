import 'package:flutter/material.dart';

import '../controller/settings_controller.dart';
import '../core/otp_settings_store.dart';
import 'otp_settings_page.dart';
import 'usage_guide_page.dart';
import 'widgets/controller_scope.dart';
import 'widgets/settings_style.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.initialOtpSettings,
    required this.otpSettingsStore,
    required this.onOtpSettingsChanged,
  });

  final OtpApiSettings initialOtpSettings;
  final OtpSettingsStore otpSettingsStore;
  final ValueChanged<OtpApiSettings> onOtpSettingsChanged;

  @override
  Widget build(BuildContext context) => ControllerScope<SettingsController>(
        controller: SettingsController(
          initialSettings: initialOtpSettings,
          store: otpSettingsStore,
          onSettingsChanged: onOtpSettingsChanged,
        ),
        builder: (controller) => _SettingsView(controller),
      );
}

class _SettingsView extends StatelessWidget {
  const _SettingsView(this.controller);

  final SettingsController controller;

  Future<void> _openOtpSettings(BuildContext context) async {
    final settings =
        await Navigator.of(context).push<OtpApiSettings>(MaterialPageRoute(
      builder: (_) => OtpSettingsPage(
        initialSettings: controller.otpSettings,
        store: controller.store,
      ),
    ));
    if (settings != null && context.mounted) {
      controller.applyOtpSettings(settings);
    }
  }

  Future<void> _openGuide(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const UsageGuidePage()),
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
                SettingsPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Cấu hình OTP Email API',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'URL và token dùng để tự lấy mã OTP khi đăng ký hoặc đăng nhập.',
                        style: TextStyle(
                          color: SettingsStyle.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('openOtpSettings'),
                        onPressed: () => _openOtpSettings(context),
                        child: const Text('Mở cấu hình OTP API'),
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
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
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
