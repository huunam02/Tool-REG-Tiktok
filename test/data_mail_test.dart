import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';
import 'package:test_tiktok/core/controller/proxy_form_controller.dart';
import 'package:test_tiktok/core/data_file_export.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  const mail =
      r'person@example.com|mail-secret|refresh*9*!$+&=#?|client-id|alias@example.net';
  const proxy = '192.0.2.7:8080:user:pass';

  test('TXT derives the primary email and preserves all Data Mail parts', () {
    final row = ImportedConfiguration.parse('$proxy|$mail|TikTok-secret|1');
    expect(row.account.email, 'person@example.com');
    expect(row.account.dataMail, mail);
    expect(row.account.password, 'TikTok-secret');
    expect(row.statusAccount, AccountStatus.registered);
    expect(
      ImportedConfiguration.parse('$proxy|$mail|').account.password,
      isNotEmpty,
    );
    expect(
      () => ImportedConfiguration.parse(
        '$proxy|${mail.replaceFirst('person@example.com', 'invalid')}|password',
      ),
      throwsFormatException,
    );
  });

  test('Excel imports Data Mail without an Email or Mail Password column', () {
    final book = Excel.createExcel();
    book['Profiles'].appendRow([
      TextCellValue('Proxy'),
      TextCellValue('Data Mail'),
      TextCellValue('Password'),
      TextCellValue('Status'),
    ]);
    book['Profiles'].appendRow([
      TextCellValue(proxy),
      TextCellValue(mail),
      TextCellValue('TikTok-secret'),
      IntCellValue(1),
    ]);
    final rows = decodeConfigurationImportFile(
      ConfigurationImportFile('data.xlsx', Uint8List.fromList(book.encode()!)),
    );
    expect(rows.single.account.email, 'person@example.com');
    expect(rows.single.account.dataMail, mail);
    expect(rows.single.statusAccount, AccountStatus.registered);
  });

  test('export and reimport keep Data Mail and derive email from it', () {
    final account = ImportedConfiguration.parse('$proxy|$mail|TikTok-secret|1');
    final bytes = encodeDataExport(
      configurations: [
        SavedProxy(
          id: 1,
          name: 'test',
          proxy: account.proxy,
          userAgent: 'test',
          account: account.account,
          statusAccount: account.statusAccount,
        ),
      ],
      accounts: [],
    );
    final book = Excel.decodeBytes(bytes);
    final headers = book.tables.values.first.rows.first.map(
      (cell) => cell?.displayText,
    );
    expect(headers, contains('Data Mail'));
    expect(headers, isNot(contains('Mail Password')));
    final rows = decodeConfigurationImportFile(
      ConfigurationImportFile('data.xlsx', bytes),
    );
    expect(rows.single.account.dataMail, mail);
    expect(rows.single.account.email, 'person@example.com');
  });

  test('form derives email when Data Mail changes', () {
    final fields = ConfigurationFormFields();
    fields.mailboxPassword.text = mail;
    expect(fields.accountEmail.text, 'person@example.com');
    fields.mailboxPassword.text = mail.replaceFirst('person@', 'second@');
    expect(fields.accountEmail.text, 'second@example.com');
    fields.dispose();
  });

  test(
    'OTP GET encodes rawInput exactly and keeps secrets out of logs',
    () async {
      final logs = <String>[];
      final reader = OtpApiClient(
        OtpApiConfiguration(
          url: Uri.parse(
            'https://example.com:2001/api/extract-otp?rawInput=old',
          ),
        ),
        logOutput: logs.add,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/extract-otp');
          expect(request.url.queryParameters, {'rawInput': mail});
          expect(request.bodyBytes, isEmpty);
          expect(request.headers.containsKey('Content-Type'), isFalse);
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('X-Reader-Token'), isFalse);
          return http.Response(
            jsonEncode({'success': true, 'otp': '012345', 'rawInput': mail}),
            200,
          );
        }),
      );
      expect(
        await reader.fetchCode(email: 'person@example.com', password: mail),
        '012345',
      );
      expect(logs.join(), isNot(contains('mail-secret')));
      expect(logs.join(), isNot(contains('refresh*')));
      reader.close();
    },
  );

  test('Data Mail OTP asks again until the mail arrives', () async {
    var requests = 0;
    final reader = OtpApiClient(
      OtpApiConfiguration(
        url: Uri.parse('https://example.com:2001/api/extract-otp'),
        waitSeconds: 30,
      ),
      logOutput: (_) {},
      dataMailPollInterval: const Duration(milliseconds: 10),
      client: MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode(
            requests < 3
                ? {'success': false, 'message': 'No OTP found'}
                : {'success': true, 'otp': '654321'},
          ),
          200,
        );
      }),
    );
    expect(
      await reader.fetchCode(email: 'person@example.com', password: mail),
      '654321',
    );
    expect(requests, 3);
    reader.close();
  });

  test('Data Mail OTP times out when the mail never arrives', () async {
    final reader = OtpApiClient(
      OtpApiConfiguration(
        url: Uri.parse('https://example.com:2001/api/extract-otp'),
        waitSeconds: 1,
      ),
      logOutput: (_) {},
      dataMailPollInterval: const Duration(milliseconds: 200),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'success': false}), 200),
      ),
    );
    await expectLater(
      reader.fetchCode(email: 'person@example.com', password: mail),
      throwsA(
        isA<OtpApiException>().having((e) => e.timedOut, 'timedOut', isTrue),
      ),
    );
    reader.close();
  });

  test('Data Mail ignores older mail and previously rejected codes', () async {
    var requests = 0;
    final logs = <String>[];
    final reader = OtpApiClient(
      OtpApiConfiguration(
        url: Uri.parse('https://example.com/api/extract-otp'),
      ),
      notBefore: DateTime.utc(2026, 10, 22, 11, 20),
      rejectedCodes: {'111111'},
      dataMailPollInterval: const Duration(milliseconds: 1),
      logOutput: logs.add,
      client: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'success': true,
            'otp': requests == 3 ? '222222' : '111111',
            'receivedAt': requests == 1
                ? '2026-10-22T10:18:00Z'
                : '2026-10-22T11:21:00Z',
          }),
          200,
        );
      }),
    );
    expect(
      await reader.fetchCode(email: 'person@example.com', password: mail),
      '222222',
    );
    expect(requests, 3);
    expect(logs.join(), contains('staleCode'));
    expect(logs.join(), contains('rejectedCode'));
    expect(logs.join(), isNot(contains('111111')));
    expect(logs.join(), isNot(contains(mail)));
    reader.close();
  });
}
