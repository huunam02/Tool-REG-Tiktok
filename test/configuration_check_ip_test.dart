import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/screen/proxy_management_page.dart';
import 'package:test_tiktok/screen/settings_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  testWidgets('the configuration menu offers Kiểm tra IP for that entry', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    final id = await store.save(
      name: 'Checked',
      proxy: WebViewProxy.parse('checked.example:8080'),
    );
    final checked = <SavedProxy>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyManagementPage(
          store: store,
          onCheckIp: (entry) async => checked.add(entry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('Xóa'), findsOneWidget);
    await tester.tap(find.byKey(Key('checkIp-$id')));
    await tester.pumpAndSettle();
    expect(checked.single.id, id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a check action the menu has only Sửa and Xóa', (
    tester,
  ) async {
    final store = MemoryProxyStore();
    await store.save(name: 'Plain', proxy: null);
    await tester.pumpWidget(
      MaterialApp(home: ProxyManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra IP'), findsNothing);
  });

  testWidgets('Cài đặt no longer offers the IP / User-Agent check', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(proxyStore: MemoryProxyStore())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra IP / User-Agent'), findsNothing);
    expect(find.text('Kiểm tra IP với WhatIsMyIP'), findsNothing);
    expect(find.text('Xuất dữ liệu Excel'), findsOneWidget);
  });
}
