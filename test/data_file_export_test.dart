import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';
import 'package:test_tiktok/core/data_excel_layout.dart';
import 'package:test_tiktok/core/data_file_export.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/proxy_store.dart';

void main() {
  final configuration = SavedProxy(
    id: 12,
    name: 'Cấu hình thử nghiệm',
    proxy: WebViewProxy.parseImport('192.0.2.7:8080:00123:pass:word'),
    userAgent: 'test-agent',
    timeZoneId: 'Asia/Ho_Chi_Minh',
    hasBeenUsed: true,
    account: const AccountCredentials(
      email: 'person@example.com',
      password: ' =secret ',
      mailboxPassword: ' 00123 ',
    ),
    statusAccount: AccountStatus.registered,
  );

  test('exports only the requested columns and preserves credential text', () {
    final workbook = Excel.decodeBytes(
      encodeDataExport(configurations: [configuration], accounts: []),
    );
    expect(workbook.tables.keys, [dataExcelSheetName]);
    final rows = workbook[dataExcelSheetName].rows;
    expect(rows.first.map((cell) => cell?.displayText), dataExcelHeaders);
    expect(rows.first.map((cell) => cell?.displayText), [
      'Proxy',
      'Email',
      'Password',
      'Mail Password',
      'status(Đã dăng ký)',
      'User-Agent',
      'Múi giờ',
      'Đã sử dụng',
      'Thời gian xem (ms)',
      'Phút xem',
      'Video đã xem',
      'Video xem hết',
      'Video lướt sớm',
      'Bình luận',
      'Chế độ',
      'Từ khóa',
    ]);
    expect(
      rows[1]
          .take(configurationExcelHeaders.length)
          .map((cell) => cell?.displayText),
      [
        '192.0.2.7:8080:00123:pass:word',
        'person@example.com',
        ' =secret ',
        ' 00123 ',
        '1',
        'test-agent',
        'Asia/Ho_Chi_Minh',
        '1',
      ],
    );
    expect(rows[1][2]!.value, isA<TextCellValue>());
    expect(rows[1][3]!.value, isA<TextCellValue>());
    expect(rows[1][4]!.value, isA<IntCellValue>());
    expect(rows[1][8]!.value, IntCellValue(0));
    expect(rows[1], hasLength(16));
  });

  test(
    'exported workbook imports credentials and status without report rows',
    () {
      final records = decodeConfigurationImportFile(
        ConfigurationImportFile(
          'export.xlsx',
          encodeDataExport(
            configurations: [configuration],
            accounts: const [
              NurtureAccount(
                key: 'deleted@example.com',
                email: 'deleted@example.com',
              ),
            ],
          ),
        ),
      );
      expect(records, hasLength(1));
      expect(sameProxy(records.single.proxy, configuration.proxy), isTrue);
      expect(
        sameAccount(records.single.account, configuration.account),
        isTrue,
      );
      expect(records.single.statusAccount, AccountStatus.registered);
    },
  );

  test(
    'exports all nurture totals and accounts without a saved configuration',
    () {
      final updated = DateTime.utc(2026, 10, 17, 2, 30);
      final workbook = Excel.decodeBytes(
        encodeDataExport(
          configurations: [configuration],
          accounts: [
            NurtureAccount(
              key: 'person@example.com',
              email: 'person@example.com',
              configurationId: 12,
              configurationName: 'Cấu hình thử nghiệm',
              totals: const NurtureTotals(
                watchMilliseconds: 90001,
                videos: 5,
                fullVideos: 2,
                skippedVideos: 3,
                comments: 4,
              ),
              mode: NurtureMode.search,
              keyword: '=Du lịch',
              phase: 'completed',
              updatedAt: updated,
            ),
            const NurtureAccount(
              key: 'deleted@example.com',
              email: 'deleted@example.com',
            ),
          ],
        ),
      );
      final rows = workbook[dataExcelSheetName].rows;
      expect(rows, hasLength(3));
      expect(rows.first.map((cell) => cell?.displayText), dataExcelHeaders);
      expect(rows[1][1]!.displayText, 'person@example.com');
      expect(rows[1][8]!.value, IntCellValue(90001));
      expect(
        (rows[1][9]!.value as DoubleCellValue).value,
        closeTo(90001 / 60000, 1e-10),
      );
      expect(rows[1].skip(10).take(4).map((cell) => cell?.displayText), [
        '5',
        '2',
        '3',
        '4',
      ]);
      expect(rows[1][14]!.displayText, NurtureMode.search.label);
      expect(rows[1][15]!.value, isA<TextCellValue>());
      expect(rows[1][15]!.displayText, '=Du lịch');
      expect(rows[2][1]!.displayText, 'deleted@example.com');
      for (final column in [0, 2, 3, 4, 5]) {
        expect(rows[2][column]?.displayText ?? '', '');
      }
      expect(rows[2][8]!.value, IntCellValue(0));
    },
  );

  test(
    'exports configurations without accounts or proxy without dropping them',
    () {
      final workbook = Excel.decodeBytes(
        encodeDataExport(
          configurations: [
            const SavedProxy(
              id: 1,
              name: 'Direct',
              proxy: null,
              userAgent: 'agent',
            ),
          ],
          accounts: [],
        ),
      );
      final row = workbook[dataExcelSheetName].rows[1];
      expect(row[0]?.displayText ?? '', '');
      expect(row[1]?.displayText ?? '', '');
      expect(row[4]!.displayText, '0');
      expect(row[5]!.displayText, 'agent');
    },
  );

  test(
    'joins by normalized email and preserves configurations sharing an account',
    () {
      final workbook = Excel.decodeBytes(
        encodeDataExport(
          configurations: [
            configuration,
            SavedProxy(
              id: 13,
              name: 'Second configuration',
              proxy: configuration.proxy,
              userAgent: 'second-agent',
              account: configuration.account,
            ),
          ],
          accounts: const [
            NurtureAccount(
              key: 'person@example.com',
              email: ' PERSON@EXAMPLE.COM ',
              configurationId: 13,
              totals: NurtureTotals(videos: 5, fullVideos: 5),
            ),
            NurtureAccount(
              key: 'other@example.com',
              email: 'other@example.com',
              configurationId: 12,
              totals: NurtureTotals(videos: 9, fullVideos: 9),
            ),
          ],
        ),
      );
      final rows = workbook[dataExcelSheetName].rows;
      expect(rows, hasLength(4));
      expect(rows[1][5]!.displayText, 'test-agent');
      expect(rows[2][5]!.displayText, 'second-agent');
      expect(rows[1][10]!.displayText, '5');
      expect(rows[2][10]!.displayText, '5');
      expect(rows[3][1]!.displayText, 'other@example.com');
      expect(rows[3][10]!.displayText, '9');
    },
  );

  test('nurture-only export retains every account in the single sheet', () {
    final workbook = Excel.decodeBytes(
      encodeDataExport(
        configurations: [],
        accounts: const [
          NurtureAccount(key: 'first@example.com', email: 'first@example.com'),
          NurtureAccount(
            key: 'second@example.com',
            email: 'second@example.com',
          ),
        ],
      ),
    );
    expect(workbook.tables.keys, [dataExcelSheetName]);
    final rows = workbook[dataExcelSheetName].rows;
    expect(rows, hasLength(3));
    expect(rows[1][1]!.displayText, 'first@example.com');
    expect(rows[2][1]!.displayText, 'second@example.com');
  });

  test('previous two-sheet exports still import', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Cau hinh');
    workbook['Cau hinh'].appendRow(
      legacyConfigurationExcelHeaders.map(TextCellValue.new).toList(),
    );
    workbook['Cau hinh'].appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(1),
      IntCellValue(12),
    ]);
    workbook[nurtureExcelSheetName].appendRow(
      nurtureExcelHeaders.map(TextCellValue.new).toList(),
    );
    workbook[nurtureExcelSheetName].appendRow([
      TextCellValue('person@example.com'),
    ]);
    final records = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'legacy.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    );
    expect(records, hasLength(1));
    expect(records.single.account.email, 'person@example.com');
    expect(records.single.statusAccount, AccountStatus.registered);
  });

  test(
    'an unrelated sheet named Nuoi acc still receives import validation',
    () {
      final workbook = Excel.createExcel();
      workbook[nurtureExcelSheetName].appendRow([
        TextCellValue('invalid record'),
      ]);
      expect(
        () => decodeConfigurationImportFile(
          ConfigurationImportFile(
            'invalid.xlsx',
            Uint8List.fromList(workbook.encode()!),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test('previous combined exports still import and skip nurture-only rows', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', dataExcelSheetName);
    final sheet = workbook[dataExcelSheetName];
    sheet.appendRow(legacyDataExcelHeaders.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(0),
      IntCellValue(12),
      TextCellValue('Previous configuration'),
    ]);
    sheet.appendRow([
      null,
      TextCellValue('deleted@example.com'),
      for (var i = 2; i < 11; i++) null,
      IntCellValue(90000),
    ]);
    final records = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'previous.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    );
    expect(records, hasLength(1));
    expect(records.single.account.email, 'person@example.com');
    expect(records.single.statusAccount, AccountStatus.unregistered);
  });
}
