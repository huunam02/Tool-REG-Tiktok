import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';

import 'support/memory_proxy_store.dart';

class _Store extends MemoryProxyStore {
  int registrationWrites = 0;

  @override
  Future<bool> markRegistered(int id, String email) {
    registrationWrites++;
    return super.markRegistered(id, email);
  }
}

class _View extends PlatformInAppWebViewController {
  _View()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String result = 'waiting-form';

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => source.contains(autoSignupStepScript) ? result : true;
}

void main() {
  for (final outcome in [
    'skip',
    'signup-success',
    'username-skip-accessibility-failed',
    'verification-required',
    'already-logged-in',
    'storage-failed',
  ]) {
    testWidgets('signup registration status: $outcome', (tester) async {
      final store = _Store();
      const account = AccountCredentials(
        email: 'signup@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final id = await store.save(
        name: 'Signup',
        proxy: null,
        account: account,
      );
      final other = await store.save(
        name: 'Other',
        proxy: WebViewProxy.parse('192.0.2.8:8080'),
        account: account,
      );
      // Selection may change while the signup page still uses its snapshot.
      await store.useSaved(other);
      final view = _View();
      final notices = <String>[];
      final logic = TikTokController(
        configuration: AppConfiguration(
          configurationId: id,
          userAgent: 'agent',
          signupEmail: account.email,
          signupPassword: account.password,
          signupMailboxPassword: account.mailboxPassword,
          loginUsername: account.email,
          loginPassword: account.password,
          comments: [],
        ),
        proxyStore: store,
        useAccessibility: false,
      )..onInit();
      logic.webViewController = InAppWebViewController.fromPlatform(
        platform: view,
      );
      logic.onNotice = (notice) => notices.add(notice.message);
      addTearDown(() => logic.onDelete());

      Future<void> poll(String result) async {
        view.result = result;
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
      }

      final signup = logic.autoSignup();
      await tester.pump();
      if (outcome == 'skip' || outcome == 'storage-failed') {
        store.failWrites = outcome == 'storage-failed';
        await poll('username-skipped');
        expect(
          store.registrationWrites,
          outcome == 'skip' ? 1 : greaterThanOrEqualTo(1),
        );
        expect(
          store.entries.singleWhere((row) => row.id == id).statusAccount,
          outcome == 'skip'
              ? AccountStatus.registered
              : AccountStatus.unregistered,
        );
        await poll('username-skipped');
        if (outcome == 'skip') expect(store.registrationWrites, 1);
        store.failWrites = false;
        await poll('signup-success');
      } else {
        await poll(outcome);
      }
      await signup;
      final registered = [
        'skip',
        'signup-success',
        'already-logged-in',
        'storage-failed',
      ].contains(outcome);
      expect(
        store.entries.singleWhere((row) => row.id == id).statusAccount,
        registered ? AccountStatus.registered : AccountStatus.unregistered,
      );
      expect(store.currentId, other);
      expect(store.currentStatus, AccountStatus.unregistered);
      expect(logic.autoWatchEnabled, isFalse);
      expect(logic.loginConfirmed, isFalse);
      if (!registered) expect(store.registrationWrites, 0);
      if (outcome == 'storage-failed') {
        expect(
          notices.any((text) => text.contains('chưa lưu được trạng thái')),
          isTrue,
        );
      }
    });
  }
}
