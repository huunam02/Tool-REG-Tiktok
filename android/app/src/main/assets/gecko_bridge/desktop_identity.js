/* global exportFunction */
(() => {
  'use strict';
  // Run synchronously at document_start in every frame. Export getters into
  // the page realm directly so CSP does not block an inline script or eval.
  const page = window.wrappedJSObject;
  const define = (target, key, value) => {
    try {
      Object.defineProperty(target, key, {
        get: exportFunction(() => value, page),
        enumerable: true,
        configurable: true,
      });
    } catch (error) {
      console.warn(`Firefox desktop identity: ${key}`, error);
    }
  };
  // hardwareConcurrency stays native: workers cannot be patched, so a window
  // value differing from theirs gives the override away.
  define(page.Navigator.prototype, 'maxTouchPoints', 0);
  // Desktop Firefox has no window.orientation, and its screen is landscape.
  for (const key of ['orientation', 'onorientationchange']) {
    try {
      delete page.Window.prototype[key];
      delete page[key];
    } catch (error) {
      console.warn(`Firefox desktop identity: ${key}`, error);
    }
  }
  define(page.ScreenOrientation.prototype, 'type', 'landscape-primary');
  define(page.ScreenOrientation.prototype, 'angle', 0);
  for (const [key, value] of Object.entries({
    width: 1536, height: 864, colorDepth: 24, pixelDepth: 24,
  })) define(page.Screen.prototype, key, value);
  define(page, 'outerWidth', 1550);
  define(page, 'outerHeight', 830);
  define(page, 'devicePixelRatio', 1);
})();
