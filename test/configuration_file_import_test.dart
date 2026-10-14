import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';

void main() {
  const record = '192.0.2.7:8080:user:pass person@example.com|tiktok|mail';

  test('TXT supports UTF-8 BOM, copied line endings and per-row status', () {
    final data = decodeConfigurationImportFile(ConfigurationImportFile(
      'profiles.TXT',
      Uint8List.fromList(utf8.encode('\uFEFF$record|1\r\n\n'
          '${record.replaceFirst('person@', 'second@')}|0')),
    ));
    expect(data, hasLength(2));
    expect(data.first.statusAccount, AccountStatus.registered);
    expect(data.last.statusAccount, AccountStatus.unregistered);
  });

  test('TXT supports little- and big-endian UTF-16', () {
    for (final littleEndian in [true, false]) {
      final units = record.codeUnits;
      final bytes = Uint8List.fromList([
        if (littleEndian) ...[0xff, 0xfe] else ...[0xfe, 0xff],
        for (final unit in units)
          ...littleEndian ? [unit & 0xff, unit >> 8] : [unit >> 8, unit & 0xff],
      ]);
      expect(
          decodeConfigurationImportFile(
                  ConfigurationImportFile('data.txt', bytes))
              .single
              .account
              .email,
          'person@example.com');
    }
  });

  test('Excel accepts complete lines, two columns and credential columns', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Profiles'];
    sheet.appendRow([TextCellValue('Proxy'), TextCellValue('Email')]);
    sheet.appendRow([TextCellValue('$record|1')]);
    sheet.appendRow([
      TextCellValue('192.0.2.8:8080:user:pass'),
      TextCellValue('second@example.com|tiktok|mail|0'),
    ]);
    sheet.appendRow([
      TextCellValue('192.0.2.9:8080:user:pass'),
      TextCellValue('third@example.com'),
      TextCellValue(' password with spaces '),
      TextCellValue(' mailbox with spaces '),
      IntCellValue(1),
    ]);
    final data = decodeConfigurationImportFile(ConfigurationImportFile(
      'profiles.xlsx',
      Uint8List.fromList(workbook.encode()!),
    ));
    expect(data, hasLength(3));
    expect(data.map((row) => row.statusAccount), [
      AccountStatus.registered,
      AccountStatus.unregistered,
      AccountStatus.registered,
    ]);
    expect(data.last.account.password, ' password with spaces ');
    expect(data.last.account.mailboxPassword, ' mailbox with spaces ');
  });

  test('Excel errors report the source sheet and row without a partial import',
      () {
    final workbook = Excel.createExcel();
    workbook['Profiles'].appendRow([TextCellValue(record)]);
    workbook['Profiles'].appendRow([TextCellValue('$record|2')]);
    expect(
      () => decodeConfigurationImportFile(ConfigurationImportFile(
        'bad.xlsx',
        Uint8List.fromList(workbook.encode()!),
      )),
      throwsA(isA<FormatException>().having((error) => error.message, 'message',
          startsWith('Sheet Profiles, dòng 2:'))),
    );
  });

  test('unsupported, corrupt and empty files are rejected', () {
    for (final file in [
      ConfigurationImportFile(
          'data.csv', Uint8List.fromList(utf8.encode(record))),
      ConfigurationImportFile('bad.xlsx', Uint8List.fromList([0, 1, 2])),
      ConfigurationImportFile('empty.txt', Uint8List(0)),
      ConfigurationImportFile(
          'empty.xlsx', Uint8List.fromList(Excel.createExcel().encode()!)),
      ConfigurationImportFile('bad.txt', Uint8List.fromList([0xff, 0xfe, 1])),
    ]) {
      expect(() => decodeConfigurationImportFile(file), throwsFormatException);
    }
  });
}
