// ignore_for_file: constant_identifier_names
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../config.dart' as built_in;

enum RemoteConfigKey {
  otp_api_url,
  otp_api_token,
  sadcaptcha_license_key,
  search_keywords,
  auto_comments;

  String get defaultValue => switch (this) {
    otp_api_url => 'https://drainer-wager-uncheck.ngrok-free.dev/api/code',
    otp_api_token => 'c3247bbbf1e7b6913cbf314a4f0aa16e',
    sadcaptcha_license_key => '406b433775d67e306eb3192ab99c344a',
    search_keywords => jsonEncode(built_in.defaultSearchKeywords),
    auto_comments => jsonEncode(built_in.defaultAutoComments),
  };
}

class RemoteConfig {
  static Map<String, dynamic> get defaults => {
    for (final key in RemoteConfigKey.values) key.name: key.defaultValue,
  };
  static Map<String, dynamic> configs = defaults;

  static String getString(RemoteConfigKey key) {
    final value = configs[key.name];
    return value is String ? value.trim() : key.defaultValue;
  }

  static List<String> get searchKeywords =>
      getStringList(RemoteConfigKey.search_keywords);

  static List<String> get autoComments =>
      getStringList(RemoteConfigKey.auto_comments);

  /// Store each list as a String parameter containing a JSON array. An explicit []
  /// stays empty; malformed values fall back to the built-in default list.
  static List<String> getStringList(RemoteConfigKey key) {
    List<String> decode(String value) {
      final decoded = jsonDecode(value);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        throw const FormatException('Expected a JSON array of strings');
      }
      return List.unmodifiable(
        decoded
            .cast<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
    }

    try {
      return decode(getString(key));
    } on FormatException {
      return decode(key.defaultValue);
    }
  }

  static Future<void> init({FirebaseRemoteConfig? instance}) async {
    configs = defaults;
    FirebaseRemoteConfig? remote;
    try {
      remote = instance ?? FirebaseRemoteConfig.instance;
      await remote.setDefaults(defaults);
      await remote.ensureInitialized();
      await remote.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 30),
          minimumFetchInterval: const Duration(minutes: 1),
        ),
      );
      await remote.fetchAndActivate();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Remote Config unavailable (${error.runtimeType}); using cached/default values.',
        );
      }
    } finally {
      // Read cached activated values even when the network fetch fails.
      if (remote != null) getRemoteConfig(instance: remote);
    }
  }

  static void getRemoteConfig({FirebaseRemoteConfig? instance}) {
    try {
      final values = (instance ?? FirebaseRemoteConfig.instance).getAll();
      configs = {
        for (final key in RemoteConfigKey.values)
          key.name: values[key.name]?.asString() ?? key.defaultValue,
      };
    } catch (_) {
      // The defaults are available before Firebase or platform channels are ready.
    } finally {
      if (kDebugMode) {
        for (final key in RemoteConfigKey.values) {
          debugPrint('[RemoteConfig] ${key.name} = ${getString(key)}');
        }
      }
    }
  }
}
