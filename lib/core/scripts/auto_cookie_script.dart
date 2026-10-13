/// Accept TikTok's cookie banner independently of login/signup automation.
const String autoAcceptCookieScript = r'''
(() => {
  if (location.protocol !== 'https:' ||
      !(location.hostname === 'tiktok.com' || location.hostname.endsWith('.tiktok.com'))) return false;
  if (window.__flutterCookieConsent) {
    window.__flutterCookieConsent.check();
    return true;
  }

  const labels = new Set([
    'allow all', 'allow all cookies', 'accept all', 'accept all cookies',
    'cho phép tất cả', 'cho phép tất cả cookie',
    'chấp nhận tất cả', 'chấp nhận tất cả cookie',
  ]);
  const normalize = text => (text || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const observed = new WeakSet();
  const clicked = new WeakMap();
  let pending = null;
  const schedule = () => {
    if (pending !== null) return;
    pending = setTimeout(() => {
      pending = null;
      check();
    }, 300);
  };
  const observer = new MutationObserver(schedule);
  const isCookieControl = button => {
    let node = button.parentElement || button.getRootNode().host;
    while (node && node !== document.body && node !== document.documentElement) {
      const identity = [node.localName, node.id, node.getAttribute('data-e2e'),
        node.getAttribute('aria-label')].join(' ');
      if (/cookie/i.test(identity) || /\bcookies?\b/i.test(node.textContent || '')) return true;
      node = node.parentElement || node.getRootNode().host;
    }
    return false;
  };
  const visible = button => {
    const style = getComputedStyle(button);
    return button.isConnected && button.getClientRects().length > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      style.visibility !== 'collapse' && style.opacity !== '0';
  };
  function check() {
    if (document.hidden) return;
    const roots = [document];
    for (let i = 0; i < roots.length; i++) {
      const root = roots[i];
      if (!observed.has(root)) {
        observer.observe(root, { childList: true, subtree: true, characterData: true,
          attributes: true, attributeFilter: ['class', 'style', 'hidden', 'disabled', 'aria-disabled'] });
        observed.add(root);
      }
      // TikTok can render its cookie banner inside an open shadow root.
      for (const element of root.querySelectorAll('*')) {
        if (element.shadowRoot) roots.push(element.shadowRoot);
      }
      for (const button of root.querySelectorAll('button, [role="button"]')) {
        const label = normalize(button.innerText || button.textContent || button.getAttribute('aria-label'));
        if (!labels.has(label) || button.disabled ||
            button.getAttribute('aria-disabled') === 'true' || !visible(button) ||
            !isCookieControl(button)) continue;
        const previous = clicked.get(button);
        if (previous !== undefined && Date.now() - previous < 1500) continue;
        clicked.set(button, Date.now());
        button.click();
        return;
      }
    }
  }
  window.__flutterCookieConsent = { check };
  check();
  // Also catch late shadow-root attachment and banners shown after SPA navigation.
  setInterval(check, 1500);
  return true;
})();
''';
