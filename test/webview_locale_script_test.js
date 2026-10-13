// Run with: node --test test/webview_locale_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/webview_locale.dart', `file://${__filename}`), 'utf8');
const script = source.match(/englishWebViewLocaleScript = r'''([\s\S]*?)''';/)[1];

test('overrides device language for every new document, including reinjection', () => {
  for (const language of ['vi-VN', 'fr-FR', 'ja-JP']) {
    const navigator = Object.create({ language, languages: [language] });
    const context = { navigator };
    runInNewContext(script, context);
    runInNewContext(script, context);
    assert.equal(navigator.language, 'en-US');
    assert.deepEqual(Array.from(navigator.languages), ['en-US', 'en']);
    assert.throws(() => navigator.languages.push('vi-VN'), { name: 'TypeError' });
  }
});

test('continues setting languages when the provider locks one property', () => {
  const navigator = {};
  Object.defineProperty(navigator, 'language', { value: 'en-US', configurable: false });
  assert.doesNotThrow(() => runInNewContext(script, { navigator }));
  assert.deepEqual(Array.from(navigator.languages), ['en-US', 'en']);
});
