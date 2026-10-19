import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/proxy_form_controller.dart';
import 'package:test_tiktok/core/account_password.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  final format = RegExp(r'^[A-Z][a-z]{5,9}[0-9]{2}[!@#$%^&*]$');
  test(
    'generated passwords cover all allowed lengths and required characters',
    () {
      final random = Random(907);
      final passwords = List.generate(
        500,
        (_) => generateAccountPassword(random: random),
      );
      expect(passwords.every(format.hasMatch), isTrue);
      expect(passwords.map((value) => value.length).toSet(), {
        9,
        10,
        11,
        12,
        13,
      });
      expect(passwords.toSet().length, passwords.length);
    },
  );

  test(
    'new forms generate a password and editing preserves an existing password',
    () {
      final fresh = ConfigurationFormFields();
      expect(fresh.accountPassword.text, matches(format));
      final edit = ConfigurationFormFields(
        entry: const SavedProxy(
          id: 1,
          name: 'Existing',
          proxy: null,
          userAgent: 'agent',
          account: AccountCredentials(
            email: 'person@example.com',
            password: '  imported!  ',
            mailboxPassword: 'mail',
          ),
        ),
      );
      expect(edit.accountPassword.text, '  imported!  ');
      fresh.dispose();
      edit.dispose();
    },
  );

  test(
    'blank imported TikTok passwords generate while provided values remain exact',
    () {
      for (final supplied in ['', '   ', ' Actual-pAss_12 ']) {
        final value = ImportedConfiguration.parse(
          '192.0.2.7:8080:user:pass|person@example.com|$supplied|mail|1',
        );
        if (supplied.trim().isEmpty) {
          expect(value.account.password, matches(format));
        } else {
          expect(value.account.password, supplied);
        }
        expect(value.statusAccount, AccountStatus.registered);
        final fields = ConfigurationFormFields()..applyImport(value);
        expect(fields.accountPassword.text, value.account.password);
        fields.dispose();
      }
    },
  );
}
