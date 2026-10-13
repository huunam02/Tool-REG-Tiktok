import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';

void main() {
  test('random signup birthdays are valid dates from 1960 through 2004', () {
    final random = Random(42);
    final birthdays = List.generate(
        10000, (_) => AppConfiguration.randomSignupBirthday(random: random));
    for (final birthday in birthdays) {
      expect(birthday.year, inInclusiveRange(1960, 2004));
      expect(
          AppConfiguration.parseBirthday(
              AppConfiguration.formatBirthday(birthday)),
          birthday);
    }
    expect(birthdays.any((birthday) => birthday.year == 1960), isTrue);
    expect(birthdays.any((birthday) => birthday.year == 2004), isTrue);
    expect(
        birthdays.any((birthday) => birthday.month == 2 && birthday.day == 29),
        isTrue);
  });

  test('proxy accepts explicit ports and rejects unsafe or malformed endpoints',
      () {
    expect(WebViewProxy.parse(' 127.0.0.1:8080 ')!.uri.toString(),
        'http://127.0.0.1:8080');
    expect(WebViewProxy.parse('https://proxy.example.com:443/')!.uri.scheme,
        'https');
    expect(WebViewProxy.parse('http://[::1]:8080')!.uri.port, 8080);
    expect(WebViewProxy.parse(''), isNull);
    for (final invalid in [
      'localhost',
      'http://localhost:0',
      'http://localhost:65536',
      'http://localhost:abc',
      'socks5://localhost:8080',
      'http://localhost:8080/path',
      'http://user:secret@localhost:8080',
      'http://local host:8080',
      'http://localhost:8080?q=1'
    ]) {
      expect(() => WebViewProxy.parse(invalid), throwsFormatException);
    }
  });

  test('birthday rejects normalized impossible dates and future dates', () {
    expect(AppConfiguration.parseBirthday('2000-02-29'), DateTime(2000, 2, 29));
    for (final invalid in [
      '',
      '2001-02-29',
      '2000-13-01',
      '2000-1-01',
      '1899-12-31',
      '2999-01-01'
    ]) {
      expect(AppConfiguration.parseBirthday(invalid), isNull);
    }
  });
}
