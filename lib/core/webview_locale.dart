import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Temporarily inactive. No navigation or WebView injects this override.

const englishWebViewHeaders = {'Accept-Language': 'en-US,en;q=0.9'};

// Run in each document and frame before the website chooses its language.
const englishWebViewLocaleScript = r'''
(() => {
  const languages = Object.freeze(['en-US', 'en']);
  for (const [key, value] of [['language', 'en-US'], ['languages', languages]]) {
    try {
      Object.defineProperty(navigator, key, {
        get: () => value,
        configurable: true,
      });
    } catch (_) {
      // Native locale settings still apply if the provider disallows overrides.
    }
  }
})();
''';

UserScript englishWebViewLocaleUserScript() => UserScript(
      source: englishWebViewLocaleScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
