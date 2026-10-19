import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/screen/home_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  tearDown(() => RemoteConfig.configs = RemoteConfig.defaults);

  for (final isKeywords in [true, false]) {
    final title = isKeywords ? 'Keyword search' : 'Danh sách comment';
    final previewKey = isKeywords ? 'searchKeywordList' : 'commentList';
    final buttonKey = isKeywords ? 'viewAllSearchKeywords' : 'viewAllComments';

    testWidgets('$title previews three entries and opens the full list', (
      tester,
    ) async {
      final entries = List.generate(80, (index) => '$title item ${index + 1}');
      RemoteConfig.configs = {
        ...RemoteConfig.defaults,
        'search_keywords': jsonEncode(isKeywords ? entries : ['Keyword']),
        'auto_comments': jsonEncode(isKeywords ? ['Comment'] : entries),
      };
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: MemoryProxyStore()),
        ),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(Key(previewKey));
      expect(
        find.descendant(of: preview, matching: find.byType(SelectableText)),
        findsNWidgets(3),
      );
      expect(find.text(entries[3]), findsNothing);
      expect(find.text('$title (80)'), findsOneWidget);

      final button = find.byKey(Key(buttonKey));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('remoteEntriesList'));
      expect(list, findsOneWidget);
      expect(find.text(entries[3]), findsOneWidget);
      expect(find.text(entries.last), findsNothing);
      await tester.scrollUntilVisible(
        find.text(entries.last),
        500,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text(entries.last), findsOneWidget);
      expect(find.text('80.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(Key(buttonKey)), findsOneWidget);
      expect(list, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
