import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/firefox_user_agent.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/proxy_draft.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/screen/edit_proxy_page.dart';
import 'package:test_tiktok/screen/proxy_management_page.dart';

import 'support/memory_proxy_store.dart';

Future<String> _testTimeZone(WebViewProxy proxy, String userAgent) async =>
    'America/New_York';

void main() {
  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

  Future<void> enter(WidgetTester tester, String key, String value) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), value);
  }

  testWidgets('a new configuration starts with the default nurture settings '
      'and saves its own values', (tester) async {
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
    expect(text(tester, 'nurtureLikePercent'), '30');
    expect(text(tester, 'nurtureCommentPercent'), '20');
    expect(text(tester, 'nurtureLongWatchPercent'), '50');
    expect(text(tester, 'nurtureMinMinutes'), '2');
    expect(text(tester, 'nurtureMaxMinutes'), '3');

    await tester.enterText(
      find.byKey(const Key('proxyImportData')),
      '192.0.2.7:9323:proxy-user:proxy-password|person@example.com|'
      'TikTok-password|Mailbox-password',
    );
    await tester.tap(find.byKey(const Key('applyProxyImportData')));
    await tester.pumpAndSettle();
    // Importing a text record keeps the values already in the form.
    expect(text(tester, 'nurtureLikePercent'), '30');

    await enter(tester, 'nurtureLikePercent', '45');
    await enter(tester, 'nurtureMinMinutes', '9');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    // Minimum above maximum is rejected and nothing is stored.
    expect(find.text('Phải ≥ thời gian tối thiểu.'), findsOneWidget);
    expect(store.entries, isEmpty);

    await enter(tester, 'nurtureMaxMinutes', '12');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(
      store.entries.single.nurtureSettings,
      const NurtureSettings(likePercent: 45, minMinutes: 9, maxMinutes: 12),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing shows the saved values and Mặc định restores them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const custom = NurtureSettings(
      likePercent: 45,
      commentPercent: 5,
      longWatchPercent: 70,
      minMinutes: 10,
      maxMinutes: 20,
    );
    ProxyDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                draft = await Navigator.of(context).push<ProxyDraft>(
                  MaterialPageRoute(
                    builder: (_) => EditProxyPage(
                      entry: SavedProxy(
                        id: 1,
                        name: 'person@example.com',
                        proxy: WebViewProxy.parseImport(
                          '192.0.2.7:9323:proxy-user:proxy-password',
                        ),
                        userAgent: 'agent',
                        account: const AccountCredentials(
                          email: 'person@example.com',
                          password: 'secret',
                          mailboxPassword: 'mail',
                        ),
                        nurtureSettings: custom,
                      ),
                      generateUserAgent: () async => 'agent',
                      detectTimeZone: _testTimeZone,
                    ),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(text(tester, 'nurtureLikePercent'), '45');
    expect(text(tester, 'nurtureCommentPercent'), '5');
    expect(text(tester, 'nurtureLongWatchPercent'), '70');
    expect(text(tester, 'nurtureMinMinutes'), '10');
    expect(text(tester, 'nurtureMaxMinutes'), '20');

    await tester.ensureVisible(find.byKey(const Key('resetNurtureSettings')));
    await tester.tap(find.byKey(const Key('resetNurtureSettings')));
    await tester.pumpAndSettle();
    expect(text(tester, 'nurtureLikePercent'), '30');
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(draft!.nurtureSettings, NurtureSettings.defaults);
  });

  testWidgets('configurations show the fixed Windows desktop GPU after import', (
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
    String gpu() =>
        tester.widget<Text>(find.byKey(const Key('savedGpuProfile'))).data!;
    expect(gpu(), firefoxDesktopGpuLabel);
    expect(find.byKey(const Key('changeGpuProfile')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('proxyImportData')),
      '192.0.2.7:9323:proxy-user:proxy-password|person@example.com|'
      'TikTok-password|Mailbox-password',
    );
    await tester.ensureVisible(find.byKey(const Key('applyProxyImportData')));
    await tester.tap(find.byKey(const Key('applyProxyImportData')));
    await tester.pumpAndSettle();
    expect(gpu(), firefoxDesktopGpuLabel);
    await tester.tap(find.byKey(const Key('saveProxyEntry')));
    await tester.pumpAndSettle();
    expect(find.text(firefoxDesktopGpuLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
