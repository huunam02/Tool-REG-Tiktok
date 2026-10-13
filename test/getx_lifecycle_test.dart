import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/proxy_form_controller.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';

void main() {
  testWidgets(
      'proxy editors have independent state and close pending generation',
      (tester) async {
    final pendingAgent = Completer<String>();
    final first = CreateProxyPage(
        key: const Key('firstEditor'),
        generateUserAgent: () => pendingAgent.future);
    final second = CreateProxyPage(
        key: const Key('secondEditor'),
        generateUserAgent: () async => 'second-agent');

    Widget editors(List<Widget> children) => MaterialApp(
        home: Row(
            children: children
                .map((child) => Expanded(key: child.key, child: child))
                .toList()));
    await tester.pumpWidget(editors([first, second]));
    await tester.pumpAndSettle();
    final builders = find.byType(GetBuilder<ProxyFormController>);
    final firstController = tester
        .state<GetBuilderState<ProxyFormController>>(builders.first)
        .controller!;
    final secondController = tester
        .state<GetBuilderState<ProxyFormController>>(builders.last)
        .controller!;
    expect(firstController.generating, isTrue);
    expect(secondController.userAgent.text, 'second-agent');
    expect(identical(firstController, secondController), isFalse);

    await tester.pumpWidget(editors([second]));
    await tester.pumpAndSettle();
    expect(firstController.isClosed, isTrue);
    expect(secondController.isClosed, isFalse);
    pendingAgent.complete('late-first-agent');
    await tester.pumpAndSettle();
    expect(secondController.userAgent.text, 'second-agent');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(secondController.isClosed, isTrue);
  });
}
