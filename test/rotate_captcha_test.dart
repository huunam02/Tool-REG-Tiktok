import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test_tiktok/core/rotate_captcha.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

const challenge = RotateCaptchaChallenge(
  outer: 'data:image/png;base64,AQID',
  inner: 'data:image/png;base64,BAUG',
  viewportWidth: 1000,
  viewportHeight: 2000,
  x: 200,
  y: 500,
  travel: 600,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('x-slayer/accessibility_channel');
  final gestures = <MethodCall>[];
  setUp(() {
    gestures.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'signupSnapshot') {
            return {
              'ready': true,
              'webBounds': [50, 100, 850, 1700],
            };
          }
          if (call.method == 'dispatchGesture') gestures.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'posts base64 pair and scales CSS drag into physical screen pixels',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.host, 'www.sadcaptcha.com');
        expect(request.url.path, '/api/v1/rotate');
        expect(request.url.queryParameters, {'licenseKey': 'test-key'});
        expect(request.followRedirects, isFalse);
        expect(jsonDecode(request.body), {
          'outerImageB64': 'AQID',
          'innerImageB64': 'BAUG',
        });
        return http.Response('{"angle":180}', 200);
      });
      var confirmations = 0;
      final solved = await RotateCaptchaSolver(client: client).solve(
        licenseKey: 'test-key',
        read: () async => challenge,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => ++confirmations == 1,
      );
      expect(solved, isTrue);
      expect(confirmations, 3); // A remaining CAPTCHA never counts as solved.
      expect(gestures.single.arguments, {
        'strokes': [
          {
            'path': [
              {'x': 210.0, 'y': 500.0},
              {'x': 450.0, 'y': 500.0},
            ],
            'startTime': 0,
            'duration': 450,
          },
        ],
      });
    },
  );

  test(
    'desktop modal maps to the small WebView without fixed screenshot points',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'signupSnapshot') {
              return {
                'ready': true,
                'webBounds': [0, 0, 318, 636],
              };
            }
            if (call.method == 'dispatchGesture') gestures.add(call);
            return true;
          });
      final c = RotateCaptchaChallenge.fromResult({
        'outer': challenge.outer,
        'inner': challenge.inner,
        'viewportWidth': 1000,
        'viewportHeight': 2000,
        'x': 338,
        'y': 1138,
        'travel': 284,
      })!;
      final solver = RotateCaptchaSolver(
        client: MockClient((_) async => http.Response('{"angle":180}', 200)),
      );
      expect(
        await solver.solve(
          licenseKey: 'key',
          read: () async => c,
          accessibility: SignupAccessibility(),
          isPresent: () async => false,
          guard: () async {},
          onStatus: (_) {},
        ),
        isTrue,
      );
      final strokes = (gestures.single.arguments as Map)['strokes'] as List;
      final points = strokes.single['path'] as List;
      expect(points[0]['x'], closeTo(107.484, .001));
      expect(points[0]['y'], closeTo(361.884, .001));
      expect(points[1]['x'], closeTo(152.64, .001));
      expect(points[1]['y'], closeTo(361.884, .001));
    },
  );

  test('visible CAPTCHA times out without repeating API or drag', () async {
    var requests = 0;
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async {
        requests++;
        return http.Response('{"angle":180}', 200);
      }),
    );
    await expectLater(
      solver.solve(
        licenseKey: 'key',
        read: () async => challenge,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => true,
      ),
      throwsStateError,
    );
    expect(requests, 1);
    expect(gestures, hasLength(1));
  });

  test(
    'rejects missing or out-of-range angles without dispatching a drag',
    () async {
      for (final body in [
        '{}',
        '{"angle":-1}',
        '{"angle":361}',
        '{"angle":"180"}',
      ]) {
        final solver = RotateCaptchaSolver(
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          solver.solve(
            licenseKey: 'key',
            read: () async => challenge,
            accessibility: SignupAccessibility(),
            guard: () async {},
            onStatus: (_) {},
            isPresent: () async => true,
          ),
          throwsStateError,
        );
      }
      expect(gestures, isEmpty);
    },
  );

  test('rejects API failure without dispatching a drag', () async {
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    );
    await expectLater(
      solver.solve(
        licenseKey: 'key',
        read: () async => challenge,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => true,
      ),
      throwsStateError,
    );
    expect(gestures, isEmpty);
  });

  test('does not drag a replaced challenge', () async {
    var reads = 0;
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async => http.Response('{"angle":180}', 200)),
    );
    await expectLater(
      solver.solve(
        licenseKey: 'key',
        read: () async => ++reads == 1 ? challenge : null,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => true,
      ),
      throwsStateError,
    );
    expect(gestures, isEmpty);
  });

  test('cancellation during API request prevents a late gesture', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    var active = true;
    final solver = RotateCaptchaSolver(
      client: MockClient((_) {
        started.complete();
        return pending.future;
      }),
    );
    final result = solver.solve(
      licenseKey: 'key',
      read: () async => challenge,
      accessibility: SignupAccessibility(),
      guard: () async {
        if (!active) throw StateError('cancelled');
      },
      onStatus: (_) {},
      isPresent: () async => true,
    );
    await started.future;
    active = false;
    final expectation = expectLater(result, throwsStateError);
    pending.complete(http.Response('{"angle":180}', 200));
    await expectation;
    expect(gestures, isEmpty);
  });

  test(
    'closing a solver cancels immediately and prevents a late gesture',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final solver = RotateCaptchaSolver(
        client: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      final result = solver.solve(
        licenseKey: 'key',
        read: () async => challenge,
        accessibility: SignupAccessibility(),
        isPresent: () async => true,
        guard: () async {},
        onStatus: (_) {},
      );
      await started.future;
      final expectation = expectLater(
        result,
        throwsA(isA<RotateCaptchaCancelled>()),
      );
      solver.close();
      await expectation;
      pending.complete(http.Response('{"angle":180}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(gestures, isEmpty);
    },
  );

  test('supports HTTPS image URLs and strips data URI prefixes', () async {
    final c = RotateCaptchaChallenge.fromResult({
      'outer': 'https://images.example/outer.png',
      'inner': challenge.inner,
      'viewportWidth': 1000,
      'viewportHeight': 2000,
      'x': 200,
      'y': 500,
      'travel': 600,
    })!;
    final solver = RotateCaptchaSolver(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        expect(jsonDecode(request.body)['outerImageB64'], 'AQID');
        return http.Response('{"angle":360}', 200);
      }),
    );
    addTearDown(solver.close);
    expect(await solver.angle(c, 'key'), 360);
  });

  test('skips absent CAPTCHA without using API or Accessibility', () async {
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async => throw StateError('unexpected API')),
    );
    expect(
      await solver.solve(
        licenseKey: 'key',
        read: () async => null,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => false,
      ),
      isFalse,
    );
    expect(gestures, isEmpty);
  });
}
