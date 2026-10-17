import 'dart:async';

import 'package:excel_community/excel_community.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/data_excel_layout.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/screen/home_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

  Future<MemoryProxyStore> seed() async {
    final store = MemoryProxyStore();
    await store.save(
      name: 'Saved configuration',
      proxy: null,
      userAgent: 'agent',
      account: const AccountCredentials(
        email: 'person@example.com',
        password: 'secret',
        mailboxPassword: 'mail',
      ),
    );
    await store.nurture.beginSession(
      id: 'session',
      email: 'person@example.com',
      plan: const NurturePlan(NurtureMode.feed),
      phase: 'stopped',
    );
    await store.nurture.saveProgress(
      'session',
      1,
      const NurtureTotals(videos: 2, fullVideos: 2),
    );
    return store;
  }

  Future<void> pumpHome(WidgetTester tester, MemoryProxyStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(userAgent: 'agent', proxyStore: store),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  Future<void> openExportSettings(WidgetTester tester) async {
    expect(find.byKey(const Key('exportExcel')), findsNothing);
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
    expect(find.text('Xuất Excel data'), findsOneWidget);
  }

  testWidgets(
    'exports latest stored data through settings and prevents duplicate saves',
    (tester) async {
      final store = await seed();
      final saving = Completer<String?>();
      var saves = 0;
      Map<dynamic, dynamic>? arguments;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'save');
        saves++;
        arguments = call.arguments as Map<dynamic, dynamic>;
        return saving.future;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await pumpHome(tester, store);
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      // Export must read the store instead of reusing the currently displayed totals.
      await store.nurture.saveProgress(
        'session',
        2,
        const NurtureTotals(videos: 7, fullVideos: 7),
      );
      await openExportSettings(tester);
      await tester.tap(find.byKey(const Key('exportExcel')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('exportExcel')))
            .onPressed,
        isNull,
      );
      expect(saves, 1);
      expect(arguments!['fileName'], startsWith('tiktok_data_'));
      expect(arguments!['fileName'], endsWith('.xlsx'));
      expect(arguments!['allowedExtensions'], ['xlsx']);
      final workbook = Excel.decodeBytes(arguments!['bytes'] as Uint8List);
      expect(workbook.tables.keys, [dataExcelSheetName]);
      expect(workbook[dataExcelSheetName].rows, hasLength(2));
      expect(workbook[dataExcelSheetName].rows[1][10]!.displayText, '7');
      saving.complete('/exports/data.xlsx');
      await tester.pumpAndSettle();
      expect(
        find.text('Đã xuất 1 cấu hình và 1 tài khoản nuôi.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('exportExcel')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final failSave in [false, true]) {
    testWidgets(
      failSave
          ? 'save failure releases export button and reports error'
          : 'cancelling export does not report success',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async {
            if (failSave) throw PlatformException(code: 'save_failed');
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await pumpHome(tester, await seed());
        await openExportSettings(tester);
        await tester.tap(find.byKey(const Key('exportExcel')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Đã xuất'), findsNothing);
        expect(
          find.text('Không thể xuất Excel. Hãy thử lại.'),
          failSave ? findsOneWidget : findsNothing,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('exportExcel')))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty database does not open the save dialog', (tester) async {
    var saves = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      saves++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await pumpHome(tester, MemoryProxyStore());
    await openExportSettings(tester);
    await tester.tap(find.byKey(const Key('exportExcel')));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(
      find.text('Chưa có dữ liệu cấu hình hoặc nuôi Account để xuất.'),
      findsOneWidget,
    );
  });
}
