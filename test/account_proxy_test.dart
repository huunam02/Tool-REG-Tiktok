import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/account_proxy.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/proxy_store.dart';

SavedProxy profile(
  int id, {
  String? address = 'proxy.example:8080',
  String username = '',
  String password = '',
}) => SavedProxy(
  id: id,
  name: 'Account $id',
  proxy: WebViewProxy.parse(
    address ?? '',
    username: username,
    password: password,
  ),
  userAgent: 'agent',
  account: AccountCredentials(
    email: '$id@example.com',
    password: 'password',
    mailboxPassword: 'mail',
  ),
);

void main() {
  test('accounts without a proxy can independently use the device network', () {
    final first = profile(1, address: null);
    final second = profile(2, address: null);
    validateSignupProxy(first, [first, second]);
    validateSignupProxy(second, [first, second]);
  });
  test(
    'two accounts cannot share an allocation, even by changing its password',
    () {
      final first = profile(1, username: 'allocation', password: 'old');
      final second = profile(2, username: 'allocation', password: 'new');
      expect(
        () => validateSignupProxy(second, [first, second]),
        throwsFormatException,
      );
    },
  );
  test('distinct proxies or distinct gateway allocations are allowed', () {
    final first = profile(1, username: 'a');
    final second = profile(2, username: 'b');
    final third = profile(3, address: 'another.proxy.example:8080');
    validateSignupProxy(first, [first, second, third]);
    validateSignupProxy(second, [first, second, third]);
    validateSignupProxy(third, [first, second, third]);
  });
}
