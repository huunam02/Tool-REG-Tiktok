import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/core/controller/proxy_form_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/configuration_file_import.dart';
import 'package:test_tiktok/screen/widgets/proxy_form.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';
import 'package:test_tiktok/screen/proxy_management_page.dart';

import 'support/memory_proxy_store.dart';

Future<String> _testTimeZone(WebViewProxy proxy, String userAgent) async =>
    'America/New_York';

void main() {
  const record = '192.0.2.7:9323:proxy-user:proxy-password';
  const combinedRecord =
      '$record|person@example.com|TikTok-password|Mailbox-password';
  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

  test('imports proxy address, port and separate credentials', () {
    final proxy = WebViewProxy.parseImport(record);
    expect(proxy.uri.toString(), 'socks5://192.0.2.7:9323');
    expect(proxy.uri.userInfo, isEmpty);
    expect(proxy.username, 'proxy-user');
    expect(proxy.password, 'proxy-password');
  });

  test(
    'import preserves password characters and accepts copied line endings',
    () {
      final proxy = WebViewProxy.parseImport(
        '\r\nproxy.example.com:8080:user: pass:word \r\n',
      );
      expect(proxy.uri.host, 'proxy.example.com');
      expect(proxy.password, ' pass:word ');
    },
  );

  test(
    'import rejects invalid ports, missing credentials and multiple rows',
    () {
      for (final invalid in [
        '',
        '192.0.2.7:9323',
        '192.0.2.7:9323:user',
        '192.0.2.7:9323::password',
        '192.0.2.7:9323:user:',
        '192.0.2.7:9323:user:   ',
        '192.0.2.7:0:user:password',
        '192.0.2.7:65536:user:password',
        '192.0.2.7:abc:user:password',
        'local host:8080:user:password',
        'proxy.example.com/path:8080:user:password',
        '$record\n$record',
      ]) {
        expect(() => WebViewProxy.parseImport(invalid), throwsFormatException);
      }
    },
  );

  testWidgets('import button shows exactly file and clipboard options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateProxyPage(
          detectTimeZone: _testTimeZone,
          generateUserAgent: () async => 'test-agent',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('importProxyData')));
    await tester.tap(find.byKey(const Key('importProxyData')));
    await tester.pumpAndSettle();
    expect(find.text('Từ file'), findsOneWidget);
    expect(find.text('Dán từ clipboard'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(2),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(text(tester, 'savedProxyUrl'), isEmpty);
  });

  testWidgets(
    'file import populates the batch, handles cancellation and preserves invalid data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyForm(
            detectTimeZone: _testTimeZone,
            title: 'Tạo cấu hình',
            submitLabel: 'Tạo cấu hình',
            randomizeOnOpen: true,
            generateUserAgent: () async => 'test-agent',
            pickImportFile: () async {
              picks++;
              if (picks == 2) return null;
              return ConfigurationImportFile(
                'profiles.txt',
                Uint8List.fromList(
                  utf8.encode(
                    picks == 1
                        ? '$combinedRecord|1\n${combinedRecord.replaceFirst('person@', 'second@')}'
                        : '$combinedRecord|2',
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var pick = 1; pick <= 3; pick++) {
        await tester.tap(find.byKey(const Key('importProxyData')));
        await tester.pumpAndSettle();
        final logic = tester
            .state<GetBuilderState<ProxyFormController>>(
              find.byType(GetBuilder<ProxyFormController>),
            )
            .controller!;
        await tester.tap(find.byKey(const Key('importFromFile')));
        await tester.pump();
        for (var attempt = 0; logic.importing && attempt < 500; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(logic.importing, isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Tạo 2 cấu hình'), findsOneWidget);
        expect(find.text('second@example.com'), findsOneWidget);
        expect(text(tester, 'savedProxyUserAgent'), 'test-agent');
      }
      expect(
        find.text(
          'Dòng 1: Trạng thái đăng ký phải là 1 (đã đăng ký) hoặc 0 (chưa đăng ký).',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('import persists proxy and account together after review', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryProxyStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyManagementPage(store: store, detectTimeZone: _testTimeZone),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    final agent = text(tester, 'savedProxyUserAgent');
    await tester.enterText(
      find.byKey(const Key('proxyImportData')),
      '$combinedRecord|1',
    );
    await tester.tap(find.byKey(const Key('applyProxyImportData')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('savedProxyName')), findsNothing);
    expect(text(tester, 'savedAccountEmail'), 'person@example.com');
    expect(text(tester, 'savedProxyUrl'), 'socks5://192.0.2.7:9323');
    expect(text(tester, 'savedProxyUsername'), 'proxy-user');
    expect(text(tester, 'savedProxyPassword'), 'proxy-password');
    expect(text(tester, 'savedProxyTimeZone'), 'America/New_York');
    expect(text(tester, 'savedProxyUserAgent'), agent);
    expect(text(tester, 'proxyImportData'), isEmpty);
    expect(find.text('Đã import thành công 1 cấu hình.'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries.single.name, 'person@example.com');
    expect(store.entries.single.proxy!.password, 'proxy-password');
    expect(store.entries.single.account!.email, 'person@example.com');
    expect(store.entries.single.account!.password, 'TikTok-password');
    expect(store.entries.single.account!.mailboxPassword, 'Mailbox-password');
    expect(store.entries.single.userAgent, agent);
    expect(store.entries.single.statusAccount, AccountStatus.registered);
    expect(store.current, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import updates the switch and invalid status preserves fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CreateProxyPage(
          detectTimeZone: _testTimeZone,
          generateUserAgent: () async => 'test-agent',
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final suffix in ['|1', '|2', '|0', '|1', '']) {
      await tester.enterText(
        find.byKey(const Key('proxyImportData')),
        suffix == '|2'
            ? 'other.example.com:8080:user:pass|other@example.com|other|mail|2'
            : '$combinedRecord$suffix',
      );
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('savedAccountStatus')))
            .value,
        suffix == '|1' || suffix == '|2',
      );
      expect(text(tester, 'savedAccountEmail'), 'person@example.com');
      expect(text(tester, 'savedProxyUrl'), 'socks5://192.0.2.7:9323');
      expect(text(tester, 'savedMailboxPassword'), 'Mailbox-password');
      if (suffix == '|2') {
        expect(
          find.text(
            'Dòng 1: Trạng thái đăng ký phải là 1 (đã đăng ký) hoặc 0 (chưa đăng ký).',
          ),
          findsOneWidget,
        );
      } else {
        expect(text(tester, 'proxyImportData'), isEmpty);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('paste button imports proxy data from clipboard immediately', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': combinedRecord};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CreateProxyPage(
          detectTimeZone: _testTimeZone,
          generateUserAgent: () async => 'test-agent',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importProxyData')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pasteProxyData')));
    await tester.pump();

    expect(text(tester, 'proxyImportData'), isEmpty);
    expect(find.byKey(const Key('savedProxyName')), findsNothing);
    expect(text(tester, 'savedAccountEmail'), 'person@example.com');
    expect(text(tester, 'savedProxyUrl'), 'socks5://192.0.2.7:9323');
    expect(text(tester, 'savedProxyUsername'), 'proxy-user');
    expect(text(tester, 'savedProxyPassword'), 'proxy-password');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pasted Excel filename guides to file import and preserves fields',
    (tester) async {
      const fileName = 'proxy_email_accounts_corrected.xlsx';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': fileName} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CreateProxyPage(generateUserAgent: () async => 'test-agent'),
        ),
      );
      await tester.pumpAndSettle();
      final logic = tester
          .state<GetBuilderState<ProxyFormController>>(
            find.byType(GetBuilder<ProxyFormController>),
          )
          .controller!;
      logic.importData.text = combinedRecord;
      logic.importProxy();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('importProxyData')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pasteProxyData')));
      await tester.pumpAndSettle();
      expect(logic.importError, contains('Import data > Từ file'));
      expect(text(tester, 'proxyImportData'), fileName);
      expect(logic.accountEmail.text, 'person@example.com');
      expect(logic.password.text, 'proxy-password');
      expect(logic.importing, isFalse);
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(logic.importError, contains('Import data > Từ file'));
      expect(logic.accountEmail.text, 'person@example.com');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipboard imports multiple configurations and saves after review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      final batch =
          '$combinedRecord|1\r\n\r\n'
          '${combinedRecord.replaceFirst('person@', 'second@')}|0\n'
          '${combinedRecord.replaceFirst('person@', 'third@')}';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': batch} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyManagementPage(
            store: store,
            detectTimeZone: _testTimeZone,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addProxy')));
      await tester.pumpAndSettle();
      final agent = text(tester, 'savedProxyUserAgent');
      await tester.tap(find.byKey(const Key('importProxyData')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pasteProxyData')));
      await tester.pumpAndSettle();
      expect(find.text('Tạo 3 cấu hình'), findsOneWidget);
      expect(find.text('Đã import thành công 3 cấu hình.'), findsOneWidget);
      expect(find.text('second@example.com'), findsOneWidget);
      expect(store.entries, isEmpty);

      await tester.enterText(
        find.byKey(const Key('proxyImportData')),
        '$combinedRecord\n$combinedRecord|2',
      );
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(find.text('Tạo 3 cấu hình'), findsOneWidget);
      expect(
        find.text(
          'Dòng 2: Trạng thái đăng ký phải là 1 (đã đăng ký) hoặc 0 (chưa đăng ký).',
        ),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);

      await tester.enterText(find.byKey(const Key('proxyImportData')), batch);
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveProxyEntry')));
      await tester.pumpAndSettle();
      expect(store.entries.map((entry) => entry.account!.email), [
        'person@example.com',
        'second@example.com',
        'third@example.com',
      ]);
      expect(store.entries.map((entry) => entry.statusAccount), [
        AccountStatus.registered,
        AccountStatus.unregistered,
        AccountStatus.unregistered,
      ]);
      expect(store.entries.first.userAgent, agent);
      expect(
        store.entries.map((entry) => entry.userAgent).toSet(),
        hasLength(3),
      );
      expect(store.current, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch can be discarded or replaced by a single record', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CreateProxyPage(
          detectTimeZone: _testTimeZone,
          generateUserAgent: () async => 'test-agent',
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final discard in [false, true]) {
      await tester.ensureVisible(find.byKey(const Key('proxyImportData')));
      await tester.enterText(
        find.byKey(const Key('proxyImportData')),
        '$combinedRecord\n${combinedRecord.replaceFirst('person@', 'second@')}|1',
      );
      await tester.ensureVisible(find.byKey(const Key('applyProxyImportData')));
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(find.text('Tạo 2 cấu hình'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (discard) {
        await tester.ensureVisible(find.text('Bỏ danh sách'));
        await tester.tap(find.text('Bỏ danh sách'));
      } else {
        await tester.ensureVisible(find.byKey(const Key('proxyImportData')));
        await tester.enterText(
          find.byKey(const Key('proxyImportData')),
          combinedRecord,
        );
        await tester.ensureVisible(
          find.byKey(const Key('applyProxyImportData')),
        );
        await tester.tap(find.byKey(const Key('applyProxyImportData')));
      }
      await tester.pumpAndSettle();
      expect(find.text('Tạo 2 cấu hình'), findsNothing);
      expect(
        text(tester, 'savedAccountEmail'),
        discard ? '' : 'person@example.com',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('two imported rows have independent editable configuration forms', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryProxyStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyManagementPage(store: store, detectTimeZone: _testTimeZone),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('proxyImportData')),
      '$combinedRecord|1\n${combinedRecord.replaceFirst('person@', 'second@')}|0',
    );
    await tester.tap(find.byKey(const Key('applyProxyImportData')));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin cấu hình'), findsNWidgets(2));
    expect(text(tester, 'savedAccountEmail'), 'person@example.com');
    expect(text(tester, 'savedAccountEmail-1'), 'second@example.com');
    final firstAgent = text(tester, 'savedProxyUserAgent');
    final secondAgent = text(tester, 'savedProxyUserAgent-1');
    expect(secondAgent, isNot(firstAgent));
    await tester.ensureVisible(
      find.byKey(const Key('generateProxyUserAgent-1')),
    );
    await tester.tap(find.byKey(const Key('generateProxyUserAgent-1')));
    await tester.pumpAndSettle();
    expect(text(tester, 'savedProxyUserAgent'), firstAgent);
    expect(text(tester, 'savedProxyUserAgent-1'), isNot(secondAgent));

    for (final entry in {
      'savedProxyUrl-1': 'http://other.example.com:9000',
      'savedProxyUserAgent-1': 'edited-second-agent',
      'savedAccountEmail-1': 'invalid-email',
      'savedAccountPassword-1': 'edited-password',
      'savedMailboxPassword-1': 'edited-mailbox',
    }.entries) {
      await tester.ensureVisible(find.byKey(Key(entry.key)));
      await tester.enterText(find.byKey(Key(entry.key)), entry.value);
    }
    expect(text(tester, 'savedProxyUrl'), 'socks5://192.0.2.7:9323');
    expect(text(tester, 'savedAccountPassword'), 'TikTok-password');
    expect(text(tester, 'savedMailboxPassword'), 'Mailbox-password');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email tài khoản hợp lệ.'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.enterText(
      find.byKey(const Key('savedAccountEmail-1')),
      'edited@example.com',
    );
    for (final key in ['savedAccountStatus-1', 'savedAccountStatus']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('savedAccountStatus')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('savedAccountStatus-1')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(store.entries, hasLength(2));
    final first = store.entries.singleWhere(
      (entry) => entry.account!.email == 'person@example.com',
    );
    final second = store.entries.singleWhere(
      (entry) => entry.account!.email == 'edited@example.com',
    );
    expect(first.userAgent, firstAgent);
    expect(first.statusAccount, AccountStatus.unregistered);
    expect(second.proxy!.uri.host, 'other.example.com');
    expect(second.userAgent, 'edited-second-agent');
    expect(second.account!.password, 'edited-password');
    expect(second.account!.mailboxPassword, 'edited-mailbox');
    expect(second.statusAccount, AccountStatus.registered);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing has no name or import and preserves the account and User-Agent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      await store.save(
        name: 'Chosen name',
        proxy: WebViewProxy.parse('original.example.com:8080')!,
        userAgent: 'chosen-agent',
        account: const AccountCredentials(
          email: 'original@example.com',
          password: 'tiktok',
          mailboxPassword: 'mail',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyManagementPage(
            store: store,
            detectTimeZone: _testTimeZone,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('proxyImportData')), findsNothing);
      expect(find.byKey(const Key('applyProxyImportData')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('savedProxyUrl')),
        'socks5://192.0.2.7:9323',
      );
      await tester.enterText(
        find.byKey(const Key('savedProxyUsername')),
        'proxy-user',
      );
      await tester.enterText(
        find.byKey(const Key('savedProxyPassword')),
        'proxy-password',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedProxyName')), findsNothing);
      expect(text(tester, 'savedAccountEmail'), 'original@example.com');
      expect(text(tester, 'savedProxyUserAgent'), 'chosen-agent');
      await tester.tap(find.byKey(const Key('saveProxyEntry')));
      await tester.pumpAndSettle();
      expect(store.entries.single.account!.email, 'original@example.com');
      expect(store.entries.single.userAgent, 'chosen-agent');
      expect(store.entries.single.proxy!.uri.host, '192.0.2.7');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid import leaves existing fields intact and can be corrected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CreateProxyPage(
            detectTimeZone: _testTimeZone,
            generateUserAgent: () async => 'test-agent',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originals = {
        'savedProxyUrl': 'https://original.example.com:443',
        'savedProxyUsername': 'original-user',
        'savedProxyPassword': 'original-password',
      };
      for (final entry in originals.entries) {
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
      }
      await tester.enterText(
        find.byKey(const Key('proxyImportData')),
        '192.0.2.7:99999:user:password|person@example.com|tiktok|mailbox',
      );
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(
        find.text('Dòng 1: Nhập proxy dạng host:port.'),
        findsOneWidget,
      );
      for (final entry in originals.entries) {
        expect(text(tester, entry.key), entry.value);
      }
      await tester.enterText(
        find.byKey(const Key('proxyImportData')),
        combinedRecord,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Dòng 1: Nhập proxy dạng host:port.'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('applyProxyImportData')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedProxyName')), findsNothing);
      expect(text(tester, 'savedAccountEmail'), 'person@example.com');
      expect(text(tester, 'savedProxyUserAgent'), 'test-agent');
      expect(text(tester, 'savedProxyUrl'), 'socks5://192.0.2.7:9323');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signup email accepts manual input and Data Mail fills it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyManagementPage(
          store: MemoryProxyStore(),
          detectTimeZone: _testTimeZone,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addProxy')));
    await tester.pumpAndSettle();
    final email = find.byKey(const Key('savedAccountEmail'));
    final dataMail = find.byKey(const Key('savedMailboxPassword'));
    await tester.ensureVisible(dataMail);
    await tester.enterText(dataMail, 'first@example.com|p|token|client|alt');
    expect(text(tester, 'savedAccountEmail'), 'first@example.com');

    await tester.ensureVisible(email);
    await tester.enterText(email, 'typed@example.com');
    await tester.enterText(dataMail, 'second@example.com|p|token|client|alt');
    expect(text(tester, 'savedAccountEmail'), 'typed@example.com');

    await tester.enterText(email, '');
    await tester.enterText(dataMail, 'third@example.com|p|token|client|alt');
    expect(text(tester, 'savedAccountEmail'), 'third@example.com');
  });
}
