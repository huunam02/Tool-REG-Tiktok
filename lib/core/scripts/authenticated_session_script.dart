/// Read UI state only; never infer a session from a video author's avatar.
const String authenticatedSessionScript = r'''
() => {
  if (location.origin !== 'https://www.tiktok.com' || document.hidden ||
      /^\/(login|signup)(\/|$)/.test(location.pathname)) return false;
  const visible = element => {
    const style = getComputedStyle(element);
    return element.getClientRects().length > 0 && style.display !== 'none' &&
      style.visibility !== 'hidden' && Number(style.opacity) !== 0;
  };
  const any = selector => Array.from(document.querySelectorAll(selector)).some(visible);
  if (any('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], iframe[src*="captcha"]')) return false;
  const titles = 'h1, h2, h3, [data-e2e="login-title"], [class*="DivTitle"], [class*="DivModalTitle"]';
  const accountTitle = /^(log\s*in( to tiktok)?|sign\s*up( for tiktok)?|verify (it['’]s|it is) really you|verify (your )?(identity|email)|email verification|enter (the |your )?(verification |6[- ]digit )?code|create (a |your )?username|đăng nhập( tiktok)?|đăng ký( tiktok)?|xác minh.*|nhập mã.*|tạo tên người dùng)$/i;
  const dialogs = document.querySelectorAll('[role="dialog"], [aria-modal="true"], [data-e2e="login-modal"], [data-e2e="signup-modal"], [class*="DivModalContainer"], #idv-modal-container');
  if (Array.from(dialogs).some(dialog => visible(dialog) &&
      Array.from(dialog.querySelectorAll(titles)).some(title => visible(title) &&
        accountTitle.test((title.innerText || title.textContent || '').replace(/\s+/g, ' ').trim())))) return false;
  if (any('[data-e2e="top-login-button"], [data-e2e="nav-login-button"], [data-e2e="login-button"], [data-e2e="login-container"]')) return false;
  // In the current desktop layout profile-icon/inbox-icon stay mounted but
  // hidden. nav-messages becomes visible only in the signed-in navigation.
  return any('[data-e2e="profile-icon"], [data-e2e="top-avatar"], [data-e2e="header-avatar"], [data-e2e="nav-messages"]');
}
''';

const String checkAuthenticatedSessionScript =
    '($authenticatedSessionScript)()';
