(() => {
  'use strict';
  const port = browser.runtime.connectNative('browser');
  const pendingHandlers = new Map();

  const normalize = value => {
    if (value === undefined) return null;
    try { return JSON.parse(JSON.stringify(value)); }
    catch (_) { return String(value); }
  };

  const execute = (source, pageWorld) => {
    if (!pageWorld) return (0, eval)(source);
    try {
      if (window.wrappedJSObject?.eval) {
        return window.wrappedJSObject.eval(source);
      }
    } catch (_) {}
    const marker = `gecko-eval-${crypto.randomUUID()}`;
    const script = document.createElement('script');
    script.textContent = `window[${JSON.stringify(marker)}]=(()=>{try{return {ok:true,value:(0,eval)(${JSON.stringify(source)})}}catch(error){return {ok:false,error:String(error)}}})()`;
    (document.documentElement || document.head).appendChild(script);
    script.remove();
    const result = window.wrappedJSObject?.[marker] ?? window[marker];
    try { delete window.wrappedJSObject[marker]; } catch (_) {}
    if (!result?.ok) throw new Error(result?.error || 'Page script was blocked');
    return result.value;
  };

  // Keep the JavaScript API used by the existing automation scripts.
  Object.defineProperty(window, 'gecko_bridge', {
    configurable: false,
    value: Object.freeze({
      callHandler(name, ...args) {
        const id = crypto.randomUUID();
        port.postMessage({type: 'handler', id, name, args: normalize(args)});
        return new Promise((resolve, reject) => pendingHandlers.set(id, {resolve, reject}));
      }
    })
  });

  port.onMessage.addListener(async message => {
    if (!message || typeof message !== 'object') return;
    if (message.type === 'handlerResult') {
      const pending = pendingHandlers.get(message.id);
      if (!pending) return;
      pendingHandlers.delete(message.id);
      message.ok ? pending.resolve(message.value) : pending.reject(new Error(message.error));
      return;
    }
    if (message.type !== 'eval') return;
    try {
      const value = await execute(String(message.source || ''), message.pageWorld === true);
      port.postMessage({type: 'evalResult', id: message.id, ok: true, value: normalize(value)});
    } catch (error) {
      port.postMessage({type: 'evalResult', id: message.id, ok: false, error: String(error)});
    }
  });

  port.postMessage({type: 'ready', top: window === window.top, url: location.href});
})();
