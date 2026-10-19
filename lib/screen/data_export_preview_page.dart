import 'package:flutter/material.dart';

import '../core/data_file_export.dart';
import 'widgets/settings_style.dart';

/// Xem trước: the Data sheet exactly as Xuất Excel would save it. Pops `true`
/// when the user chooses to export from here.
class DataExportPreviewPage extends StatelessWidget {
  const DataExportPreviewPage({super.key, required this.preview});

  final DataExportPreview preview;

  static const _maxColumnWidth = 240.0;

  @override
  Widget build(BuildContext context) => Theme(
    data: SettingsStyle.theme(context),
    child: Scaffold(
      appBar: AppBar(title: const Text('Xem trước Excel')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                '${preview.configurationCount} cấu hình · '
                '${preview.accountCount} tài khoản nuôi · '
                '${preview.rows.length} hàng. Kéo ngang để xem đủ cột.',
                key: const Key('dataPreviewSummary'),
                style: const TextStyle(
                  color: SettingsStyle.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    key: const Key('dataPreviewTable'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(
                        SettingsStyle.surface,
                      ),
                      border: TableBorder.all(
                        color: SettingsStyle.border,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      columnSpacing: 20,
                      dataRowMaxHeight: 64,
                      columns: [
                        const DataColumn(label: Text('#')),
                        for (final header in DataExportPreview.headers)
                          DataColumn(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _maxColumnWidth,
                              ),
                              child: Text(
                                header,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                      rows: [
                        for (var i = 0; i < preview.rows.length; i++)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: SettingsStyle.muted,
                                  ),
                                ),
                              ),
                              for (final value in preview.rows[i])
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: _maxColumnWidth,
                                    ),
                                    child: Text(
                                      value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('exportFromPreview'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Xuất Excel'),
          ),
        ),
      ),
    ),
  );
}
