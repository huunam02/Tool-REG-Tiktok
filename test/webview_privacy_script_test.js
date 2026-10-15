// Run with: node --test test/webview_privacy_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/webview_privacy.dart', `file://${__filename}`), 'utf8');
const script = source.match(/disableWebRtcScript = r'''([\s\S]*?)''';/)[1];
const gpuScript = source.match(/hideGpuInfoScript = r'''([\s\S]*?)''';/)[1];
const connectionApis = [
  'RTCPeerConnection', 'webkitRTCPeerConnection', 'mozRTCPeerConnection',
  'RTCIceGatherer', 'RTCIceTransport',
];

test('page cannot start ICE gathering through standard or legacy APIs', () => {
  let connections = 0;
  const window = {};
  for (const name of connectionApis) {
    window[name] = function () { connections++; };
  }
  const context = { window };
  runInNewContext(script, context);
  for (const name of connectionApis) {
    assert.equal(window[name], undefined);
    assert.throws(() => runInNewContext(`new window.${name}()`, context), { name: 'TypeError' });
    assert.throws(() => Object.defineProperty(window, name, { value: function () {} }), TypeError);
    assert.equal(Reflect.deleteProperty(window, name), false);
  }
  assert.equal(connections, 0);
  assert.doesNotThrow(() => runInNewContext(script, context));
});

test('fresh documents and frame contexts keep ordinary HTTP and video APIs', () => {
  for (let document = 0; document < 3; document++) {
    const fetch = () => {};
    const HTMLVideoElement = function () {};
    const window = { fetch, HTMLVideoElement, RTCPeerConnection: function () {} };
    runInNewContext(script, { window });
    assert.equal(window.RTCPeerConnection, undefined);
    assert.equal(window.fetch, fetch);
    assert.equal(window.HTMLVideoElement, HTMLVideoElement);
  }
});

function gpuContext() {
  const calls = [];
  const ordinaryExtension = {};
  const createContext = () => class {
    constructor() { this.error = 0; }
    getExtension(name) {
      calls.push(['extension', name]);
      return name === 'OES_texture_float' ? ordinaryExtension : {};
    }
    getSupportedExtensions() {
      return ['OES_texture_float', 'WEBGL_debug_renderer_info'];
    }
    getParameter(key) {
      calls.push(['parameter', key]);
      if (key === 0x1F00 || key === 0x9245) return 'Google (Apple)';
      if (key === 0x1F01 || key === 0x9246) return 'Android Emulator OpenGL ES Translator (Apple M1)';
      if (key === 0x0D33) return 16384;
      this.error = 0x0500;
      return null;
    }
    getError() { const value = this.error; this.error = 0; return value; }
  };
  class Navigator {}
  Object.defineProperty(Navigator.prototype, 'gpu', {
    get: () => ({ requestAdapter() { throw Error('Adapter must stay hidden'); } }),
    configurable: true,
  });
  const window = {
    WebGLRenderingContext: createContext(),
    WebGL2RenderingContext: createContext(),
    Navigator, navigator: new Navigator(),
  };
  runInNewContext(gpuScript, { window, console: { warn() {} } });
  return { window, calls, ordinaryExtension };
}

for (const type of ['WebGLRenderingContext', 'WebGL2RenderingContext']) {
  test(`${type} hides GPU strings including direct numeric enum queries`, () => {
    const { window, calls } = gpuContext();
    const gl = new window[type]();
    for (const name of ['WEBGL_debug_renderer_info', 'webgl_DEBUG_renderer_info',
      'WEBKIT_WEBGL_debug_renderer_info', 'MOZ_WEBGL_debug_renderer_info']) {
      assert.equal(gl.getExtension(name), null);
    }
    assert.equal(gl.getParameter(0x1F00), '');
    assert.equal(gl.getParameter(0x1F01), '');
    assert.equal(gl.getParameter(String(0x1F01)), '');
    for (const key of [0x9245, 0x9246, String(0x9246)]) {
      assert.equal(gl.getParameter(key), null);
      assert.equal(gl.getError(), 0x0500);
    }
    assert.equal(calls.some(([method, key]) => method === 'parameter' &&
      (key === 0x9245 || key === 0x9246)), false);
  });

  test(`${type} preserves other capabilities, extensions and protection on reinjection`, () => {
    const { window, ordinaryExtension } = gpuContext();
    const gl = new window[type]();
    assert.equal(gl.getParameter(0x0D33), 16384);
    assert.equal(gl.getExtension('OES_texture_float'), ordinaryExtension);
    assert.deepEqual(Array.from(gl.getSupportedExtensions()), ['OES_texture_float']);
    assert.throws(() => Object.defineProperty(window[type].prototype, 'getParameter',
      { value: () => 'Android Emulator' }), TypeError);
    runInNewContext(gpuScript, { window, console: { warn() {} } });
    assert.equal(gl.getParameter(0x9246), null);
  });
}

test('WebGPU adapter access is disabled on navigator and its prototype', () => {
  const { window } = gpuContext();
  assert.equal(window.navigator.gpu, undefined);
  assert.equal(window.Navigator.prototype.gpu, undefined);
  assert.equal(new window.Navigator().gpu, undefined);
  assert.throws(() => Object.defineProperty(window.navigator, 'gpu', { value: {} }), TypeError);
});

test('GPU protection also handles unsupported APIs and lost WebGL contexts', () => {
  assert.doesNotThrow(() => runInNewContext(gpuScript, { window: {}, console }));
  class LostContext {
    getExtension() { return null; }
    getSupportedExtensions() { return null; }
    getParameter() { return null; }
  }
  runInNewContext(gpuScript, { window: { WebGLRenderingContext: LostContext }, console });
  const gl = new LostContext();
  assert.equal(gl.getSupportedExtensions(), null);
  assert.equal(gl.getParameter(0x1F01), null);
});
