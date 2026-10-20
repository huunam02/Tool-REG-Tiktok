// ignore_for_file: constant_identifier_names
import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../config.dart' as built_in;

enum RemoteConfigKey {
  otp_api_url,

  /// PEM of the OTP server's self-signed certificate, trusted for the host of
  /// [otp_api_url] only. Empty when the server has a publicly trusted one.
  otp_api_certificate,
  sadcaptcha_license_key,
  search_keywords,
  auto_comments;

  String get defaultValue => switch (this) {
    otp_api_url => 'https://187.77.149.179:2001',
    otp_api_certificate => _otpApiCertificate,
    sadcaptcha_license_key => '406b433775d67e306eb3192ab99c344a',
    search_keywords => jsonEncode(built_in.defaultSearchKeywords),
    auto_comments => jsonEncode(built_in.defaultAutoComments),
  };
}

/// Self-signed certificate of the default OTP server (expires 2026-10-27).
/// Renewals are published through Remote Config, not a new build; see
/// docs/huong-dan-cau-hinh-firebase.md for the openssl command.
const _otpApiCertificate = '''
-----BEGIN CERTIFICATE-----
MIIDJDCCAgygAwIBAgIULOGy4QZKh3EAt4gdDhtFpyfkXLwwDQYJKoZIhvcNAQEL
BQAwGTEXMBUGA1UEAwwOMTg3Ljc3LjE0OS4xNzkwHhcNMjYxMDIwMDEzMTQxWhcN
MjYxMDI3MDEzMTQxWjAZMRcwFQYDVQQDDA4xODcuNzcuMTQ5LjE3OTCCASIwDQYJ
KoZIhvcNAQEBBQADggEPADCCAQoCggEBANOS4VVOd3me5EoJycdHAWrXncqwrpbx
DY7zer+ppbxtRDKISCdxxz+CVq8/o7RXu4y7Prx5X4hCGmcF4CCXEUKCnoncf5GL
AIRC9P5gLPQdlHKcyRmyRtnpWByU5UEf3hl3vris1+xW60INmEX658rUZ9Npj4ZP
sX2IPoYNVZ39lfJPqxYVLc4WYlkvgtVj+WygtPWcaeKsOvm06iD4wd90imJJ2Xet
6nnvYdTFetd8LQty9CEq9i8xVDcBpg2RyQf1u2tlMZ1rg/kCXAmxRZ8Yk4OyQxhn
EMLBuGVmfUsxbcoFUkiWGcOXWyiCnrZVXxdw+js9vDjvkxOkfDka7BsCAwEAAaNk
MGIwHQYDVR0OBBYEFGv1cUmaqBTUoscya8upwwmLv134MB8GA1UdIwQYMBaAFGv1
cUmaqBTUoscya8upwwmLv134MA8GA1UdEwEB/wQFMAMBAf8wDwYDVR0RBAgwBocE
u02VszANBgkqhkiG9w0BAQsFAAOCAQEAJfC34ZLdLd/RliNXnvnPDbPThvXhi6T2
hqqmyblRLb7lmuQnw6yTG3VwkM2kH8n+hWeXuuaCuLbvt8aTV9DO1Z1cip9koi3a
Y+9ABATnctqzIj7qSI+dXq/dRHafCrTzuE0MmBmBLU2gYno3MrsAvFRlBlxNVHfT
68O88G5Dxm/4gDjEjMz1SHr7V9KXgsGOwY3IDOJ6RMZZDqvlIhN+qRC67HeQeQjS
KfIKLV2SHSf1i9R4oSqH1mg98RFQ/+qZ/9UFMN2mRQ8RGHn+ippO+j8+7mavZnQk
FtS6j41rZLnsIBu+NYUmbh/0VtIuXRiJ39TdN8gOYdchoWVCdhCRuQ==
-----END CERTIFICATE-----
''';

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
