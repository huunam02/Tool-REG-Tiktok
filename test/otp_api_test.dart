import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/otp_api.dart';

void main() {
  late HttpServer server;
  late OtpApiClient client;
  late List<String> logs;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    logs = [];
    client = OtpApiClient(
      OtpApiConfiguration(
        url: Uri.parse('http://127.0.0.1:${server.port}/api/code'),
        readerToken: 'test-token',
      ),
      logOutput: logs.add,
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test(
    'sends the supplied contract and preserves leading zeroes in OTP',
    () async {
      final observed = Completer<HttpRequest>();
      final body = Completer<dynamic>();
      server.listen((request) async {
        observed.complete(request);
        body.complete(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'ok': true, 'code': '012345', 'done': true}),
        );
        await request.response.close();
      });
      expect(
        await client.fetchCode(
          email: 'mail@example.com',
          password: 'mail-secret',
        ),
        '012345',
      );
      final request = await observed.future;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/code');
      expect(request.headers.value('X-Reader-Token'), 'test-token');
      expect(request.headers.value('ngrok-skip-browser-warning'), '1');
      expect(request.headers.contentType!.mimeType, 'application/json');
      expect(await body.future, {
        'email': 'mail@example.com|mail-secret',
        'wait': 180,
      });
      expect(logs.join('\n'), contains('[OTP API] REQUEST'));
      expect(logs.join('\n'), contains('[OTP API] RESPONSE'));
      expect(logs.join('\n'), contains('mail@example.com|***'));
      expect(logs.join('\n'), contains('"statusCode": 200'));
      expect(
        logs.join('\n'),
        contains('"url": "http://127.0.0.1:${server.port}/api/code"'),
      );
      expect(logs.join('\n'), contains('"code": "012345"'));
      expect(logs.join('\n'), isNot(contains('mail-secret')));
      expect(logs.join('\n'), isNot(contains('test-token')));
    },
  );

  for (final status in [400, 401, 403, 408, 409, 422, 500]) {
    test('HTTP $status fails without exposing the API error body', () async {
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = status;
        request.response.write('{"error":"mail-secret test-token"}');
        await request.response.close();
      });
      try {
        await client.fetchCode(
          email: 'mail@example.com',
          password: 'mail-secret',
        );
        fail('Expected an API failure');
      } on OtpApiException catch (error) {
        expect(error.timedOut, status == 408);
        expect(error.message, isNot(contains('mail-secret')));
        expect(error.message, isNot(contains('test-token')));
        expect(logs.join('\n'), contains('"statusCode": $status'));
        expect(logs.join('\n'), contains('[OTP API] ERROR'));
        expect(logs.join('\n'), isNot(contains('mail-secret')));
        expect(logs.join('\n'), isNot(contains('test-token')));
      }
    });
  }

  test(
    'response logs redact nested credentials without changing the returned code',
    () async {
      server.listen((request) async {
        await request.drain<void>();
        request.response.write(
          jsonEncode({
            'ok': true,
            'code': '012345',
            'detail': 'Credentials: mail-secret / test-token',
            'extra': [
              {
                'email': 'other@example.com|other-password',
                'password': 'other-password',
                'X-Reader-Token': 'other-token',
              },
            ],
          }),
        );
        await request.response.close();
      });
      expect(
        await client.fetchCode(
          email: 'mail@example.com',
          password: 'mail-secret',
        ),
        '012345',
      );
      final output = logs.join('\n');
      for (final secret in [
        'mail-secret',
        'test-token',
        'other-password',
        'other-token',
      ]) {
        expect(output, isNot(contains(secret)));
      }
      expect(output, contains('other@example.com|***'));
      expect(output, contains('"code": "012345"'));
    },
  );

  for (final body in [
    '<html>ngrok warning</html>',
    '{"ok":false,"code":"012345"}',
    '{"ok":true,"code":12345}',
    '{"ok":true,"code":"12345"}',
    '{"ok":true,"detail":"Your code is 012345"}',
  ]) {
    test('rejects malformed or unsuccessful response $body', () async {
      server.listen((request) async {
        await request.drain<void>();
        request.response.write(body);
        await request.response.close();
      });
      await expectLater(
        client.fetchCode(email: 'mail@example.com', password: 'mail-secret'),
        throwsA(isA<OtpApiException>()),
      );
    });
  }

  test('does not send mailbox credentials or token to a redirect', () async {
    var redirected = false;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/api/code') {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/other');
      } else {
        redirected = true;
      }
      await request.response.close();
    });
    await expectLater(
      client.fetchCode(email: 'mail@example.com', password: 'mail-secret'),
      throwsA(isA<OtpApiException>()),
    );
    expect(redirected, isFalse);
  });

  test('cancellation closes the reader and ignores a late code', () async {
    final reader = _ControlledReader();
    final request = OtpCodeRequest.start(
      reader,
      email: 'mail@example.com',
      password: 'mail-secret',
    );
    request.cancel();
    expect(reader.closed, isTrue);
    reader.response.complete('012345');
    await Future<void>.delayed(Duration.zero);
    expect(request.code, isNull);
    expect(request.error, isNull);
  });

  test(
    'mailbox timeout is preserved for the bounded resend decision',
    () async {
      final reader = _ControlledReader();
      final request = OtpCodeRequest.start(
        reader,
        email: 'mail@example.com',
        password: 'mail-secret',
      );
      reader.response.completeError(
        const OtpApiException('OTP wait expired', timedOut: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(request.timedOut, isTrue);
      expect(request.error, 'OTP wait expired');
      expect(reader.closed, isTrue);
    },
  );

  test('closing the HTTP client aborts an in-flight OTP request', () async {
    final received = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      received.complete();
      // Keep the response pending, as the real API does while waiting for OTP.
    });
    final pending = client.fetchCode(
      email: 'mail@example.com',
      password: 'mail-secret',
    );
    final rejected = expectLater(
      pending.timeout(const Duration(seconds: 3)),
      throwsA(isA<OtpApiException>()),
    );
    await received.future.timeout(const Duration(seconds: 3));
    client.close();
    await rejected;
  });

  test('unexpected reader failures are sanitized', () async {
    final reader = _ControlledReader();
    final request = OtpCodeRequest.start(
      reader,
      email: 'mail@example.com',
      password: 'mail-secret',
    );
    reader.response.completeError(StateError('mail-secret test-token'));
    await Future<void>.delayed(Duration.zero);
    expect(request.error, isNotNull);
    expect(request.error, isNot(contains('mail-secret')));
    expect(reader.closed, isTrue);
  });

  test(
    'URL validation accepts HTTP/HTTPS and keeps credentials out of the URL',
    () {
      expect(
        OtpApiConfiguration.parseUrl('https://example.com/api/code').host,
        'example.com',
      );
      for (final url in [
        'http://10.0.2.2:5678/api/code',
        'http://127.0.0.1:5678/api/code',
        'http://192.168.1.10:5678/api/code',
        'http://example.com/api/code',
      ]) {
        expect(OtpApiConfiguration.parseUrl(url).toString(), url);
      }
      for (final url in [
        'https://example.ngrok-free.dev',
        'https://example.ngrok-free.dev/',
      ]) {
        expect(
          OtpApiConfiguration.parseUrl(url).toString(),
          'https://example.ngrok-free.dev/api/code',
        );
      }
      for (final url in [
        'ftp://example.com/api/code',
        'http:///api/code',
        'http://token@10.0.2.2:5678/api/code',
        'https://token@example.com/api/code',
        'https://example.com/api/code#token',
        'bad-url',
      ]) {
        expect(() => OtpApiConfiguration.parseUrl(url), throwsFormatException);
      }
    },
  );
}

class _ControlledReader implements OtpCodeReader {
  final response = Completer<String>();
  bool closed = false;

  @override
  Future<String> fetchCode({required String email, required String password}) =>
      response.future;
  @override
  void close() => closed = true;
}
