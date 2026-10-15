import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/webview_user_agent.dart';
import 'package:test_tiktok/core/chrome_user_agent.dart';

import 'support/test_proxy_ip_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeIphone =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
  const configured =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36';

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'uses native WebKit in an explicit Mac Safari desktop UA, never iPhone mobile',
    () {
      final agent = safariDesktopUserAgent(nativeIphone)!;
      expect(agent, contains('Macintosh; Intel Mac OS X'));
      expect(agent, contains('AppleWebKit/605.1.15'));
      expect(agent, contains('Version/18.5 Safari/605.1.15'));
      expect(agent, isNot(matches('iPhone|Mobile|Chrome|Edg')));
    },
  );

  test(
    'prefers a supplied Safari version and handles the native iPad format',
    () {
      expect(
        safariDesktopUserAgent('$nativeIphone Version/18.4 Safari/604.1'),
        contains('Version/18.4 Safari/605.1.15'),
      );
      expect(
        safariDesktopUserAgent(
          nativeIphone
              .replaceAll('iPhone;', 'iPad;')
              .replaceAll('CPU iPhone OS', 'CPU OS'),
        ),
        contains('Version/18.5'),
      );
    },
  );

  test('does not invent native versions from incomplete or Chromium UAs', () {
    expect(safariDesktopUserAgent('unknown'), isNull);
    expect(safariDesktopUserAgent('AppleWebKit/605.1.15'), isNull);
    expect(safariDesktopUserAgent(configured), isNull);
  });

  test(
    'iOS normalizes Windows Chrome to macOS without reading native Safari',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var nativeReads = 0;
      Future<String> loadNative() async {
        nativeReads++;
        return nativeIphone;
      }

      final next = configured.replaceFirst(
        'Windows NT 10.0; Win64; x64',
        'Macintosh; Intel Mac OS X 10_15_7',
      );
      expect(
        await resolveWebViewUserAgent(
          configured,
          nativeAgentLoader: loadNative,
        ),
        next,
      );
      expect(
        await resolveWebViewUserAgent(next, nativeAgentLoader: loadNative),
        next,
      );
      expect(nativeReads, 0);
    },
  );

  test(
    'iOS uses native Safari desktop only when no UA was configured',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await resolveWebViewUserAgent(
          '',
          nativeAgentLoader: () async => nativeIphone,
        ),
        safariDesktopUserAgent(nativeIphone),
      );
    },
  );

  test(
    'Android advertises Chrome 155 even when the installed engine is older',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final agent = await resolveWebViewUserAgent(
        '',
        nativeAgentLoader: () async =>
            'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_arm64; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/154.0.8037.107 Mobile Safari/537.36',
      );
      expect(
        agent,
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36',
      );
      expect(agent, isNot(contains('Mobile')));
      expect(agent, isNot(contains(' wv')));
    },
  );

  test(
    'Android keeps Chrome 155 across saved identities without reading native UA',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var nativeReads = 0;
      for (final agent in [
        configured,
        configured.replaceFirst(
          'Windows NT 10.0; Win64; x64',
          'Macintosh; Intel Mac OS X 10_15_7',
        ),
        'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36',
      ]) {
        expect(
          await resolveWebViewUserAgent(
            agent,
            nativeAgentLoader: () async {
              nativeReads++;
              return 'Chrome/154.0.8037.107';
            },
          ),
          currentAndroidChromeDesktopUserAgent,
        );
      }
      expect(nativeReads, 0);
    },
  );

  test('Android normalizes a saved UA when native discovery fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      await resolveWebViewUserAgent(
        configured,
        nativeAgentLoader: () async => throw StateError('Unavailable'),
      ),
      currentAndroidChromeDesktopUserAgent,
    );
    expect(
      await resolveWebViewUserAgent(
        configured,
        nativeAgentLoader: () async => 'unknown',
      ),
      currentAndroidChromeDesktopUserAgent,
    );
  });

  for (final major in [151, 152, 153, 154, 155]) {
    test(
      'Android keeps selected Chrome $major and matching full version',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final selected = chromeDesktopUserAgent(
          'Windows NT 10.0; Win64; x64',
          major: major,
        );
        final resolved = await resolveWebViewUserAgent(selected);
        expect(
          resolved,
          chromeDesktopUserAgent('X11; Linux x86_64', major: major),
        );
        expect(chromeFullVersionForUserAgent(resolved), startsWith('$major.'));
        expect(await resolveWebViewUserAgent(resolved), resolved);
        MethodCall? nativeCall;
        const channel = MethodChannel('test_tiktok/webview_identity');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCall = call;
          return resolved;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await configureAndroidDesktopIdentity(
          InAppWebViewController.fromPlatform(
            platform: TestProxyIpController(),
          ),
          userAgent: resolved,
        );
        expect(nativeCall!.method, 'configure');
        expect(nativeCall!.arguments['userAgent'], resolved);
        expect(
          nativeCall!.arguments['chromeFullVersion'],
          recentChromeFullVersions[major],
        );
      },
    );
    test('iOS preserves selected Chrome $major', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final selected = chromeDesktopUserAgent(
        'Macintosh; Intel Mac OS X 10_15_7',
        major: major,
      );
      expect(await resolveWebViewUserAgent(selected), selected);
    });
  }

  test(
    'iOS upgrades an old built-in Chrome UA to the current stable',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await resolveWebViewUserAgent(
          configured.replaceFirst('Chrome/155', 'Chrome/140'),
        ),
        chromeDesktopUserAgent(macChromePlatform),
      );
      expect(currentChromeMajor, 155);
    },
  );

  test('iOS preserves a custom Safari UA as well as a Chromium UA', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final agent = safariDesktopUserAgent(nativeIphone)!;
    expect(
      await resolveWebViewUserAgent(
        agent,
        nativeAgentLoader: () async => 'unknown',
      ),
      agent,
    );
  });

  test(
    'native discovery failure with no configured UA returns the empty fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        await resolveWebViewUserAgent(
          '',
          nativeAgentLoader: () async => throw StateError('Unavailable'),
        ),
        '',
      );
      expect(
        await resolveWebViewUserAgent(
          '',
          nativeAgentLoader: () async => 'unknown',
        ),
        '',
      );
    },
  );
}
