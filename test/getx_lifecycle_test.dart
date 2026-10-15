import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/proxy_form_controller.dart';
import 'package:test_tiktok/screen/create_proxy_page.dart';

void main() {
  testWidgets(
      'discarding imported forms ignores their pending User-Agent generation',
      (tester) async {
    final pending = Completer<String>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: CreateProxyPage(detectTimeZone: (_, _) async => 'America/New_York', generateUserAgent: () {
        calls++;
        return calls == 1 ? Future.value('first-agent') : pending.future;
      }),
    ));
    await tester.pumpAndSettle();
    final logic = tester
        .state<GetBuilderState<ProxyFormController>>(
            find.byType(GetBuilder<ProxyFormController>))
        .controller!;
    logic.importData.text =
        '192.0.2.7:8080:user:pass first@example.com|tiktok|mail\n'
        '192.0.2.8:8080:user:pass second@example.com|tiktok|mail\n'
        '192.0.2.9:8080:user:pass third@example.com|tiktok|mail';
    logic.importProxy();
    await tester.pumpAndSettle();
    final discarded = logic.configurations.skip(1).toList();
    expect(logic.generating, isTrue);
    expect(calls, 2);
    logic.clearImportedConfigurations();
    await tester.pumpAndSettle();
    pending.complete('discarded-agent');
    await tester.pumpAndSettle();
    expect(logic.configurations, hasLength(1));
    expect(discarded.every((fields) => fields.disposed), isTrue);
    expect(logic.userAgent.text, 'first-agent');
    expect(logic.generating, isFalse);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'proxy editors have independent state and close pending generation',
      (tester) async {
    final pendingAgent = Completer<String>();
    final first = CreateProxyPage(
        detectTimeZone: (_, _) async => 'America/New_York',
        key: const Key('firstEditor'),
        generateUserAgent: () => pendingAgent.future);
    final second = CreateProxyPage(
        detectTimeZone: (_, _) async => 'America/New_York',
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
