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
    expect(data.statusAccount, AccountStatus.unregistered);
  });

  test('imports optional registration status without changing credentials', () {
    for (final suffix in ['', '|0', '|1']) {
      final data = ImportedConfiguration.parse('$record$suffix');
      expect(
        data.statusAccount,
        suffix == '|1' ? AccountStatus.registered : AccountStatus.unregistered,
      );
      expect(data.account.password, 'TikTok-password');
      expect(data.account.mailboxPassword, 'Mailbox-password');
    }
  });

  test('preserves password characters and copied line endings', () {
    final data = ImportedConfiguration.parse(
      '\r\n192.0.2.7:8080:user:pass:word person@example.com|  tiktok password  | mailbox password \r\n',
    );
    expect(data.proxy.password, 'pass:word');
    expect(data.account.password, '  tiktok password  ');
    expect(data.account.mailboxPassword, ' mailbox password ');
  });

  test('imports multiple rows with blank lines and all line ending types', () {
    final data = ImportedConfiguration.parseMany(
      '\r\n$record|1\n \n${record.replaceFirst('person@', 'second@')}|0\r'
      '${record.replaceFirst('person@', 'third@')}\r\n',
    );
    expect(data.map((row) => row.account.email), [
      'person@example.com',
      'second@example.com',
      'third@example.com',
    ]);
    expect(data.map((row) => row.statusAccount), [
      AccountStatus.registered,
      AccountStatus.unregistered,
      AccountStatus.unregistered,
    ]);
  });

  test('reports the original line number and rejects empty batches', () {
    expect(
      () => ImportedConfiguration.parseMany('$record\n\n$record|2'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          startsWith('Dòng 3:'),
        ),
      ),
    );
    expect(
      () => ImportedConfiguration.parseMany(' \r\n\n'),
      throwsFormatException,
    );
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
        '$record|2',
        '$record|',
        '$record|1|0',
      ]) {
        expect(
          () => ImportedConfiguration.parse(invalid),
          throwsFormatException,
        );
      }
    },
  );
}
