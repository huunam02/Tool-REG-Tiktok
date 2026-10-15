import 'package:flutter/material.dart';

import '../controller/otp_settings_controller.dart';
import '../core/otp_settings_store.dart';
import 'widgets/controller_scope.dart';
import 'widgets/settings_style.dart';

class OtpSettingsPage extends StatelessWidget {
  const OtpSettingsPage({
    super.key,
    required this.initialSettings,
    required this.store,
  });

  final OtpApiSettings initialSettings;
  final OtpSettingsStore store;

  @override
  Widget build(BuildContext context) => ControllerScope<OtpSettingsController>(
        controller: OtpSettingsController(
          initialSettings: initialSettings,
          store: store,
        ),
        builder: (controller) => _OtpSettingsView(controller),
      );
}

class _OtpSettingsView extends StatelessWidget {
  const _OtpSettingsView(this.controller);

  final OtpSettingsController controller;

  Future<void> _save(BuildContext context) async {
    final settings = await controller.save();
    if (settings != null && context.mounted) Navigator.pop(context, settings);
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: SettingsStyle.theme(context),
        child: Scaffold(
          appBar: AppBar(title: const Text('Cấu hình OTP API')),
          body: SafeArea(
            child: Form(
              key: controller.formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  const Text(
                    'THÔNG TIN KẾT NỐI',
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
                          'API nhận mã OTP từ hộp thư',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Cấu hình này dùng chung cho luồng đăng ký và đăng nhập.',
                          style: TextStyle(
                            color: SettingsStyle.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const Key('otpApiUrl'),
                          controller: controller.url,
                          validator: controller.validateUrl,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'URL API',
                            hintText: 'https://example.com/api/code',
                            helperText: 'Chấp nhận URL HTTP hoặc HTTPS.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('otpApiToken'),
                          controller: controller.token,
                          validator: controller.validateToken,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Token API',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const Key('saveOtpSettings'),
                onPressed: controller.saving ? null : () => _save(context),
                child: Text(controller.saving ? 'Đang lưu…' : 'Lưu cấu hình'),
              ),
            ),
          ),
        ),
      );
}
