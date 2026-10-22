import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/gecko_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_tiktok/gecko_view_42');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getUrl') return 'https://www.tiktok.com/';
          if (call.method == 'evaluateJavascript') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps browser operations to the per-view native channel', () async {
    final controller = GeckoController.test(42);
    await controller.start();
    await controller.loadUrl(
      urlRequest: GeckoUrlRequest(url: Uri.parse('https://example.com/')),
    );
    final evaluated = await controller.evaluateJavascript(source: '1 + 1');
    final url = await controller.getUrl();
    await controller.reload();

    expect(evaluated, isTrue);
    expect(url, Uri.parse('https://www.tiktok.com/'));
    expect(
      calls.map((call) => call.method),
      ['start', 'loadUrl', 'evaluateJavascript', 'getUrl', 'reload'],
    );
    expect(calls[1].arguments, {'url': 'https://example.com/'});
    expect(calls[2].arguments, {'source': '1 + 1', 'pageWorld': false});
    controller.dispose();
  });
}
