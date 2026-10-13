import 'package:flutter/material.dart';

import '../core/otp_api.dart';
import '../core/otp_settings_store.dart';
import 'app_controller.dart';

class OtpSettingsController extends AppController {
  OtpSettingsController({required this.initialSettings, required this.store});

  final OtpApiSettings initialSettings;
  final OtpSettingsStore store;
  final formKey = GlobalKey<FormState>();
  late final url = TextEditingController(text: initialSettings.url);
  late final token = TextEditingController(text: initialSettings.token);
  bool tokenHidden = true;
  bool saving = false;

  String? validateUrl(String? value) {
    try {
      OtpApiConfiguration.parseUrl(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? validateToken(String? value) =>
      value == null || value.trim().isEmpty ? 'Nhập token API lấy OTP.' : null;

  void toggleTokenVisibility() => mutate(() => tokenHidden = !tokenHidden);

  Future<OtpApiSettings?> save() async {
    if (saving || formKey.currentState?.validate() != true) return null;
    final settings = OtpApiSettings(
      url: url.text.trim(),
      token: token.text.trim(),
    );
    mutate(() => saving = true);
    try {
      await store.save(settings);
      return active ? settings : null;
    } catch (_) {
      if (active) notify('Không thể lưu cấu hình OTP API. Hãy thử lại.');
      return null;
    } finally {
      if (active) mutate(() => saving = false);
    }
  }

  @override
  void onClose() {
    url.dispose();
    token.dispose();
    super.onClose();
  }
}
