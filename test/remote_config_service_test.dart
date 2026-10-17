import 'dart:convert';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/config.dart' as built_in;
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';

class _Value extends RemoteConfigValue {
  _Value(String value) : super(utf8.encode(value), ValueSource.valueRemote);
}

class _Remote extends Fake implements FirebaseRemoteConfig {
  final calls = <String>[];
  Map<String, dynamic>? registeredDefaults;
  Map<String, String> activated = {}, fetched = {};
  bool offline = false, readFails = false;

  @override
  Future<void> setDefaults(Map<String, dynamic> defaults) async {
    calls.add('defaults');
    registeredDefaults = Map.of(defaults);
  }

  @override
  Future<void> ensureInitialized() async {
    calls.add('initialized');
  }

  @override
  Future<void> setConfigSettings(RemoteConfigSettings settings) async {
    calls.add('settings');
  }

  @override
  Future<bool> fetchAndActivate() async {
    calls.add('fetch');
    if (offline) throw StateError('offline');
    activated.addAll(fetched);
    return fetched.isNotEmpty;
  }

  @override
  Map<String, RemoteConfigValue> getAll() {
    calls.add('read');
    if (readFails) throw StateError('unavailable');
    return {
      for (final entry in activated.entries) entry.key: _Value(entry.value),
    };
  }
}

void main() {
  tearDown(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });

  test(
    'exported configuration matches supported parameter names and current defaults',
    () {
      final exported =
          jsonDecode(File('docs/remote_config_values.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        RemoteConfig.defaults.keys,
        unorderedEquals([
          'otp_api_url',
          'otp_api_token',
          'sadcaptcha_license_key',
          'search_keywords',
          'auto_comments',
        ]),
      );
      expect(exported.keys, unorderedEquals(RemoteConfig.defaults.keys));
      for (final key in RemoteConfigKey.values) {
        final value = exported[key.name];
        expect(value, isA<String>());
        if (key == RemoteConfigKey.search_keywords ||
            key == RemoteConfigKey.auto_comments) {
          expect(jsonDecode(value as String), jsonDecode(key.defaultValue));
        } else {
          expect(value, key.defaultValue);
        }
      }
    },
  );

  test(
    'registers defaults before fetch and supplies activated values to OTP and CAPTCHA',
    () async {
      final remote = _Remote()
        ..fetched = {
          'otp_api_url': 'https://remote.example.com/api/code',
          'otp_api_token': 'remote-token',
          'sadcaptcha_license_key': 'remote-captcha-key',
          'search_keywords': '["Travel", "Cà phê"]',
          'auto_comments': '["Great video!", "Cảm ơn ❤️"]',
        };
      await RemoteConfig.init(instance: remote);
      expect(remote.calls, [
        'defaults',
        'initialized',
        'settings',
        'fetch',
        'read',
      ]);
      expect(remote.registeredDefaults, RemoteConfig.defaults);
      final otp = await const OtpSettingsStore().load();
      expect(
        otp.toConfiguration().url.toString(),
        'https://remote.example.com/api/code',
      );
      expect(otp.toConfiguration().readerToken, 'remote-token');
      final captcha = CaptchaSettingsStore();
      expect((await captcha.load()).licenseKey, 'remote-captcha-key');
      captcha.dispose();
      final configuration = AppConfiguration.defaults('agent');
      expect(configuration.searchKeywords, ['Travel', 'Cà phê']);
      expect(configuration.comments, ['Great video!', 'Cảm ơn ❤️']);
    },
  );

  test('failed fetch still reads cached activated values', () async {
    final remote = _Remote()
      ..offline = true
      ..activated = {
        'otp_api_token': 'cached-token',
        'sadcaptcha_license_key': 'cached-key',
      };
    await RemoteConfig.init(instance: remote);
    expect(
      RemoteConfig.getString(RemoteConfigKey.otp_api_token),
      'cached-token',
    );
    expect(
      RemoteConfig.getString(RemoteConfigKey.sadcaptcha_license_key),
      'cached-key',
    );
    expect(
      RemoteConfig.getString(RemoteConfigKey.otp_api_url),
      RemoteConfigKey.otp_api_url.defaultValue,
    );
  });

  test('first offline launch uses defaults when nothing is cached', () async {
    await RemoteConfig.init(instance: _Remote()..offline = true);
    expect(RemoteConfig.configs, RemoteConfig.defaults);
  });

  test(
    'explicitly empty remote values do not fall back to built-in defaults',
    () async {
      await RemoteConfig.init(
        instance: _Remote()
          ..fetched = {'sadcaptcha_license_key': '', 'otp_api_token': ''},
      );
      expect(
        RemoteConfig.getString(RemoteConfigKey.sadcaptcha_license_key),
        isEmpty,
      );
      expect((await const OtpSettingsStore().load()).token, isEmpty);
    },
  );

  test('platform read failure keeps defaults available', () async {
    await RemoteConfig.init(instance: _Remote()..readFails = true);
    expect(RemoteConfig.configs, RemoteConfig.defaults);
  });

  test('list defaults are available before Firebase starts', () {
    RemoteConfig.configs = {};
    expect(RemoteConfig.searchKeywords, built_in.defaultSearchKeywords);
    expect(RemoteConfig.autoComments, built_in.defaultAutoComments);
  });

  test(
    'list parsing trims whitespace, removes blank entries and preserves Unicode',
    () {
      RemoteConfig.configs = {
        'search_keywords': '["  Cà phê  ", " ", "", "Travel"]',
        'auto_comments': '[" Cảm ơn ❤️ ", "", "Great video!"]',
      };
      expect(RemoteConfig.searchKeywords, ['Cà phê', 'Travel']);
      expect(RemoteConfig.autoComments, ['Cảm ơn ❤️', 'Great video!']);
      expect(
        () => RemoteConfig.autoComments.add('extra'),
        throwsUnsupportedError,
      );
    },
  );

  for (final value in [
    '',
    'invalid JSON',
    '{}',
    '"single string"',
    '["valid", 123]',
    'null',
  ]) {
    test('invalid list value $value falls back to built-in lists', () {
      RemoteConfig.configs = {'search_keywords': value, 'auto_comments': value};
      expect(RemoteConfig.searchKeywords, built_in.defaultSearchKeywords);
      expect(RemoteConfig.autoComments, built_in.defaultAutoComments);
    });
  }

  test(
    'explicit empty lists stay empty and configuration snapshots keep their values',
    () {
      RemoteConfig.configs = {
        'search_keywords': '["Travel"]',
        'auto_comments': '["Great video!"]',
      };
      final first = AppConfiguration.defaults('agent');
      RemoteConfig.configs = {'search_keywords': '[]', 'auto_comments': '[]'};
      final second = AppConfiguration.defaults('agent');
      expect(second.comments, isEmpty);
      expect(second.searchKeywords, isEmpty);
      expect(first.comments, ['Great video!']);
      expect(first.searchKeywords, ['Travel']);
    },
  );
}
