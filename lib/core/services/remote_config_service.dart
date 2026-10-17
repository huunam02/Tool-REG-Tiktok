// ignore_for_file: constant_identifier_names
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:test_tiktok/core/config.dart';

enum RemoteConfigKey {
  otp_api_url,
  otp_api_token;

  dynamic get defaultValue {
    switch (this) {
      case otp_api_url:
        return otpApiUrl;
      case otp_api_token:
        return otpApiToken;
    }
  }

  Type get valueType {
    switch (this) {
      case otp_api_url:
      case otp_api_token:
        return String;
    }
  }
}

class RemoteConfig {
  static final _remoteConfig = FirebaseRemoteConfig.instance;
  static Map<String, dynamic> configs = {};

  static Future<void> init() async {
    try {
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 30),
          minimumFetchInterval: const Duration(minutes: 1),
        ),
      );
      await _remoteConfig.fetchAndActivate();
      getRemoteConfig();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Remote Config fetch failed: $e');
      }
    }
  }

  static void getRemoteConfig() {
    for (var key in RemoteConfigKey.values) {
      try {
        switch (key.valueType) {
          case const (String):
            configs[key.name] = _remoteConfig.getString(key.name);
            break;
          case const (int):
            configs[key.name] = _remoteConfig.getInt(key.name);
            break;
          case const (double):
            configs[key.name] = _remoteConfig.getDouble(key.name);
            break;
          case const (bool):
            configs[key.name] = _remoteConfig.getBool(key.name);
            break;
        }
      } catch (e) {
        configs[key.name] = key.defaultValue;
      }

      if (kDebugMode) {
        debugPrint(
          'CHECK_REMOTE_CONFIG, key: ${key.name} - value: ${configs[key.name]}',
        );
      }
    }
  }
}
