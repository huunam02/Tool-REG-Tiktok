import 'package:flutter/foundation.dart';

import 'services/remote_config_service.dart';

class CaptchaApiSettings {
  const CaptchaApiSettings({required this.licenseKey});
  final String licenseKey;
}

class CaptchaSettingsStore extends ChangeNotifier {
  static final instance = CaptchaSettingsStore();
  String? _lastLoadedKey;
  bool loaded = false;

  String get effectiveLicenseKey =>
      RemoteConfig.getString(RemoteConfigKey.sadcaptcha_license_key);

  Future<CaptchaApiSettings> load() async {
    final key = effectiveLicenseKey;
    final changed = !loaded || _lastLoadedKey != key;
    _lastLoadedKey = key;
    loaded = true;
    if (changed) notifyListeners();
    return CaptchaApiSettings(licenseKey: key);
  }
}
