import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';
import 'package:test_tiktok/screen/home_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteConfig.configs = {
      ...RemoteConfig.defaults,
      'search_keywords': '["Cà phê", "Technology"]',
      'auto_comments': '["Bình luận từ remote ❤️", "Great video"]',
    };
  });
  tearDown(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });

  testWidgets(
    'Home uses remote lists for signup and login and ignores saved lists',
    (tester) async {
      // Keep this remote-data test independent of native Android automation.
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('test_tiktok/profile_vpn');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final store = MemoryProxyStore()
        ..currentAccount = const AccountCredentials(
          email: 'person@example.com',
          password: 'tiktok-password',
          mailboxPassword: 'mail-password',
        );
      await store.nurture.savePreferences({
        'home_comments': 'Old local comment',
        'nurture_keywords': 'Old local keyword',
        'search_keywords_initialized': '1',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comments')), findsNothing);
      expect(find.byKey(const Key('nurtureKeywords')), findsNothing);
      final logic = tester
          .state<GetBuilderState<HomeController>>(
            find.byType(GetBuilder<HomeController>),
          )
          .controller!;
      final configurations = <AppConfiguration>[];
      for (final action in [
        TikTokLaunchAction.signup,
        TikTokLaunchAction.login,
      ]) {
        await logic.openTikTok(action, (configuration, _) async {
          configurations.add(configuration);
        });
      }
      expect(configurations, hasLength(2));
      for (final configuration in configurations) {
        expect(configuration.comments, [
          'Bình luận từ remote ❤️',
          'Great video',
        ]);
        expect(configuration.searchKeywords, ['Cà phê', 'Technology']);
      }
      final saved = await store.nurture.preferences();
      expect(saved['home_comments'], 'Old local comment');
      expect(saved['nurture_keywords'], 'Old local keyword');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'tabs preserve selected account and nurture statistics without list editors',
    (tester) async {
      final store = MemoryProxyStore();
      final id = await store.save(
        name: 'Account 01',
        proxy: null,
        userAgent: 'agent',
        account: const AccountCredentials(
          email: 'person@example.com',
          password: 'old-password',
          mailboxPassword: 'mail',
        ),
        statusAccount: AccountStatus.registered,
      );
      // Unregistered accounts stay out of the nurture tab.
      await store.save(
        name: 'Account 02',
        proxy: null,
        userAgent: 'agent',
        account: const AccountCredentials(
          email: 'new@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      );
      await store.useSaved(id);
      await store.nurture.beginSession(
        id: 'existing',
        email: 'person@example.com',
        configurationId: id,
        plan: const NurturePlan(NurtureMode.search, 'Du lịch'),
        phase: 'stopped',
      );
      await store.nurture.saveProgress(
        'existing',
        1,
        const NurtureTotals(
          watchMilliseconds: 90000,
          videos: 3,
          fullVideos: 1,
          skippedVideos: 2,
          comments: 2,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      expect(find.text('1.5 phút'), findsOneWidget);
      expect(find.text('Tài khoản đã đăng ký số lượng: 1'), findsOneWidget);
      expect(find.text('person@example.com'), findsWidgets);
      expect(find.text('new@example.com'), findsNothing);
      expect(find.text('Video đã xem'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Nuôi search keyword · Du lịch'), findsNothing);
      expect(find.byTooltip('Làm mới thống kê'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byKey(const Key('openTikTok')), findsNothing);
      await tester.tap(find.byKey(const Key('configurationTab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manageProxies')), findsOneWidget);
      expect(find.byKey(const Key('comments')), findsNothing);
      expect(find.byKey(const Key('nurtureKeywords')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty account tab fits narrow screen and links back to configuration',
    (tester) async {
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
          home: HomePage(userAgent: 'agent', proxyStore: MemoryProxyStore()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có tài khoản đã đăng ký'), findsOneWidget);
      await tester.ensureVisible(find.text('Đi đến Cấu hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đi đến Cấu hình'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manageProxies')), findsOneWidget);
      expect(find.byKey(const Key('comments')), findsNothing);
      expect(find.byKey(const Key('nurtureKeywords')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
