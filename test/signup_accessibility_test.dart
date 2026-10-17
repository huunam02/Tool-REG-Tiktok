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
  test('taps the live control on every frame size, not a stale point', () {
    SignupNode node(String id, Rect r) => SignupNode({
      'id': id,
      'enabled': true,
      'clickable': true,
      'bounds': [r.left, r.top, r.right, r.bottom],
    });
    for (final frame in [
      const Rect.fromLTWH(6, 289, 1067, 2134), // 20:9 phone
      const Rect.fromLTWH(180, 60, 720, 1440), // 16:9 phone, pillarboxed
      const Rect.fromLTWH(500, 40, 1280, 2560), // tablet
    ]) {
      final viewport = SignupViewport(frame);
      Rect design(Rect r) => Rect.fromPoints(
        viewport.toScreen(r.topLeft),
        viewport.toScreen(r.bottomRight),
      );
      final button = design(const Rect.fromLTWH(130, 450, 140, 20));
      // Recorded point still on the control: it is reused verbatim.
      expect(
        viewport.tapPoint(button, const Offset(200, 460)),
        const Offset(200, 460),
      );
      // Fonts pushed the control 30 design units lower: follow the node.
      final moved = button.shift(Offset(0, 30 * frame.height / 800));
      final point = viewport.tapPoint(moved, const Offset(200, 460));
      expect(moved.contains(viewport.toScreen(point)), isTrue);
      // Two "Log in" labels: the one near the recorded point wins.
      final header = node(
        'header',
        design(const Rect.fromLTWH(350, 10, 40, 15)),
      );
      final footer = node(
        'footer',
        design(const Rect.fromLTWH(220, 600, 40, 15)),
      );
      expect(
        viewport.nearest([footer, header], const Offset(371, 30))?.id,
        'header',
      );
      expect(viewport.nearest([footer], const Offset(371, 30)), isNull);
      // Clipped outside the frame: never tapped.
      expect(
        () => viewport.tapPoint(frame.shift(Offset(0, frame.height))),
        throwsStateError,
      );
    }
  });
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
