import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'configuration_data.dart';
import 'data_excel_layout.dart';
import 'nurture_data.dart';
import 'proxy_store.dart';

Future<bool> saveDataExportFile(String name, Uint8List bytes) async {
  final result = await FilePicker.saveFile(
    dialogTitle: 'Lưu dữ liệu cấu hình và nuôi Account',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    bytes: bytes,
  );
  // Web downloads do not return a path.
  return kIsWeb || result != null;
}

Uint8List encodeDataExport({
  required List<SavedProxy> configurations,
  required List<NurtureAccount> accounts,
}) {
  final workbook = Excel.createExcel();
  workbook.rename('Sheet1', dataExcelSheetName);
  final sheet = workbook[dataExcelSheetName];
  _addHeaders(sheet, dataExcelHeaders);
  final accountsByEmail = {
    for (final account in accounts)
      if (nurtureAccountKey(account.email).isNotEmpty)
        nurtureAccountKey(account.email): account,
  };
  final exportedEmails = <String>{};
  for (final configuration in configurations) {
    final emailKey = nurtureAccountKey(configuration.account?.email ?? '');
    final account = accountsByEmail[emailKey];
    if (account != null) exportedEmails.add(emailKey);
    final proxy = configuration.proxy;
    final host = proxy?.uri.host ?? '';
    final proxyHost = host.contains(':') ? '[$host]' : host;
    sheet.appendRow([
      TextCellValue(
        proxy == null
            ? ''
            : '$proxyHost:${proxy.uri.port}:${proxy.username}:${proxy.password}',
      ),
      TextCellValue(configuration.account?.email ?? ''),
      TextCellValue(configuration.account?.password ?? ''),
      TextCellValue(configuration.account?.mailboxPassword ?? ''),
      IntCellValue(
        configuration.statusAccount == AccountStatus.registered ? 1 : 0,
      ),
      TextCellValue(configuration.userAgent),
      TextCellValue(configuration.timeZoneId),
      IntCellValue(configuration.hasBeenUsed ? 1 : 0),
      ..._nurtureCells(account),
    ]);
  }

  // Keep historical accounts even when their saved configuration was deleted.
  for (final account in accounts) {
    if (exportedEmails.contains(nurtureAccountKey(account.email))) continue;
    sheet.appendRow([
      null,
      TextCellValue(account.email),
      null,
      null,
      null,
      null,
      null,
      null,
      ..._nurtureCells(account),
    ]);
  }
  return Uint8List.fromList(workbook.encode()!);
}

List<CellValue> _nurtureCells(NurtureAccount? account) {
  final totals = account?.totals ?? const NurtureTotals();
  return [
    IntCellValue(totals.watchMilliseconds),
    DoubleCellValue(totals.minutes),
    IntCellValue(totals.videos),
    IntCellValue(totals.fullVideos),
    IntCellValue(totals.skippedVideos),
    IntCellValue(totals.comments),
    TextCellValue(account?.mode.label ?? ''),
    TextCellValue(account?.keyword ?? ''),
  ];
}

void _addHeaders(Sheet sheet, List<String> headers) {
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  for (var i = 0; i < headers.length; i++) {
    sheet.setColumnWidth(i, i == 0 ? 42 : 28);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .cellStyle = CellStyle(
      bold: true,
      textWrapping: TextWrapping.WrapText,
    );
  }
  sheet.setRowHeight(0, 32);
}
