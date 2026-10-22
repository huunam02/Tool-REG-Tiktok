// Block ICE gathering entirely so no Local IP is ever exposed. Always applied
// before page scripts in every document, including frames.
//
// Document-start scripts never run in a same-origin about:blank frame or
// popup, whose fresh globals a page can use at once (verified leaking on
// browser engines). So every such window is blocked before the page can
// reach it: on contentWindow/contentDocument, right after each DOM insertion,
// before parser-inserted scripts (MutationObserver), on window.open and on
// frame loads, recursively. Wrappers are Proxies so they stay native-looking.
const disableWebRtcScript = r'''
(() => {
  const names = ['RTCPeerConnection', 'webkitRTCPeerConnection',
    'mozRTCPeerConnection', 'RTCIceGatherer', 'RTCIceTransport'];
  const realms = new WeakSet();
  const wrap = (target, key, after) => {
    try {
      const d = target && Object.getOwnPropertyDescriptor(target, key);
      if (!d) return;
      const hook = (fn) => new Proxy(fn, {
        apply(original, self, args) {
          try { return after(Reflect.apply(original, self, args)); }
          catch (error) { after(); throw error; }
        },
      });
      if (typeof d.value === 'function') d.value = hook(d.value);
      else if (d.get || d.set) {
        if (d.get) d.get = hook(d.get);
        if (d.set) d.set = hook(d.set);
      } else return;
      Object.defineProperty(target, key, d);
    } catch (_) {}
  };
  const protect = (win) => {
    let realm;
    try { realm = win && (win.Object || win); } catch (_) { return; }
    // Cross-origin frames run this script themselves.
    if (!realm || realms.has(realm)) return;
    realms.add(realm);
    for (const name of names) {
      try {
        Object.defineProperty(win, name, {
          value: undefined, writable: false, configurable: false,
        });
      } catch (_) { console.warn('Unable to disable WebRTC API: ' + name); }
    }
    const frames = (value) => {
      try {
        for (let i = 0; i < win.length; i++) protect(win[i]);
      } catch (_) {}
      return value;
    };
    const child = (value) => {
      try { protect(value && value.defaultView || value); } catch (_) {}
      return frames(value);
    };
    for (const type of ['HTMLIFrameElement', 'HTMLFrameElement',
      'HTMLObjectElement']) {
      const proto = win[type] && win[type].prototype;
      wrap(proto, 'contentWindow', child);
      wrap(proto, 'contentDocument', child);
    }
    const inserting = {
      Node: ['appendChild', 'insertBefore', 'replaceChild'],
      Element: ['append', 'prepend', 'after', 'before', 'replaceWith',
        'replaceChildren', 'insertAdjacentElement', 'insertAdjacentHTML',
        'setHTMLUnsafe', 'innerHTML', 'outerHTML', 'moveBefore'],
      CharacterData: ['after', 'before', 'replaceWith'],
      DocumentType: ['after', 'before', 'replaceWith'],
      Document: ['write', 'writeln', 'append', 'prepend', 'replaceChildren',
        'moveBefore', 'execCommand'],
      DocumentFragment: ['append', 'prepend', 'replaceChildren', 'moveBefore'],
      ShadowRoot: ['innerHTML', 'setHTMLUnsafe'],
      Range: ['insertNode', 'surroundContents'],
    };
    for (const [type, keys] of Object.entries(inserting)) {
      const proto = win[type] && win[type].prototype;
      for (const key of keys) wrap(proto, key, frames);
    }
    wrap(win, 'open', child);
    // Parser-inserted frames: delivered before the next inline script runs.
    try {
      new win.MutationObserver(() => frames()).observe(win.document, {
        childList: true, subtree: true,
        attributes: true, attributeFilter: ['src', 'srcdoc', 'data'],
      });
    } catch (_) {}
    try { win.addEventListener('load', () => frames(), true); } catch (_) {}
    frames();
  };
  protect(window);
})();
''';
