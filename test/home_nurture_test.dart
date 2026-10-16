import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/config.dart' as config;
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/screen/home_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  testWidgets(
    'saved Vietnamese defaults migrate to English without removing custom lines',
    (tester) async {
      final store = MemoryProxyStore();
      await store.nurture.savePreferences({
        'home_comments':
            '  Video hay quá, xem không chán luôn!  \nCustom comment\nNội dung chất lượng thật sự 👏',
        'nurture_keywords': 'Cà phê\nCông nghệ',
        'search_keywords_initialized': '1',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('comments')))
            .controller!
            .text,
        '  This video is so good, I could watch it all day!  \nCustom comment\nSuch great content 👏',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('nurtureKeywords')))
            .controller!
            .text,
        'Coffee\nTechnology',
      );
      await tester.pump(const Duration(milliseconds: 500));
      final saved = await store.nurture.preferences();
      expect(saved['configuration_content_language'], 'en');
      expect(saved['nurture_keywords'], 'Coffee\nTechnology');
      expect(saved['home_comments'], contains('Custom comment'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('comments')))
            .controller!
            .text,
        saved['home_comments'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tabs preserve old configuration, comments and saved topics', (
    tester,
  ) async {
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
    );
    await store.useSaved(id);
    await store.nurture.savePreferences({
      'nurture_keywords': 'Du lịch',
      'home_comments': 'Saved comment',
    });
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
    final comments = find.byKey(const Key('comments'));
    expect(
      tester.widget<TextFormField>(comments).controller!.text,
      'Saved comment',
    );
    await tester.enterText(comments, 'Changed comment');
    final keywords = find.byKey(const Key('nurtureKeywords'));
    await tester.ensureVisible(keywords);
    await tester.pumpAndSettle();
    expect(find.text('Từ khóa tìm kiếm'), findsOneWidget);
    expect(tester.widget<TextFormField>(keywords).controller!.text, 'Du lịch');
    await tester.enterText(keywords, 'Ẩm thực\nCà phê');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('nurtureTab')));
    await tester.pumpAndSettle();
    expect(find.text('1.5 phút'), findsOneWidget);
    expect(find.text('Video đã xem'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Nuôi search keyword · Du lịch'), findsNothing);
    expect(find.byKey(const Key('nurtureKeywords')), findsNothing);
    expect(find.byTooltip('Làm mới thống kê'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byKey(const Key('openTikTok')), findsNothing);
    await tester.tap(find.byKey(const Key('configurationTab')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(comments).controller!.text,
      'Changed comment',
    );
    expect(find.text('old-password'), findsOneWidget);
    expect(
      (await store.nurture.preferences())['nurture_keywords'],
      'Ẩm thực\nCà phê',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(userAgent: 'agent', proxyStore: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(comments).controller!.text,
      'Changed comment',
    );
    expect(
      tester.widget<TextFormField>(keywords).controller!.text,
      'Ẩm thực\nCà phê',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty account tab fits narrow screen and links back to configuration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      await store.nurture.savePreferences({'nurture_keywords': ''});
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      final keywords = find.byKey(const Key('nurtureKeywords'));
      expect(
        tester.widget<TextFormField>(keywords).controller!.text,
        config.defaultSearchKeywords.join('\n'),
      );
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có tài khoản'), findsOneWidget);
      await tester.ensureVisible(find.text('Đi đến Cấu hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đi đến Cấu hình'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('openTikTok')), findsOneWidget);
      await tester.ensureVisible(keywords);
      await tester.pumpAndSettle();
      await tester.enterText(keywords, '');
      await tester.pump(const Duration(milliseconds: 500));
      expect((await store.nurture.preferences())['nurture_keywords'], '');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(keywords).controller!.text, '');
      expect(tester.takeException(), isNull);
    },
  );
}
