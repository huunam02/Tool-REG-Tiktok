import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';
import 'package:xml/xml.dart';

void main() {
  const record = '192.0.2.7:8080:user:pass|person@example.com|tiktok|mail';

  test('TXT supports UTF-8 BOM, copied line endings and per-row status', () {
    final data = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'profiles.TXT',
        Uint8List.fromList(
          utf8.encode(
            '\uFEFF$record|1\r\n\n'
            '${record.replaceFirst('person@', 'second@')}|0',
          ),
        ),
      ),
    );
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
          ConfigurationImportFile('data.txt', bytes),
        ).single.account.email,
        'person@example.com',
      );
    }
  });

  test('Excel accepts complete lines, two columns and credential columns', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Profiles'];
    sheet.appendRow([
      TextCellValue('Proxy'),
      TextCellValue('Email'),
      TextCellValue('Password'),
      TextCellValue('Mail Password'),
    ]);
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
    sheet.appendRow([
      TextCellValue('192.0.2.10:8080:user:pass'),
      TextCellValue('fourth@example.com'),
      TextCellValue('tiktok-password'),
      TextCellValue('mail-password'),
    ]);
    final data = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'profiles.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    );
    expect(data, hasLength(4));
    expect(data.map((row) => row.statusAccount), [
      AccountStatus.registered,
      AccountStatus.unregistered,
      AccountStatus.registered,
      AccountStatus.unregistered,
    ]);
    expect(data[2].account.password, ' password with spaces ');
    expect(data[2].account.mailboxPassword, ' mailbox with spaces ');
    expect(data.last.account.email, 'fourth@example.com');
    expect(data.last.account.password, 'tiktok-password');
    expect(data.last.account.mailboxPassword, 'mail-password');
  });

  test(
    'Excel errors report the source sheet and row without a partial import',
    () {
      final workbook = Excel.createExcel();
      workbook['Profiles'].appendRow([TextCellValue(record)]);
      workbook['Profiles'].appendRow([TextCellValue('$record|2')]);
      expect(
        () => decodeConfigurationImportFile(
          ConfigurationImportFile(
            'bad.xlsx',
            Uint8List.fromList(workbook.encode()!),
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            startsWith('Sheet Profiles, dòng 2:'),
          ),
        ),
      );
    },
  );

  for (final prefixed in [false, true]) {
    for (final absoluteTargets in [false, true]) {
      for (final plainStrings in [false, true]) {
        test(
          'Excel accepts namespaces=$prefixed, absolute targets=$absoluteTargets, plain strings=$plainStrings',
          () {
            final workbook = Excel.createExcel();
            final sheet = workbook['Profiles'];
            sheet.appendRow([
              TextCellValue('Proxy'),
              TextCellValue('Email'),
              TextCellValue('Password'),
              TextCellValue('Mail Password'),
            ]);
            for (var index = 0; index < 3; index++) {
              sheet.appendRow([
                TextCellValue('192.0.2.7:8080:user:pass'),
                TextCellValue('person$index@example.com'),
                switch (index) {
                  0 => TextCellValue(''),
                  1 => TextCellValue('   '),
                  _ => null,
                },
                TextCellValue(' x:secret<&> '),
              ]);
            }
            final data = decodeConfigurationImportFile(
              ConfigurationImportFile(
                'profiles.xlsx',
                _excelVariant(
                  workbook.encode()!,
                  prefixed: prefixed,
                  absoluteTargets: absoluteTargets,
                  plainStrings: plainStrings,
                ),
              ),
            );
            expect(data, hasLength(3));
            for (var index = 0; index < data.length; index++) {
              expect(data[index].account.email, 'person$index@example.com');
              expect(
                data[index].account.password,
                matches(RegExp(r'^[A-Z][a-z]{5,9}[0-9]{2}[!@#$%^&*]$')),
              );
              expect(data[index].account.mailboxPassword, ' x:secret<&> ');
              expect(data[index].proxy!.username, 'user');
              expect(data[index].statusAccount, AccountStatus.unregistered);
            }
          },
        );
      }
    }
  }

  test('unsupported, corrupt and empty files are rejected', () {
    for (final file in [
      ConfigurationImportFile(
        'data.csv',
        Uint8List.fromList(utf8.encode(record)),
      ),
      ConfigurationImportFile('bad.xlsx', Uint8List.fromList([0, 1, 2])),
      ConfigurationImportFile('empty.txt', Uint8List(0)),
      ConfigurationImportFile(
        'empty.xlsx',
        Uint8List.fromList(Excel.createExcel().encode()!),
      ),
      ConfigurationImportFile('bad.txt', Uint8List.fromList([0xff, 0xfe, 1])),
    ]) {
      expect(() => decodeConfigurationImportFile(file), throwsFormatException);
    }
  });
}

Uint8List _excelVariant(
  List<int> bytes, {
  required bool prefixed,
  required bool absoluteTargets,
  required bool plainStrings,
}) {
  const namespace = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  final archive = ZipDecoder().decodeBytes(bytes);
  final sharedStrings = XmlDocument.parse(
    utf8.decode(archive.findFile('xl/sharedStrings.xml')!.content),
  ).findAllElements('si').map((item) => item.innerText).toList();
  for (final file in archive.files) {
    if (!file.name.endsWith('.xml') && !file.name.endsWith('.rels')) continue;
    var xml = utf8.decode(file.content);
    if (plainStrings && file.name.startsWith('xl/worksheets/')) {
      final document = XmlDocument.parse(xml);
      for (final cell in document.findAllElements('c')) {
        if (cell.getAttribute('t') != 's') continue;
        final value = cell.getElement('v')!;
        final text = sharedStrings[int.parse(value.innerText)];
        cell.setAttribute('t', 'str');
        value.children.clear();
        value.children.add(XmlText(text));
      }
      xml = document.toXmlString();
    }
    if (prefixed && xml.contains('xmlns="$namespace"')) {
      xml = xml.replaceAllMapped(
        RegExp(r'(<\/?)([A-Za-z][\w.-]*)(?=[\s/>])'),
        (match) => '${match[1]}x:${match[2]}',
      );
      xml = xml.replaceFirst('xmlns="$namespace"', 'xmlns:x="$namespace"');
    }
    if (absoluteTargets && file.name == 'xl/_rels/workbook.xml.rels') {
      final document = XmlDocument.parse(xml);
      for (final relation in document.findAllElements('Relationship')) {
        final target = relation.getAttribute('Target')!;
        if (!target.startsWith('/')) {
          relation.setAttribute('Target', '/xl/$target');
        }
      }
      xml = document.toXmlString();
    }
    final content = utf8.encode(xml);
    archive.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
