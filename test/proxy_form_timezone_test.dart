import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/core/controller/proxy_form_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/screen/widgets/proxy_form.dart';

const records =
    '192.0.2.7:8080:user:pass|first@example.com|mail|refresh|client|backup@example.com|tiktok\n'
    '192.0.2.8:8080:user:pass|second@example.com|mail|refresh|client|backup@example.com|tiktok';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ProxyFormController create(
    Future<String> Function(WebViewProxy, String) detector,
  ) {
    final form = ProxyFormController(
      randomizeOnOpen: false,
      selectUserAgent: () async => 'agent',
      detectTimeZone: detector,
    );
    form.onInit();
    form.userAgent.text = 'agent';
    addTearDown(form.onClose);
    return form;
  }

  test(
    'selecting HTTP preserves credentials and uses HTTP for timezone lookup and drafts',
    () async {
      String? requestedScheme;
      final form = create((proxy, _) async {
        requestedScheme = proxy.uri.scheme;
        return 'Asia/Ho_Chi_Minh';
      });
      form.url.text = 'socks5://proxy.example:8080';
      form.username.text = 'fixture-user';
      form.password.text = 'fixture-pass';
      form.timeZoneId.text = 'America/New_York';
      final fields = form.configurations.first;
      fields.setProxyProtocol('http');
      expect(fields.proxyProtocol, 'http');
      expect(form.url.text, 'http://proxy.example:8080');
      expect(form.username.text, 'fixture-user');
      expect(form.password.text, 'fixture-pass');
      expect(form.timeZoneId.text, isEmpty);
      await form.detectTimeZoneFor(fields);
      expect(requestedScheme, 'http');
      expect(fields.toDraft().proxy!.uri.scheme, 'http');
      expect(form.timeZoneId.text, 'Asia/Ho_Chi_Minh');
    },
  );

  test(
    'protocol selected before typing the address is applied to unqualified input',
    () async {
      final form = create((proxy, _) async => 'Asia/Tokyo');
      final fields = form.configurations.first;
      fields.setProxyProtocol('http');
      form.url.text = 'proxy.example:8080';
      expect(fields.parseProxy()!.uri.scheme, 'http');
      form.url.text = 'socks5://proxy.example:1080';
      expect(fields.proxyProtocol, 'socks5');
      expect(fields.parseProxy()!.uri.scheme, 'socks5');
    },
  );

  test(
    'import detects every row and each draft carries its own timezone',
    () async {
      final calls = <String>[];
      final form = create((proxy, agent) async {
        calls.add(proxy.uri.host);
        return proxy.uri.host.endsWith('7') ? 'America/New_York' : 'Asia/Tokyo';
      });
      form.importData.text = records;
      form.importProxy();
      expect(form.detectingTimeZones, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['192.0.2.7', '192.0.2.8']);
      expect(form.configurations.map((row) => row.toDraft().timeZoneId), [
        'America/New_York',
        'Asia/Tokyo',
      ]);
      expect(form.detectingTimeZones, isFalse);
    },
  );

  test(
    'failed row is reported independently and can be detected again',
    () async {
      var retry = false;
      final form = create((proxy, _) async {
        if (proxy.uri.host.endsWith('7') && !retry) {
          throw const FormatException('Proxy không kết nối được.');
        }
        return 'Asia/Tokyo';
      });
      form.importData.text = records;
      form.importProxy();
      await Future<void>.delayed(Duration.zero);
      expect(
        form.configurations.first.timeZoneError,
        contains('không kết nối'),
      );
      expect(form.configurations.first.timeZoneId.text, isEmpty);
      expect(form.configurations.last.timeZoneId.text, 'Asia/Tokyo');
      retry = true;
      await form.detectTimeZoneFor(form.configurations.first);
      expect(form.configurations.first.timeZoneError, isNull);
      expect(form.timeZoneId.text, 'Asia/Tokyo');
    },
  );

  test(
    'changing proxy or entering a manual zone discards stale lookup results',
    () async {
      final gates = <Completer<String>>[];
      final form = create((_, _) {
        final gate = Completer<String>();
        gates.add(gate);
        return gate.future;
      });
      form.importData.text = records;
      form.importProxy();
      form.configurations.first.url.text = 'other.example:8080';
      form.configurations.last.timeZoneId.text = 'Europe/Berlin';
      gates[0].complete('America/New_York');
      gates[1].complete('Asia/Tokyo');
      await Future<void>.delayed(Duration.zero);
      expect(form.timeZoneId.text, isEmpty);
      expect(form.configurations.last.timeZoneId.text, 'Europe/Berlin');
      form.configurations.last.password.text = 'new-password';
      expect(form.configurations.last.timeZoneId.text, isEmpty);
    },
  );

  test(
    'closing a form ignores late detection without touching disposed fields',
    () async {
      final gate = Completer<String>();
      final form = ProxyFormController(
        randomizeOnOpen: false,
        selectUserAgent: () async => 'agent',
        detectTimeZone: (_, _) => gate.future,
      );
      form.onInit();
      form.url.text = 'proxy.example:8080';
      final pending = form.detectTimeZoneFor(form.configurations.first);
      form.onClose();
      gate.complete('Asia/Tokyo');
      await pending;
      expect(form.configurations.first.disposed, isTrue);
    },
  );

  testWidgets(
    'new forms default to HTTP and the protocol selector switches to SOCKS5',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyForm(
            title: 'Tạo cấu hình',
            submitLabel: 'Lưu',
            randomizeOnOpen: false,
            generateUserAgent: () async => 'agent',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
        'http',
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SOCKS5').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('savedProxyUrl')),
        'proxy.example:1080',
      );
      final logic = tester
          .state<GetBuilderState<ProxyFormController>>(
            find.byType(GetBuilder<ProxyFormController>),
          )
          .controller!;
      expect(logic.configurations.first.parseProxy()!.uri.scheme, 'socks5');
    },
  );

  testWidgets(
    'imported timezone field is visible, editable and restored in drafts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ProxyForm(
            title: 'Tạo cấu hình',
            submitLabel: 'Lưu',
            randomizeOnOpen: true,
            generateUserAgent: () async => 'agent',
            detectTimeZone: (_, _) async => 'America/New_York',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final logic = tester
          .state<GetBuilderState<ProxyFormController>>(
            find.byType(GetBuilder<ProxyFormController>),
          )
          .controller!;
      logic.importData.text = records.split('\n').first;
      logic.importProxy();
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('savedProxyTimeZone'));
      await tester.ensureVisible(field);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        'America/New_York',
      );
      await tester.enterText(field, 'Asia/Tokyo');
      await tester.pumpAndSettle();
      expect((await logic.save())!.single.timeZoneId, 'Asia/Tokyo');
      expect(tester.takeException(), isNull);
    },
  );
}
