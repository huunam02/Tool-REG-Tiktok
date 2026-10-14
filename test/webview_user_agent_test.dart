import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/webview_user_agent.dart';

void main() {
  const nativeIphone =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
  const configured =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

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
    'iOS keeps different selected identities instead of collapsing to native Safari',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var nativeReads = 0;
      Future<String> loadNative() async {
        nativeReads++;
        return nativeIphone;
      }

      final next = configured.replaceAll('Chrome/140', 'Chrome/139');
      expect(
        await resolveWebViewUserAgent(
          configured,
          nativeAgentLoader: loadNative,
        ),
        configured,
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
    'Android uses the installed Chromium version when no UA is configured',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final agent = await resolveWebViewUserAgent(
        '',
        nativeAgentLoader: () async =>
            'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_arm64; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/154.0.8037.107 Mobile Safari/537.36',
      );
      expect(
        agent,
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
      );
      expect(agent, isNot(contains('Mobile')));
      expect(agent, isNot(contains(' wv')));
    },
  );

  test(
    'Android keeps each selected UA instead of replacing it with native Linux',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var nativeReads = 0;
      for (final agent in [
        configured,
        configured.replaceFirst(
          'Windows NT 10.0; Win64; x64',
          'Macintosh; Intel Mac OS X 10_15_7',
        ),
      ]) {
        expect(
          await resolveWebViewUserAgent(
            agent,
            nativeAgentLoader: () async {
              nativeReads++;
              return 'Chrome/154.0.8037.107';
            },
          ),
          agent,
        );
      }
      expect(nativeReads, 0);
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
