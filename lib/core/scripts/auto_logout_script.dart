import 'authenticated_session_script.dart';

String buildAutoLogoutScript(int attempt) =>
    '($autoLogoutStepScript)($attempt, ($authenticatedSessionScript));';

/// Use TikTok's logout controls, then positively confirm its logged-out UI.
/// Each menu, logout item and confirmation is clicked at most once per page.
const String autoLogoutStepScript = r'''
(attempt, authenticated) => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  if (document.hidden) return 'paused';
  const visible = el => {
    const style = getComputedStyle(el);
    return el.getClientRects().length > 0 && style.display !== 'none' &&
      style.visibility !== 'hidden' && Number(style.opacity) !== 0;
  };
  const all = (selector, root = document) => Array.from(root.querySelectorAll(selector)).filter(visible);
  const text = el => (el.innerText || el.textContent || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
  const enabled = el => !el.disabled && el.getAttribute('aria-disabled') !== 'true';
  if (all('#captcha-verify-container, .captcha-verify-container, .captcha-disable-scroll, [id*="captcha"], [class*="Captcha"], iframe[src*="captcha"]').length) return 'verification-required';
  // TikTok renamed its top Log in button (id, no data-e2e) and keeps the old
  // one hidden; a visible "Log in" control outside a dialog also counts.
  const login = [
    ...all('[data-e2e="top-login-button"], [data-e2e="nav-login-button"], [data-e2e="login-button"], #top-right-action-bar-login-button'),
    ...all('button, a, [role="button"]').filter(el =>
      /^(log\s*in|đăng nhập)$/i.test(text(el)) &&
      !el.closest?.('[role="dialog"], [aria-modal="true"]')),
  ];
  if (!authenticated() && login.length) return 'logged-out';
  let state = window.__flutterAutoLogout;
  if (!state || state.attempt !== attempt) {
    state = window.__flutterAutoLogout = {attempt, clicked: new WeakSet(), requested: false, confirmed: false, menuAt: null};
  }
  const controls = 'button, a, [role="button"], [role="menuitem"]';
  const logout = el => enabled(el) && /^(log\s*out|sign\s*out|đăng xuất)$/i.test(text(el));
  const findLogout = root => all(controls, root).find(logout) ||
    all('div, span', root).reverse().find(logout);
  const click = el => {
    state.clicked.add(el);
    el.click();
  };
  const dialogs = all('[role="dialog"], [aria-modal="true"], [class*="DivModalContainer"]');
  for (const dialog of dialogs) {
    const confirm = findLogout(dialog);
    if (confirm && !state.confirmed) {
      state.requested = true;
      state.confirmed = true;
      click(confirm);
      return 'confirming-logout';
    }
  }
  if (state.requested) return 'waiting-logout';
  const item = findLogout(document);
  if (item) {
    state.requested = true;
    click(item);
    return 'logout-requested';
  }
  if (state.menuAt != null && Date.now() - state.menuAt < 2000) return 'waiting-menu';
  const menus = all('[data-e2e="nav-more-menu"], [data-e2e="nav-more"], [data-e2e="top-avatar"], [data-e2e="header-avatar"], [data-e2e="profile-icon"], [aria-label="More"], [aria-label="Thêm"]');
  const more = all(controls + ', div, span').filter(el => /^(more|thêm)$/i.test(text(el)));
  const menu = [...menus, ...more].map(el => el.closest?.('button, a, [role="button"]') || el)
    .find(el => enabled(el) && !state.clicked.has(el));
  if (!menu) return 'waiting-menu';
  state.menuAt = Date.now();
  for (const type of ['mouseover', 'mouseenter', 'mousemove']) {
    menu.dispatchEvent(new MouseEvent(type, {bubbles: true, view: window}));
  }
  click(menu);
  return 'opening-menu';
}
''';
