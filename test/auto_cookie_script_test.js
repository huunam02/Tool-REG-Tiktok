// Run with: node --test test/auto_cookie_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/scripts/auto_cookie_script.dart', `file://${__filename}`), 'utf8');
const script = source.match(/autoAcceptCookieScript = r'''([\s\S]*?)''';/)[1];

function setup(hostname = 'www.tiktok.com') {
  const elements = [];
  const observed = [];
  const timeouts = [];
  const intervals = [];
  const window = {};
  const document = {
    hidden: false, body: {}, documentElement: {},
    querySelectorAll: selector => elements.filter(e => selector === '*' || e.localName === 'button'),
  };
  let mutation;
  let now = 0;
  const context = {
    window, document, location: { protocol: 'https:', hostname },
    getComputedStyle: e => ({ display: e.hidden ? 'none' : 'block', visibility: 'visible', opacity: '1' }),
    MutationObserver: class {
      constructor(callback) { mutation = callback; }
      observe(root) { observed.push(root); }
    },
    WeakSet, WeakMap,
    Date: { now: () => now },
    setTimeout: callback => { timeouts.push(callback); return timeouts.length; },
    setInterval: callback => intervals.push(callback),
  };
  const button = (label = 'Allow all', options = {}) => {
    const root = options.root || document;
    const parent = {
      localName: 'div', id: '', textContent: options.cookie === false ? 'Preferences' : 'Allow cookies from TikTok?',
      parentElement: root === document ? document.body : null,
      getAttribute: () => null, getRootNode: () => root,
    };
    const e = {
      localName: 'button', innerText: label, textContent: label,
      parentElement: parent, isConnected: true, disabled: false, hidden: false, clicks: 0,
      getAttribute: () => null, getRootNode: () => root,
      getClientRects() { return this.hidden ? [] : [{}]; },
      click() { this.clicks++; },
    };
    if (root === document) elements.push(e);
    else root.elements.push(e);
    return e;
  };
  return {
    window, document, button, elements, intervals, observed,
    run: () => runInNewContext(script, context),
    mutate: () => { mutation(); while (timeouts.length) timeouts.shift()(); },
    advance: ms => { now += ms; intervals.forEach(callback => callback()); },
  };
}

test('accepts an existing banner, leaves the decline button alone, and deduplicates injection', () => {
  const env = setup();
  const decline = env.button('Decline optional cookies');
  const allow = env.button('  Allow\nall  ');
  assert.equal(env.run(), true);
  env.run();
  env.mutate();
  assert.equal(allow.clicks, 1);
  assert.equal(decline.clicks, 0);
  assert.equal(env.intervals.length, 1);
});

test('handles a banner inserted later during signup or SPA navigation', () => {
  const env = setup();
  env.run();
  const allow = env.button();
  env.mutate();
  assert.equal(allow.clicks, 1);
});

test('accepts a banner in a shadow root attached after document load', () => {
  const env = setup();
  const host = { localName: 'tiktok-cookie-banner', shadowRoot: null };
  env.elements.push(host);
  env.run();
  const root = { host, elements: [],
    querySelectorAll(selector) { return this.elements.filter(e => selector === '*' || e.localName === 'button'); },
  };
  host.shadowRoot = root;
  const allow = env.button('Accept all', { root, cookie: false });
  Object.assign(host, { id: '', getAttribute: () => null });
  env.advance(1500);
  assert.equal(allow.clicks, 1);
  assert.ok(env.observed.includes(root));
});

test('skips hidden, disabled, unrelated and marketing controls', () => {
  const env = setup();
  const hidden = env.button(); hidden.hidden = true;
  const disabled = env.button(); disabled.disabled = true;
  const unrelated = env.button('Allow all', { cookie: false });
  const marketing = env.button('Sign up');
  env.run();
  for (const e of [hidden, disabled, unrelated, marketing]) assert.equal(e.clicks, 0);
  disabled.disabled = false;
  env.mutate();
  assert.equal(disabled.clicks, 1);
});

test('accepts Vietnamese labels and pauses when the page is hidden', () => {
  const env = setup();
  const allow = env.button('Chấp nhận tất cả');
  env.document.hidden = true;
  env.run();
  assert.equal(allow.clicks, 0);
  env.document.hidden = false;
  env.advance(1500);
  assert.equal(allow.clicks, 1);
});

test('does not install or click outside TikTok', () => {
  const env = setup('tiktok.com.example.com');
  const allow = env.button();
  assert.equal(env.run(), false);
  assert.equal(allow.clicks, 0);
  assert.equal(env.intervals.length, 0);
});
