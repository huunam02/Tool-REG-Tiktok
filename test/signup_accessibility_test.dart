import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fits one undistorted 1:2 frame across device sizes', () {
    for (final size in [
      const Size(412, 830),
      const Size(360, 640),
      const Size(800, 1100),
    ]) {
      final frame = SignupViewport.fit(size);
      expect(frame.width / frame.height, closeTo(0.5, 0.0001));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(size.width));
      expect(frame.bottom, lessThanOrEqualTo(size.height));
    }
  });
  test(
    'maps recorded WebView points to physical pixels including app bar offset',
    () {
      const viewport = SignupViewport(Rect.fromLTWH(24, 300, 1000, 2000));
      expect(
        viewport.toScreen(const Offset(200, 400)),
        const Offset(524, 1300),
      );
      expect(
        viewport.fromScreen(const Offset(524, 1300)),
        const Offset(200, 400),
      );
      for (final point in [
        const Offset(-1, 5),
        const Offset(400, 5),
        const Offset(5, 800),
        const Offset(double.nan, 5),
      ]) {
        expect(() => viewport.toScreen(point), throwsStateError);
      }
      expect(
        () => const SignupViewport(
          Rect.fromLTWH(0, 0, 400, 600),
        ).toScreen(const Offset(100, 100)),
        throwsStateError,
      );
    },
  );
  test(
    'paste goes through Accessibility plugin and propagates native rejection',
    () async {
      const channel = MethodChannel('x-slayer/accessibility_channel');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'ok': false, 'reason': 'draft-exists'};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final result = await SignupAccessibility().paste(
        'test@example.org',
        'email',
      );
      expect(calls.single.method, 'signupPasteFocused');
      expect(result, {'ok': false, 'reason': 'draft-exists'});
    },
  );
}
