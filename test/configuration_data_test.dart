import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/configuration_data.dart';

void main() {
  const record =
      '192.0.2.7:6149:proxy-user:proxy-pass person@example.com|TikTok-password|Mailbox-password';

  test('imports proxy and all account credentials as one record', () {
    final data = ImportedConfiguration.parse(record);
    expect(data.proxy.uri.host, '192.0.2.7');
    expect(data.proxy.uri.port, 6149);
    expect(data.proxy.username, 'proxy-user');
    expect(data.proxy.password, 'proxy-pass');
    expect(data.account.email, 'person@example.com');
    expect(data.account.password, 'TikTok-password');
    expect(data.account.mailboxPassword, 'Mailbox-password');
  });

  test('preserves password characters and copied line endings', () {
    final data = ImportedConfiguration.parse(
      '\r\n192.0.2.7:8080:user:pass:word person@example.com|  tiktok password  | mailbox password \r\n',
    );
    expect(data.proxy.password, 'pass:word');
    expect(data.account.password, '  tiktok password  ');
    expect(data.account.mailboxPassword, ' mailbox password ');
  });

  test(
    'rejects incomplete or multiple records and separators other than one space',
    () {
      for (final invalid in [
        '',
        '192.0.2.7:8080:user:pass',
        'person@example.com|password|mailbox',
        record.replaceFirst(' person', '  person'),
        record.replaceFirst(' person', '\tperson'),
        '$record\n$record',
        record.replaceFirst(':6149:', ':65536:'),
        record.replaceFirst('person@example.com', 'not-email'),
        record.replaceFirst('|TikTok-password|', '||'),
        record.replaceFirst('|Mailbox-password', '|   '),
        '$record|extra',
      ]) {
        expect(
          () => ImportedConfiguration.parse(invalid),
          throwsFormatException,
        );
      }
    },
  );
}
