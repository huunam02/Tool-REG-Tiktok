// Run with: node --test test/webview_privacy_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/webview_privacy.dart', `file://${__filename}`), 'utf8');
const script = source.match(/disableWebRtcScript = r'''([\s\S]*?)''';/)[1];
const connectionApis = [
  'RTCPeerConnection', 'webkitRTCPeerConnection', 'mozRTCPeerConnection',
  'RTCIceGatherer', 'RTCIceTransport',
];

function rtcContext() {
  let connections = 0;
  const window = { fetch() {}, HTMLVideoElement: function () {} };
  for (const name of connectionApis) window[name] = function () { connections++; };
  const context = { window, EventTarget, Event, DOMException, setTimeout, clearTimeout, console };
  runInNewContext(script, context);
  return { window, context, nativeConnections: () => connections };
}

for (const name of connectionApis) {
  test(`${name} is unavailable and cannot gather or emit Local IPs`, () => {
    const { window, context, nativeConnections } = rtcContext();
    assert.equal(window[name], undefined);
    assert.throws(() => new window[name](), TypeError);
    assert.throws(() => Object.defineProperty(window, name, {value: function () {}}), TypeError);
    assert.equal(Reflect.deleteProperty(window, name), false);
    assert.doesNotThrow(() => runInNewContext(script, context));
    assert.equal(nativeConnections(), 0);
    assert.doesNotMatch(script, /192\.168\.|candidate:|stun:/);
  });
}

test('fresh documents and frames retain ordinary HTTP and video APIs', () => {
  for (let document = 0; document < 3; document++) {
    const { window } = rtcContext();
    assert.equal(typeof window.fetch, 'function');
    assert.equal(typeof window.HTMLVideoElement, 'function');
    assert.equal(window.RTCPeerConnection, undefined);
  }
});
