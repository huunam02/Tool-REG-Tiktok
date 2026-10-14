import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/send_code_accessibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dispatches an 80ms touch using the live WebView point without node events',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('x-slayer/accessibility_channel');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      final service = SendCodeAccessibility()..start();
      addTearDown(() async {
        await service.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      expect(
        await service.clickSendCode(
          getTarget: () async => const Offset(50, 20),
        ),
        isTrue,
      );
      expect(calls.single.method, 'dispatchGesture');
      expect(calls.single.arguments, {
        'strokes': [
          {
            'path': [
              {'x': 50.0, 'y': 20.0},
            ],
            'startTime': 0,
            'duration': 80,
          },
        ],
      });
      expect(service.lastFailure, isNull);
    },
  );

  test('does not tap without a current, finite, nonnegative target', () async {
    final clicks = <Offset>[];
    final service = SendCodeAccessibility(
      tap: (point) async {
        clicks.add(point);
        return true;
      },
    )..start();
    addTearDown(service.dispose);
    for (final target in <Offset?>[
      null,
      const Offset(double.nan, 20),
      const Offset(50, double.infinity),
      const Offset(-1, 20),
      const Offset(50, -1),
    ]) {
      expect(
        await service.clickSendCode(getTarget: () async => target),
        isFalse,
      );
      expect(service.lastFailure, SendCodeTapFailure.targetUnavailable);
    }
    expect(clicks, isEmpty);
  });

  test(
    'awaits Android completion and does not repeat a cancelled tap',
    () async {
      final completion = Completer<bool>();
      var clicks = 0;
      final service = SendCodeAccessibility(
        tap: (_) {
          clicks++;
          return completion.future;
        },
      )..start();
      addTearDown(service.dispose);
      var finished = false;
      final tap = service.clickSendCode(
        getTarget: () async => const Offset(50, 20),
      )..then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(clicks, 1);
      expect(
        await service.clickSendCode(
          getTarget: () async => const Offset(50, 20),
        ),
        isFalse,
      );
      completion.complete(false);
      expect(await tap, isFalse);
      expect(service.lastFailure, SendCodeTapFailure.gestureIncomplete);
      expect(clicks, 1);
    },
  );

  test(
    'disposal invalidates an in-flight target lookup even after restarting',
    () async {
      final target = Completer<Offset?>();
      var clicks = 0;
      final service = SendCodeAccessibility(
        tap: (_) async {
          clicks++;
          return true;
        },
      )..start();
      addTearDown(service.dispose);
      final result = service.clickSendCode(getTarget: () => target.future);
      await service.dispose();
      service.start();
      target.complete(const Offset(50, 20));
      expect(await result, isFalse);
      expect(clicks, 0);
      expect(
        await service.clickSendCode(
          getTarget: () async => const Offset(60, 30),
        ),
        isTrue,
      );
      expect(clicks, 1);
    },
  );

  testWidgets('reports a gesture timeout separately from a missing target', (
    tester,
  ) async {
    final completion = Completer<bool>();
    final service = SendCodeAccessibility(tap: (_) => completion.future)
      ..start();
    addTearDown(service.dispose);
    final result = service.clickSendCode(
      getTarget: () async => const Offset(50, 20),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await result, isFalse);
    expect(service.lastFailure, SendCodeTapFailure.gestureTimedOut);
    completion.complete(true);
    await tester.pump();
    expect(service.lastFailure, SendCodeTapFailure.gestureTimedOut);
  });

  test(
    'reports native target lookup failure without dispatching a gesture',
    () async {
      var clicks = 0;
      final service = SendCodeAccessibility(
        tap: (_) async {
          clicks++;
          return true;
        },
      )..start();
      addTearDown(service.dispose);
      expect(
        await service.clickSendCode(
          getTarget: () async {
            throw PlatformException(code: 'target_unavailable');
          },
        ),
        isFalse,
      );
      expect(service.lastFailure, SendCodeTapFailure.targetUnavailable);
      expect(clicks, 0);
    },
  );

  test('requires preparation before reading or tapping a target', () async {
    final service = SendCodeAccessibility(tap: (_) async => true);
    expect(
      await service.clickSendCode(
        getTarget: () async {
          fail('Must not read a target before preparation.');
        },
      ),
      isFalse,
    );
    expect(service.lastFailure, SendCodeTapFailure.notStarted);
  });
}
