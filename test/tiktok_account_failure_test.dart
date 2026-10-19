import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/tiktok_account_failure.dart';

void main() {
  test(
    'recognizes the observed region rate limit without inventing a duration',
    () {
      final failure = TikTokAccountFailure.fromConsole(
        'Error: Maximum number of attempts reached. Try again later. get region err',
      );
      expect(failure, TikTokAccountFailure.rateLimited);
      expect(failure!.message, contains('chưa cho biết thời gian chờ'));
    },
  );

  test(
    'keeps unknown account API codes distinct from a confirmed rate limit',
    () {
      for (final message in [
        'Login: account-api error: [7] unknown.',
        'Login: email bind failed: 7 ().',
      ]) {
        final failure = TikTokAccountFailure.fromConsole(message)!;
        expect(failure.message, contains('mã 7'));
        expect(
          failure.priority,
          lessThan(TikTokAccountFailure.rateLimited.priority),
        );
        expect(failure, isNot(TikTokAccountFailure.rateLimited));
      }
    },
  );

  test('reports a region failure while discarding raw account data', () {
    final failure = TikTokAccountFailure.fromConsole(
      'Error: get region err email=private@example.com token=private-token',
    );
    expect(failure, TikTokAccountFailure.regionFailed);
    expect(failure!.message, isNot(contains('private')));
  });

  test('ignores successful certificate checks and unrelated console errors', () {
    for (final message in [
      'Indicates the evaluation succeeded and the certificate is implicitly trusted',
      'SSL error code: 4',
      'Video: Maximum number of attempts reached. Try again later.',
      'Uncaught TypeError in analytics',
      'Login: account-api request started',
    ]) {
      expect(TikTokAccountFailure.fromConsole(message), isNull);
    }
  });
}
