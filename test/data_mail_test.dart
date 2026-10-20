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
}
