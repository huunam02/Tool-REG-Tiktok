import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import 'configuration_data.dart';
import 'account_password.dart';
import 'app_configuration.dart';
import 'data_excel_layout.dart';
import 'gpu_profile.dart';
import 'nurture_data.dart';

class ConfigurationImportFile {
  const ConfigurationImportFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

Future<ConfigurationImportFile?> pickConfigurationImportFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'txt'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  return ConfigurationImportFile(
    file.name,
    file.bytes ?? await file.xFile.readAsBytes(),
  );
}

List<ImportedConfiguration> decodeConfigurationImportFile(
  ConfigurationImportFile file,
) {
  switch (path.extension(file.name).toLowerCase()) {
    case '.txt':
      return ImportedConfiguration.parseMany(_decodeText(file.bytes));
    case '.xlsx':
    case '.xls':
      return _decodeExcel(file.bytes);
    default:
      throw const FormatException('Chọn file Excel (.xlsx, .xls) hoặc TXT.');
  }
}

String _decodeText(Uint8List bytes) {
  if (bytes.length >= 2 &&
      (bytes[0] == 0xff && bytes[1] == 0xfe ||
          bytes[0] == 0xfe && bytes[1] == 0xff)) {
    if (bytes.length.isOdd) {
      throw const FormatException('File TXT Unicode không hợp lệ.');
    }
    final littleEndian = bytes[0] == 0xff;
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | bytes[i + 1] << 8
            : bytes[i] << 8 | bytes[i + 1],
    ]);
  }
  try {
    return utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
  } on FormatException {
    throw const FormatException('File TXT cần dùng UTF-8 hoặc Unicode UTF-16.');
  }
}

List<ImportedConfiguration> _decodeExcel(Uint8List bytes) {
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(_normalizeExcelXml(bytes));
  } catch (_) {
    throw const FormatException(
      'Không đọc được file Excel. Kiểm tra lại file.',
    );
  }
  final records = <ImportedConfiguration>[];
  for (final sheet in workbook.tables.entries) {
    final rows = sheet.value.rows;
    final headers = rows.isEmpty
        ? <String>[]
        : rows.first.map((cell) => cell?.displayText ?? '').toList();
    // The exported statistics are a report, not extra configurations.
    if (sheet.key == nurtureExcelSheetName &&
        matchesExcelHeaders(headers, nurtureExcelHeaders)) {
      continue;
    }
    final columns = {
      for (var i = 0; i < headers.length; i++) headers[i].trim(): i,
    };
    // Exports since Cấu hình nuôi start with the configuration columns and
    // carry its columns; other columns are found by header or ignored.
    final withNurtureSettings =
        columns.containsKey('Proxy') &&
        columns.containsKey('Password') &&
        (columns.containsKey('Data Mail') ||
            columns.containsKey('Mail Password')) &&
        nurtureSettingsExcelHeaders.every(columns.containsKey);
    final combinedExport =
        withNurtureSettings ||
        matchesExcelHeaders(headers, previousDataExcelHeaders) ||
        matchesExcelHeaders(headers, legacyDataExcelHeaders);
    final exportedConfiguration =
        combinedExport ||
        matchesExcelHeaders(headers, configurationExcelHeaders) ||
        matchesExcelHeaders(headers, legacyConfigurationExcelHeaders);
    for (var index = 0; index < rows.length; index++) {
      final cells = rows[index].map((cell) => cell?.displayText ?? '').toList();
      while (cells.isNotEmpty && cells.last.trim().isEmpty) {
        cells.removeLast();
      }
      if (cells.isEmpty) continue;
      if (index == 0 &&
          [
            'proxy',
            'data',
            'dữ liệu',
          ].contains(cells.first.trim().toLowerCase())) {
        continue;
      }
      try {
        // A historical account can have statistics but no saved credentials.
        if (combinedExport &&
            cells.length >= 5 &&
            [0, 2, 3, 4].every((column) => cells[column].trim().isEmpty)) {
          continue;
        }
        final nurtureSettings = withNurtureSettings
            ? _readNurtureSettings(cells, columns)
            : null;
        final gpuProfileId = withNurtureSettings
            ? _readGpuProfile(cells, columns)
            : null;
        // Header-based import keeps Data Mail in one cell even though it
        // contains pipes. Email is always derived from this cell.
        if (columns.containsKey('Data Mail')) {
          String read(String name) {
            final column = columns[name];
            return column != null && column < cells.length ? cells[column] : '';
          }

          final status = read('status(Đã dăng ký)').isNotEmpty
              ? read('status(Đã dăng ký)')
              : read('Status');
          final dataMail = read('Data Mail');
          if (dataMail.trim().isEmpty && read('Proxy').trim().isEmpty) continue;
          // Saved accounts from the old layout may only have a mail password.
          final legacy =
              !dataMail.contains('|') && columns.containsKey('Email');
          final record = legacy
              ? ImportedConfiguration(
                  proxy: WebViewProxy.parseImport(read('Proxy')),
                  account: AccountCredentials(
                    email: read('Email'),
                    password: read('Password').trim().isEmpty
                        ? generateAccountPassword()
                        : read('Password'),
                    mailboxPassword: dataMail,
                  ),
                  statusAccount: switch (status.trim()) {
                    '' || '0' => AccountStatus.unregistered,
                    '1' => AccountStatus.registered,
                    _ => throw const FormatException(
                      'Trạng thái đăng ký phải là 0 hoặc 1.',
                    ),
                  },
                )
              : ImportedConfiguration.parse(
                  '${read('Proxy')}|$dataMail|${read('Password')}${status.isEmpty ? '' : '|$status'}',
                );
          record.account.validate();
          records.add(
            record.copyWith(
              nurtureSettings: nurtureSettings,
              gpuProfileId: gpuProfileId,
            ),
          );
          continue;
        }
        // Additional exported configuration columns are for reference only.
        if (exportedConfiguration && cells.length > 5) {
          cells.removeRange(5, cells.length);
        }
        final line = switch (cells.length) {
          1 => cells.first,
          2 || 3 || 4 || 5 => cells.join('|'),
          _ => throw const FormatException(
            'Mỗi dòng Excel cần một ô dữ liệu, hai cột proxy/tài khoản, '
            'hoặc các cột Proxy, Data Mail, Password, Status (không bắt buộc).',
          ),
        };
        records.add(
          ImportedConfiguration.parse(line).copyWith(
            nurtureSettings: nurtureSettings,
            gpuProfileId: gpuProfileId,
          ),
        );
      } on FormatException catch (error) {
        throw FormatException(
          'Sheet ${sheet.key}, dòng ${index + 1}: ${error.message}',
        );
      }
    }
  }
  if (records.isEmpty) {
    throw const FormatException('File Excel không có dữ liệu cấu hình.');
  }
  return records;
}

