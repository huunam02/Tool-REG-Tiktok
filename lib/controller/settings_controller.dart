import 'package:flutter/foundation.dart';

import '../core/otp_settings_store.dart';
import 'app_controller.dart';

class SettingsController extends AppController {
  SettingsController({
    required OtpApiSettings initialSettings,
    required this.store,
    required this.onSettingsChanged,
  }) : otpSettings = initialSettings;

  final OtpSettingsStore store;
  final ValueChanged<OtpApiSettings> onSettingsChanged;
  OtpApiSettings otpSettings;

  void applyOtpSettings(OtpApiSettings settings) => mutate(() {
        otpSettings = settings;
        onSettingsChanged(settings);
      });
}
