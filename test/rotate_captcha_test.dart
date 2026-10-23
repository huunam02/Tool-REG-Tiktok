import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
          if (call.method == 'dispatchGesture' ||
              call.method == 'dispatchContinuousGesture') {
            gestures.add(call);
          }
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
      // Press, move along a human-like track, hold, release; the track
      // ends exactly on the computed target.
      expect(gestures.single.method, 'dispatchContinuousGesture');
      final raw = (gestures.single.arguments as Map)['segments'] as List;
      final segments = [
        for (final s in raw)
          [
            for (final p in s['path'] as List)
              Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
          ],
      ];
      expect(segments.first, [const Offset(210, 500)]);
      expect(segments.last, [const Offset(450, 500)]);
      for (var i = 1; i < segments.length; i++) {
        expect(segments[i].first, segments[i - 1].last); // One finger.
      }
      final track = segments.expand((s) => s);
      final overshoot = track.map((p) => p.dx).reduce(max) - 450;
      expect(overshoot, inInclusiveRange(3, 9));
      expect(track.every((p) => (p.dy - 500).abs() <= 3), isTrue);
      final duration = raw.fold<int>(
        0,
        (sum, s) => sum + (s['duration'] as int),
      );
      expect(duration, inInclusiveRange(800, 2000));
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
            if (call.method == 'dispatchContinuousGesture') {
              gestures.add(call);
            }
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
      final segments = (gestures.single.arguments as Map)['segments'] as List;
      final first = (segments.first['path'] as List).single;
      final last = (segments.last['path'] as List).single;
      expect(first['x'], closeTo(107.484, .001));
      expect(first['y'], closeTo(361.884, .001));
      expect(last['x'], closeTo(152.64, .001));
      expect(last['y'], closeTo(361.884, .001));
    },
  );

  test('waits beyond five seconds for a slowly loading CAPTCHA', () async {
    final elapsed = Stopwatch()..start();
    var requests = 0;
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async {
        requests++;
        // Stop at the API response: this test only checks loading readiness.
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      solver.solve(
        licenseKey: 'key',
        read: () async => elapsed.elapsed < const Duration(seconds: 6)
            ? null
            : challenge,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: (_) {},
        isPresent: () async => true,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'SadCaptcha trả góc xoay không hợp lệ.',
        ),
      ),
    );
    expect(requests, 1);
    expect(gestures, isEmpty);
  });

  test('closing while CAPTCHA loads cancels without an API request', () async {
    var reads = 0;
    final reading = Completer<void>();
    final solver = RotateCaptchaSolver(
      client: MockClient((_) async => throw StateError('unexpected API')),
    );
    final result = solver.solve(
      licenseKey: 'key',
      read: () async {
        reads++;
        if (!reading.isCompleted) reading.complete();
        return null;
      },
      accessibility: SignupAccessibility(),
      guard: () async {},
      onStatus: (_) {},
      isPresent: () async => true,
    );
    final expectation = expectLater(
      result,
      throwsA(isA<RotateCaptchaCancelled>()),
    );
    await reading.future;
    solver.close();
    await expectation;
    expect(reads, 1);
    expect(gestures, isEmpty);
  });

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

  test(
    'a wrong answer is retried once on a refreshed puzzle',
    () async {
      const next = RotateCaptchaChallenge(
        outer: 'data:image/png;base64,BwgJ',
        inner: 'data:image/png;base64,CgsM',
        viewportWidth: 1000,
        viewportHeight: 2000,
        x: 200,
        y: 500,
        travel: 600,
      );
      var refreshed = false, requests = 0;
      final statuses = <String>[];
      final solver = RotateCaptchaSolver(
        client: MockClient((_) async {
          requests++;
          return http.Response('{"angle":90}', 200);
        }),
      );
      final solved = await solver.solve(
        licenseKey: 'key',
        read: () async => refreshed ? next : challenge,
        accessibility: SignupAccessibility(),
        guard: () async {},
        onStatus: statuses.add,
        // The first puzzle stays until refreshed; the second drag solves it.
        isPresent: () async => gestures.length < 2,
        refresh: () async => refreshed = true,
      );
      expect(solved, isTrue);
      expect(refreshed, isTrue);
      expect(requests, 2);
      expect(gestures, hasLength(2));
      expect(statuses, contains(startsWith('CAPTCHA chưa đúng')));
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  group('refresh', () {
    void snapshot(List<Map<String, Object>> nodes) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'signupSnapshot') {
                return {
                  'ready': true,
                  'webBounds': [0, 0, 500, 1000],
                  'nodes': nodes,
                };
              }
              if (call.method == 'dispatchGesture') gestures.add(call);
              return true;
            });
    Map<String, double> tapped() => Map.from(
      ((gestures.single.arguments as Map)['strokes'] as List).single['path'][0]
          as Map,
    );

    test('taps the control Accessibility names', () async {
      snapshot([
        {
          'id': '0.4',
          'description': 'Refresh',
          'clickable': true,
          'enabled': true,
          'bounds': [300, 600, 340, 640],
        },
      ]);
      await refreshRotateCaptcha(
        accessibility: SignupAccessibility(),
        readGeometry: () async => throw StateError('unexpected JS'),
        guard: () async {},
      );
      expect(tapped(), {'x': 320.0, 'y': 620.0});
    });

    test('falls back to CSS geometry scaled into the WebView', () async {
      snapshot([]);
      await refreshRotateCaptcha(
        accessibility: SignupAccessibility(),
        readGeometry: () async => '{"viewportWidth":1000,"x":600,"y":1200}',
        guard: () async {},
      );
      expect(tapped(), {'x': 300.0, 'y': 600.0});
    });

    test('never taps without a located control', () async {
      snapshot([]);
      await expectLater(
        refreshRotateCaptcha(
          accessibility: SignupAccessibility(),
          readGeometry: () async => null,
          guard: () async {},
        ),
        throwsStateError,
      );
      expect(gestures, isEmpty);
    });
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