// excel_community expects unprefixed SpreadsheetML elements and relative
// workbook relationship targets, and treats plain t="str" cells as formulas.
// Normalize these valid XLSX variants in memory before passing to the reader.
List<int> _normalizeExcelXml(Uint8List bytes) {
  // Leave legacy binary XLS to the library's own decoder.
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
    return bytes;
  }
  const spreadsheetNamespace =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  final archive = ZipDecoder().decodeBytes(bytes);
  var changed = false;
  for (final file in archive.files) {
    if (!file.name.startsWith('xl/') ||
        !(file.name.endsWith('.xml') ||
            file.name == 'xl/_rels/workbook.xml.rels')) {
      continue;
    }
    final document = XmlDocument.parse(utf8.decode(file.content));
    var fileChanged = false;
    // Reverse order keeps original namespace declarations available while
    // replacing children before their parents.
    final elements = document.descendants.whereType<XmlElement>().toList();
    for (final element in elements.reversed) {
      if (element.name.prefix != null &&
          element.name.namespaceUri == spreadsheetNamespace) {
        final replacement = XmlElement(
          XmlName.parts(element.name.local),
          element.attributes.map((attribute) => attribute.copy()),
          element.children.map((child) => child.copy()),
          element.isSelfClosing,
        );
        if (element == document.rootElement) {
          replacement.setAttribute('xmlns', spreadsheetNamespace);
        }
        element.replace(replacement);
        fileChanged = true;
      }
    }
    if (file.name.startsWith('xl/worksheets/')) {
      for (final cell in document.findAllElements('c')) {
        if (cell.getAttribute('t') != 'str' || cell.getElement('f') != null) {
          continue;
        }
        final value = cell.getElement('v');
        if (value == null) continue;
        cell.setAttribute('t', 'inlineStr');
        value.replace(
          XmlElement(XmlName.parts('is'), [], [
            XmlElement(XmlName.parts('t'), [], [XmlText(value.innerText)]),
          ]),
        );
        fileChanged = true;
      }
    }
    if (file.name == 'xl/_rels/workbook.xml.rels') {
      for (final relationship in document.findAllElements('Relationship')) {
        final target = relationship.getAttribute('Target');
        if (relationship.getAttribute('TargetMode') != 'External' &&
            target != null &&
            target.startsWith('/')) {
          relationship.setAttribute(
            'Target',
            path.posix.relative(target, from: '/xl'),
          );
          fileChanged = true;
        }
      }
    }
    if (fileChanged) {
      final content = utf8.encode(document.toXmlString());
      archive.addFile(ArchiveFile(file.name, content.length, content));
      changed = true;
    }
  }
  return changed ? ZipEncoder().encode(archive) : bytes;
}

/// Cấu hình nuôi columns of a combined export row; empty cells use the
/// defaults.
NurtureSettings _readNurtureSettings(
  List<String> cells,
  Map<String, int> columns,
) {
  const d = NurtureSettings.defaults;
  int read(int offset, int fallback) {
    final index = columns[nurtureSettingsExcelHeaders[offset]]!;
    final text = index < cells.length
        ? cells[index].trim().replaceFirst(RegExp(r'\s*%$'), '')
        : '';
    if (text.isEmpty) return fallback;
    final value = int.tryParse(text) ?? double.tryParse(text)?.round();
    if (value == null) {
      throw FormatException(
        'Cột "${nurtureSettingsExcelHeaders[offset]}" phải là số nguyên.',
      );
    }
    return value;
  }

  final settings = NurtureSettings(
    likePercent: read(0, d.likePercent),
    commentPercent: read(1, d.commentPercent),
    longWatchPercent: read(2, d.longWatchPercent),
    minMinutes: read(3, d.minMinutes),
    maxMinutes: read(4, d.maxMinutes),
  );
  final error = settings.error;
  if (error != null) throw FormatException(error);
  return settings;
}

/// The Thiết bị GPU cell (id or device name); null when absent or empty.
String? _readGpuProfile(List<String> cells, Map<String, int> columns) {
  final index = columns[gpuProfileExcelHeader];
  final text = index != null && index < cells.length ? cells[index] : '';
  if (text.trim().isEmpty) return null;
  final profile = GpuProfile.find(text);
  if (profile == null) {
    throw FormatException(
      'Cột "$gpuProfileExcelHeader": không có thiết bị "${text.trim()}".',
    );
  }
  return profile.id;
}
