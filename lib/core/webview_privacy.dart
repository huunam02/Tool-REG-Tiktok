import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Hide GPU model/driver strings while keeping ordinary WebGL rendering.
// This covers page/frame contexts; workers and rendering fingerprints are not
// a device-wide privacy boundary.
const hideGpuInfoScript = r'''
(() => {
  const debugInfo = /^(?:webkit_|moz_)?webgl_debug_renderer_info$/i;
  for (const Context of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!Context) continue;
    const prototype = Context.prototype;
    const extension = prototype.getExtension;
    const extensions = prototype.getSupportedExtensions;
    const parameter = prototype.getParameter;
    if (typeof extension !== 'function' || typeof parameter !== 'function') continue;
    try {
      Object.defineProperty(prototype, 'getExtension', {
        value: function getExtension(name) {
          const requested = String(name);
          if (debugInfo.test(requested)) return null;
          return Reflect.apply(extension, this, [requested]);
        },
        writable: false, configurable: false,
      });
      if (typeof extensions === 'function') {
        Object.defineProperty(prototype, 'getSupportedExtensions', {
          value: function getSupportedExtensions() {
            const supported = Reflect.apply(extensions, this, []);
            return supported === null ? null : supported.filter(name => !debugInfo.test(name));
          },
          writable: false, configurable: false,
        });
      }
      Object.defineProperty(prototype, 'getParameter', {
        value: function getParameter(name) {
          const key = name >>> 0;
          // Use an invalid native enum to preserve the WebGL error behavior.
          if (key === 0x9245 || key === 0x9246) return Reflect.apply(parameter, this, [0]);
          const value = Reflect.apply(parameter, this, [key]);
          if (value === null) return null;
          if (key === 0x1F00 || key === 0x1F01) return '';
          return value;
        },
        writable: false, configurable: false,
      });
    } catch (_) {
      console.warn('Unable to restrict WebGL GPU information');
    }
  }
  // WebGPU exposes vendor/device details through its adapter as well.
  for (const target of [window.Navigator?.prototype, window.navigator]) {
    if (!target) continue;
    try {
      Object.defineProperty(target, 'gpu', {
        value: undefined, writable: false, configurable: false,
      });
    } catch (_) {
      console.warn('Unable to disable WebGPU');
    }
  }
})();
''';

UserScript hideGpuInfoUserScript() => UserScript(
  source: hideGpuInfoScript,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
  contentWorld: ContentWorld.PAGE,
  allowedOriginRules: {'*'},
);

// HTTP(S) proxy overrides do not protect WebRTC's ICE/STUN connections.
// Disable the page's connection APIs before it can collect local IP addresses.
// This is a page-level guard, not a device-wide network firewall.
const disableWebRtcScript = r'''
(() => {
  for (const name of [
    'RTCPeerConnection',
    'webkitRTCPeerConnection',
    'mozRTCPeerConnection',
    'RTCIceGatherer',
    'RTCIceTransport',
  ]) {
    try {
      Object.defineProperty(window, name, {
        value: undefined,
        writable: false,
        configurable: false,
      });
    } catch (_) {
      console.warn('Unable to disable WebRTC API: ' + name);
    }
  }
})();
''';

UserScript disableWebRtcUserScript() => UserScript(
  source: disableWebRtcScript,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
  contentWorld: ContentWorld.PAGE,
  allowedOriginRules: {'*'},
);
