import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'proxy_local_ip.dart';

// Advertise a Pixel 9 Pro XL WebGL identity while preserving native rendering.
// This is page/frame emulation, not GPU/driver or worker emulation.
const pixelGpuInfoScript = r'''
(() => {
  for (const Context of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
    if (!Context) continue;
    const prototype = Context.prototype;
    const parameter = prototype.getParameter;
    if (typeof parameter !== 'function') continue;
    try {
      Object.defineProperty(prototype, 'getParameter', {
        value: function getParameter(name) {
          const key = name >>> 0;
          // Query the native context first: preserve extension enablement,
          // invalid-enum errors, receiver validation and context-loss behavior.
          const value = Reflect.apply(parameter, this, [key]);
          if (value === null) return null;
          if (key === 0x1F00) return 'WebKit';
          if (key === 0x1F01) return 'WebKit WebGL';
          if (key === 0x9245) return 'ARM';
          if (key === 0x9246) return 'Mali-G715';
          return value;
        },
        writable: false, configurable: false,
      });
    } catch (_) {
      console.warn('Unable to configure Pixel WebGL information');
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

UserScript pixelGpuInfoUserScript() => UserScript(
  source: pixelGpuInfoScript,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
  contentWorld: ContentWorld.PAGE,
  allowedOriginRules: {'*'},
);

// Block ICE gathering entirely so neither real nor synthetic Local IPs are
// exposed. Apply before page scripts in every document, including frames.
const disableWebRtcScript = r'''
(() => {
  for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection',
    'mozRTCPeerConnection', 'RTCIceGatherer', 'RTCIceTransport']) {
    try {
      Object.defineProperty(window, name, {
        value: undefined, writable: false, configurable: false,
      });
    } catch (_) { console.warn('Unable to disable WebRTC API: ' + name); }
  }
})();
''';

String webRtcLocalIpScript(String localIp) {
  if (!isSimulatedLocalIp(localIp)) {
    throw const FormatException(
      'Local IP mô phỏng phải thuộc dải 10.x, 172.16–31.x hoặc 192.168.x (host 1–254).',
    );
  }
  // Retain compatibility with saved profiles without injecting their address.
  return disableWebRtcScript;
}

UserScript disableWebRtcUserScript({
  String localIp = defaultSimulatedLocalIp,
}) => UserScript(
  source: webRtcLocalIpScript(localIp),
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
  contentWorld: ContentWorld.PAGE,
  allowedOriginRules: {'*'},
);
