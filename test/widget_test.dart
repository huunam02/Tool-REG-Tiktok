import 'package:flutter/material.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_tiktok/desktop_user_agents.dart';
import 'package:test_tiktok/home_page.dart';

class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      _TestWebView(params);
}

class _TestWebView extends PlatformInAppWebViewWidget {
  _TestWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

void main() {
  testWidgets('Expandable menu exposes watch, login and signup actions',
      (tester) async {
    final previousPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
    addTearDown(() {
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: HomePage(userAgent: desktopUserAgents.first),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ExpandableFab), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();
    final menu = tester.state<ExpandableFabState>(find.byType(ExpandableFab));
    expect(menu.isOpen, isTrue);
    expect(find.text('Tự xem và bình luận'), findsOneWidget);
    expect(find.text('Tự động đăng nhập'), findsOneWidget);
    expect(find.text('Tự động đăng ký'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(menu.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });
}
