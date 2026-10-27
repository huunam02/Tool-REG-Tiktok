import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';
import 'package:test_tiktok/core/data_excel_layout.dart';
import 'package:test_tiktok/core/data_file_export.dart';
import 'package:test_tiktok/core/firefox_user_agent.dart';
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
      'Data Mail',
      'Password',
      'status(Đã dăng ký)',
      'User-Agent',
      'Múi giờ',
      'Đã sử dụng',
      'Thiết bị GPU',
      'Tỷ lệ thả tim (%)',
      'Tỷ lệ bình luận (%)',
      'Tỷ lệ xem lâu (%)',
      'Nuôi tối thiểu (phút)',
      'Nuôi tối đa (phút)',
      'Thời gian xem (ms)',
      'Phút xem',
      'Video đã xem',
      'Video xem hết',
      'Video lướt sớm',
      'Bình luận',
    ]);
    expect(
      rows[1]
          .take(configurationExcelHeaders.length)
          .map((cell) => cell?.displayText),
      [
        '192.0.2.7:8080:00123:pass:word',
        'person@example.com',
        ' 00123 ',
        ' =secret ',
        '1',
        'test-agent',
        'Asia/Ho_Chi_Minh',
        '1',
      ],
    );
    expect(rows[1][2]!.value, isA<TextCellValue>());
    expect(rows[1][3]!.value, isA<TextCellValue>());
    expect(rows[1][4]!.value, isA<IntCellValue>());
    expect(rows[1].skip(9).take(5).map((cell) => cell?.displayText), [
      '30',
      '20',
      '50',
      '2',
      '3',
    ]);
    expect(rows[1][14]!.value, IntCellValue(0));
    expect(rows[1], hasLength(20));
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

  test('a configuration without proxy round-trips as Mặc định của máy', () {
    final records = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'export.xlsx',
        encodeDataExport(
          configurations: [
            SavedProxy(
              id: 14,
              name: 'Không proxy',
              proxy: null,
              userAgent: 'test-agent',
              account: configuration.account,
            ),
          ],
          accounts: const [],
        ),
      ),
    );
    expect(records, hasLength(1));
    expect(records.single.proxy, isNull);
    expect(sameAccount(records.single.account, configuration.account), isTrue);
  });

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
      expect(rows[1][14]!.value, IntCellValue(90001));
      expect(
        (rows[1][15]!.value as DoubleCellValue).value,
        closeTo(90001 / 60000, 1e-10),
      );
      expect(rows[1].skip(16).take(4).map((cell) => cell?.displayText), [
        '5',
        '2',
        '3',
        '4',
      ]);
      // Mode and keyword are random per session and not exported.
      expect(rows[1], hasLength(20));
      expect(
        rows[1].map((cell) => cell?.displayText),
        isNot(contains('=Du lịch')),
      );
      expect(rows[2][1]!.displayText, 'deleted@example.com');
      for (final column in [0, 2, 3, 4, 5]) {
        expect(rows[2][column]?.displayText ?? '', '');
      }
      expect(rows[2][14]!.value, IntCellValue(0));
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
      expect(rows[1][16]!.displayText, '5');
      expect(rows[2][16]!.displayText, '5');
      expect(rows[3][1]!.displayText, 'other@example.com');
      expect(rows[3][16]!.displayText, '9');
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

  test('each configuration\'s Cấu hình nuôi survives export and import', () {
    const custom = NurtureSettings(
      likePercent: 45,
      commentPercent: 5,
      longWatchPercent: 70,
      minMinutes: 10,
      maxMinutes: 20,
    );
    final records = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'backup.xlsx',
        encodeDataExport(
          configurations: [
            configuration,
            SavedProxy(
              id: 13,
              name: 'Second',
              proxy: configuration.proxy,
              userAgent: 'second-agent',
              account: const AccountCredentials(
                email: 'second@example.com',
                password: 'secret',
                mailboxPassword: 'mail',
              ),
              nurtureSettings: custom,
            ),
          ],
          accounts: const [],
        ),
      ),
    );
    expect(records.map((record) => record.nurtureSettings), [
      NurtureSettings.defaults,
      custom,
    ]);
  });

  test('an export with the old Chế độ/Từ khóa columns still imports', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', dataExcelSheetName);
    final sheet = workbook[dataExcelSheetName];
    sheet.appendRow(
      [
        ...configurationExcelHeaders,
        ...nurtureSettingsExcelHeaders,
        ...legacyNurtureStatisticsExcelHeaders,
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(1),
      TextCellValue('agent'),
      TextCellValue(''),
      IntCellValue(0),
      IntCellValue(45),
      IntCellValue(5),
      IntCellValue(70),
      IntCellValue(10),
      IntCellValue(20),
      for (var i = 0; i < 6; i++) IntCellValue(0),
      TextCellValue(NurtureMode.search.label),
      TextCellValue('Du lịch'),
    ]);
    final record = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'mode.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    ).single;
    expect(record.account.email, 'person@example.com');
    expect(
      record.nurtureSettings,
      const NurtureSettings(
        likePercent: 45,
        commentPercent: 5,
        longWatchPercent: 70,
        minMinutes: 10,
        maxMinutes: 20,
      ),
    );
  });

  test('a backup that still has a Local IP column imports without it', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', dataExcelSheetName);
    final sheet = workbook[dataExcelSheetName];
    sheet.appendRow(
      [
        ...configurationExcelHeaders,
        'Local IP',
        ...nurtureSettingsExcelHeaders,
        ...nurtureStatisticsExcelHeaders,
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(1),
      null,
      null,
      null,
      TextCellValue('10.9.8.7'),
      IntCellValue(45),
    ]);
    final record = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'local-ip.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    ).single;
    expect(record.account.email, 'person@example.com');
    expect(record.nurtureSettings!.likePercent, 45);
  });

  test('Thiết bị GPU exports the desktop GPU and import ignores it', () {
    final bytes = encodeDataExport(
      configurations: [
        SavedProxy(
          id: 15,
          name: 'GPU',
          proxy: configuration.proxy,
          userAgent: 'agent',
          account: const AccountCredentials(
            email: 'gpu@example.com',
            password: 'secret',
            mailboxPassword: 'mail',
          ),
        ),
      ],
      accounts: const [],
    );
    final rows = Excel.decodeBytes(bytes)[dataExcelSheetName].rows;
    expect(rows[0][8]!.displayText, gpuProfileExcelHeader);
    expect(rows[1][8]!.displayText, firefoxDesktopGpuLabel);
    expect(
      decodeConfigurationImportFile(
        ConfigurationImportFile('gpu.xlsx', bytes),
      ).single.account.email,
      'gpu@example.com',
    );
  });

  test('an older export with a phone GPU still imports', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', dataExcelSheetName);
    final sheet = workbook[dataExcelSheetName];
    sheet.appendRow(dataExcelHeaders.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(1),
      null,
      null,
      null,
      TextCellValue('galaxy-s23'),
    ]);
    final record = decodeConfigurationImportFile(
      ConfigurationImportFile(
        'gpu.xlsx',
        Uint8List.fromList(workbook.encode()!),
      ),
    ).single;
    expect(record.account.email, 'person@example.com');
    expect(record.statusAccount, AccountStatus.registered);
  });

  test('an invalid Cấu hình nuôi cell names the column', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', dataExcelSheetName);
    final sheet = workbook[dataExcelSheetName];
    sheet.appendRow(dataExcelHeaders.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('192.0.2.7:8080:user:pass'),
      TextCellValue('person@example.com'),
      TextCellValue('secret'),
      TextCellValue('mail'),
      IntCellValue(1),
      null,
      null,
      null,
      null,
      TextCellValue('nhiều'),
    ]);
    expect(
      () => decodeConfigurationImportFile(
        ConfigurationImportFile(
          'invalid.xlsx',
          Uint8List.fromList(workbook.encode()!),
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Tỷ lệ thả tim (%)'),
        ),
      ),
    );
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
