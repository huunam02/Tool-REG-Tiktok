// Run with: node --test test/webview_privacy_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/webview_privacy.dart', `file://${__filename}`), 'utf8');
const script = source.match(/disableWebRtcScript = r'''([\s\S]*?)''';/)[1];
const gpuScript = source.match(/pixelGpuInfoScript = r'''([\s\S]*?)''';/)[1];
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

function gpuContext() {
  const calls = [];
  const ordinaryExtension = {};
  const createContext = () => class {
    constructor() { this.error = 0; this.debugEnabled = false; }
    getExtension(name) {
      calls.push(['extension', name]);
      if (name === 'OES_texture_float') return ordinaryExtension;
      if (name === 'WEBGL_debug_renderer_info') {
        this.debugEnabled = true;
        return { UNMASKED_VENDOR_WEBGL: 0x9245, UNMASKED_RENDERER_WEBGL: 0x9246 };
      }
      return null;
    }
    getSupportedExtensions() {
      return ['OES_texture_float', 'WEBGL_debug_renderer_info'];
    }
    getParameter(key) {
      if (!this || !Object.hasOwn(this, 'error')) throw new TypeError('Illegal invocation');
      calls.push(['parameter', key]);
      if ((key === 0x9245 || key === 0x9246) && !this.debugEnabled) {
        this.error = 0x0500;
        return null;
      }
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
  test(`${type} exposes Pixel identity after native extension enablement`, () => {
    const { window } = gpuContext();
    const gl = new window[type]();
    // Unsupported queries keep native errors until the extension is enabled.
    assert.equal(gl.getParameter(0x9246), null);
    assert.equal(gl.getError(), 0x0500);
    const debug = gl.getExtension('WEBGL_debug_renderer_info');
    assert.ok(debug);
    assert.equal(gl.getParameter(0x1F00), 'WebKit');
    assert.equal(gl.getParameter(0x1F01), 'WebKit WebGL');
    assert.equal(gl.getParameter(String(0x1F01)), 'WebKit WebGL');
    assert.equal(gl.getParameter(debug.UNMASKED_VENDOR_WEBGL), 'Google Inc. (ARM)');
    assert.equal(gl.getParameter(debug.UNMASKED_RENDERER_WEBGL), 'ANGLE (ARM, Mali-G715, OpenGL ES 3.2)');
    assert.equal(gl.getParameter(String(0x9246)), 'ANGLE (ARM, Mali-G715, OpenGL ES 3.2)');
    assert.equal(gl.getError(), 0);
    assert.equal(gl.getParameter(0xDEAD), null);
    assert.equal(gl.getError(), 0x0500);
    assert.throws(() => gl.getParameter.call(null, 0x9246), TypeError);
  });

  test(`${type} preserves other capabilities, extensions and protection on reinjection`, () => {
    const { window, ordinaryExtension } = gpuContext();
    const gl = new window[type]();
    assert.equal(gl.getParameter(0x0D33), 16384);
    assert.equal(gl.getExtension('OES_texture_float'), ordinaryExtension);
    assert.deepEqual(Array.from(gl.getSupportedExtensions()), ['OES_texture_float', 'WEBGL_debug_renderer_info']);
    assert.throws(() => Object.defineProperty(window[type].prototype, 'getParameter',
      { value: () => 'Android Emulator' }), TypeError);
    runInNewContext(gpuScript, { window, console: { warn() {} } });
    gl.getExtension('WEBGL_debug_renderer_info');
    assert.equal(gl.getParameter(0x9246), 'ANGLE (ARM, Mali-G715, OpenGL ES 3.2)');
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
