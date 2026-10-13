import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/home_controller.dart';
import 'package:test_tiktok/screen/home_page.dart';

import 'support/memory_proxy_store.dart';

void main() {
  Future<HomeController> mount(WidgetTester tester,
      {required bool signup}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home:
            HomePage(userAgent: 'test-agent', proxyStore: MemoryProxyStore())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(signup ? 'signupTab' : 'loginTab')));
    await tester.pumpAndSettle();
    return tester
        .state<GetBuilderState<HomeController>>(
            find.byType(GetBuilder<HomeController>))
        .controller!;
  }

  for (final signup in [true, false]) {
    final name = signup ? 'signup' : 'login';
    testWidgets('$name paste button fills the import field from clipboard',
        (tester) async {
      const record = 'person@outlook.com|TikTok-password|Mailbox-password';
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': record};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final logic = await mount(tester, signup: signup);

      await tester
          .tap(find.byKey(Key(signup ? 'pasteSignupData' : 'pasteLoginData')));
      await tester.pump();

      expect((signup ? logic.signupImportData : logic.loginImportData).text,
          record);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$name imports all three columns and keeps the other tab intact',
        (tester) async {
      final logic = await mount(tester, signup: signup);
      final otherEmail =
          (signup ? logic.loginUsername : logic.signupEmail).text;
      final otherPassword =
          (signup ? logic.loginPassword : logic.signupPassword).text;
      final otherMailbox =
          (signup ? logic.loginMailboxPassword : logic.signupMailboxPassword)
              .text;
      final field = find.byKey(Key('${name}ImportData'));
      expect(
          tester
              .widget<EditableText>(find.descendant(
                  of: field, matching: find.byType(EditableText)))
              .obscureText,
          isFalse);
      await tester.enterText(
          field, 'person@outlook.com|TikTok-password|Mailbox-password');
      await tester
          .tap(find.byKey(Key('import${signup ? 'Signup' : 'Login'}Data')));
      await tester.pumpAndSettle();
      expect((signup ? logic.signupEmail : logic.loginUsername).text,
          'person@outlook.com');
      expect((signup ? logic.signupPassword : logic.loginPassword).text,
          'TikTok-password');
      expect(
          (signup ? logic.signupMailboxPassword : logic.loginMailboxPassword)
              .text,
          'Mailbox-password');
      expect(
          (signup ? logic.loginUsername : logic.signupEmail).text, otherEmail);
      expect((signup ? logic.loginPassword : logic.signupPassword).text,
          otherPassword);
      expect(
          (signup ? logic.loginMailboxPassword : logic.signupMailboxPassword)
              .text,
          otherMailbox);
      expect((signup ? logic.signupImportData : logic.loginImportData).text,
          isEmpty);
      expect(
          find.text('Đã import thông tin ${signup ? 'đăng ký' : 'đăng nhập'}.'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(Key(signup ? 'signupEmail' : 'loginUsername')),
          'edited@outlook.com');
      expect((signup ? logic.signupEmail : logic.loginUsername).text,
          'edited@outlook.com');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(logic.isClosed, isTrue);
    });

    testWidgets(
        '$name rejects invalid records without replacing account fields',
        (tester) async {
      final logic = await mount(tester, signup: signup);
      final input = signup ? logic.signupImportData : logic.loginImportData;
      final email = signup ? logic.signupEmail : logic.loginUsername;
      final password = signup ? logic.signupPassword : logic.loginPassword;
      final mailbox =
          signup ? logic.signupMailboxPassword : logic.loginMailboxPassword;
      email.text = 'original@example.com';
      password.text = 'original-tiktok';
      mailbox.text = 'original-mailbox';
      for (final record in [
        '',
        'person@example.com|password',
        'person@example.com|password|mailbox|extra',
        'not-email|password|mailbox',
        'person@example.com||mailbox',
        'person@example.com|password|   ',
        'one@example.com|password|mailbox\ntwo@example.com|password|mailbox',
      ]) {
        input.text = record;
        logic.importAccountData(signup: signup);
        await tester.pump();
        final error = signup ? logic.signupImportError : logic.loginImportError;
        expect(error, isNotNull);
        expect(find.text(error!), findsOneWidget);
        expect(email.text, 'original@example.com');
        expect(password.text, 'original-tiktok');
        expect(mailbox.text, 'original-mailbox');
      }
      await tester.enterText(find.byKey(Key('${name}ImportData')),
          '\r\n  person@example.com|  tiktok password  | mailbox password \r\n');
      await tester.pump();
      expect(signup ? logic.signupImportError : logic.loginImportError, isNull);
      logic.importAccountData(signup: signup);
      await tester.pumpAndSettle();
      expect(email.text, 'person@example.com');
      expect(password.text, '  tiktok password  ');
      expect(mailbox.text, ' mailbox password ');
      expect(tester.takeException(), isNull);
    });
  }
}
