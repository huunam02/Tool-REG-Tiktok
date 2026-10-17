import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/widgets/proxy_widgets.dart';

import 'support/memory_proxy_store.dart';
import 'support/test_session_platform.dart';

void main() {
  const account = AccountCredentials(
    email: 'person@example.com',
    password: 'TikTok-password',
    mailboxPassword: 'Mailbox-password',
  );

  testWidgets(
    'Home retains general settings and selected configuration in its first tab',
    (tester) async {
      final store = MemoryProxyStore();
      final id = await store.save(
        name: 'Account 01',
        proxy: WebViewProxy.parse(
          '192.0.2.7:8080',
          username: 'proxy-user',
          password: 'proxy-pass',
        )!,
        userAgent: 'profile-agent',
        timeZoneId: 'America/New_York',
        account: account,
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(id);
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quản lý cấu hình'), findsOneWidget);
      expect(find.text('person@example.com'), findsOneWidget);
      expect(find.text('TikTok-password'), findsOneWidget);
      expect(find.text('Mailbox-password'), findsOneWidget);
      expect(find.text('proxy-user'), findsOneWidget);
      expect(find.text('proxy-pass'), findsOneWidget);
      expect(find.text('Đã đăng ký'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.byKey(const Key('comments')), findsNothing);
      expect(find.byKey(const Key('openTikTok')), findsOneWidget);
      expect(find.text('Đăng nhập tài khoản'), findsOneWidget);
      final preview = tester.widget<ProxyDetails>(find.byType(ProxyDetails));
      expect(sameAccount(preview.profile.account, account), isTrue);
      expect(preview.profile.proxy!.uri.host, '192.0.2.7');
      expect(preview.profile.userAgent, 'profile-agent');
      expect(preview.profile.timeZoneId, 'America/New_York');
      expect(find.byKey(const Key('currentProxyTimeZone')), findsOneWidget);
      expect(find.text('America/New_York'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing the registered switch persists both values and refreshes Home',
    (tester) async {
      final store = MemoryProxyStore();
      final id = await store.save(
        name: account.email,
        proxy: WebViewProxy.parse('192.0.2.7:8080')!,
        userAgent: 'profile-agent',
        account: account,
      );
      await store.useSaved(id);
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      for (final registered in [true, false]) {
        await tester.tap(find.byKey(const Key('manageProxies')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Tùy chọn cấu hình'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sửa'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('savedProxyName')), findsNothing);
        final toggle = find.byKey(const Key('savedAccountStatus'));
        await tester.ensureVisible(toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, !registered);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, registered);
        await tester.tap(find.byKey(const Key('saveProxyEntry')));
        await tester.pumpAndSettle();
        expect(
          store.entries.single.statusAccount,
          registered ? AccountStatus.registered : AccountStatus.unregistered,
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          find.text(registered ? 'Đã đăng ký' : 'Chưa đăng ký'),
          findsOneWidget,
        );
        expect(
          find.text(registered ? 'Đăng nhập tài khoản' : 'Đăng ký tài khoản'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching accounts on the same proxy clears the old session and refreshes Home',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previous = InAppWebViewPlatform.instance;
      final session = TestSessionPlatform();
      InAppWebViewPlatform.instance = session;
      addTearDown(() {
        if (previous != null) InAppWebViewPlatform.instance = previous;
      });
      final store = MemoryProxyStore();
      final proxy = WebViewProxy.parse('192.0.2.7:8080')!;
      final first = await store.save(
        name: 'First',
        proxy: proxy,
        userAgent: 'same-agent',
        account: account,
        statusAccount: AccountStatus.registered,
      );
      final second = await store.save(
        name: 'Second',
        proxy: proxy,
        userAgent: 'same-agent',
        account: const AccountCredentials(
          email: 'second@example.com',
          password: 'second-tiktok',
          mailboxPassword: 'second-mail',
        ),
      );
      await store.useSaved(first);
      await tester.binding.setSurfaceSize(const Size(800, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'direct-agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập tài khoản'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manageProxies')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('savedProxy-$second')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(session.calls.first, 'cookies');
      expect(find.text('second@example.com'), findsOneWidget);
      expect(find.text('second-tiktok'), findsOneWidget);
      expect(find.text('person@example.com'), findsNothing);
      expect(find.text('Đăng ký tài khoản'), findsOneWidget);
      expect(find.text('Đăng nhập tài khoản'), findsNothing);
      expect(find.byKey(const Key('comments')), findsNothing);
      await tester.tap(find.byKey(const Key('manageProxies')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('savedProxy-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setSelectedProxy')));
      await tester.pumpAndSettle();
      expect(find.text('person@example.com'), findsOneWidget);
      expect(find.text('Đăng nhập tài khoản'), findsOneWidget);
      expect(find.text('Đăng ký tài khoản'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
