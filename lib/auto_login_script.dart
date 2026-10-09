import 'dart:convert';

String buildAutoLoginScript({
  required String email,
  required String password,
  required bool allowSubmit,
  required int attempt,
}) =>
    '''
(() => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  return ($autoLoginStepScript)(
    ${jsonEncode({
          'email': email,
          'password': password,
          'attempt': attempt
        })}, $allowSubmit
  );
})();
''';

// Polled by Flutter while the login action is active. Credentials stay local
// to this call; Flutter remembers submission across full-page navigations.
const String autoLoginStepScript = r'''
(config, allowSubmit) => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  const visible = (element) => {
    const style = getComputedStyle(element);
    return element.getClientRects().length > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      Number(style.opacity) !== 0;
  };
  const find = (selector) => Array.from(document.querySelectorAll(selector))
    .find(visible);

  if (find('[data-e2e="profile-icon"]')) {
    return allowSubmit ? 'already-logged-in' : 'login-success';
  }
  if (find('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], ' +
      'iframe[src*="captcha"], input[autocomplete="one-time-code"], ' +
      'input[name="code"], input[name="verification_code"]')) {
    return 'verification-required';
  }
  if (!location.pathname.startsWith('/login')) return 'waiting-form';
  const error = find('[data-e2e="login-error"], [role="alert"]');
  if (error?.textContent.trim()) return 'login-error';
  if (window.__flutterAutoLogin?.attempt === config.attempt &&
      window.__flutterAutoLogin.submitted) return 'submitted';
  if (!allowSubmit) return 'waiting-result';

  const emailInput = find('input[name="username"], input[name="email"], ' +
    'input[type="email"], input[autocomplete="username"]');
  const passwordInput = find('input[type="password"]');
  if (!emailInput || !passwordInput) return 'waiting-form';

  // React-controlled inputs need the native setter and bubbling input events.
  const setter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype, 'value'
  ).set;
  const fill = (input, value) => {
    if (input.value === value) return;
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  };
  fill(emailInput, config.email);
  fill(passwordInput, config.password);

  // Stay inside the password form so a signup/third-party button is not used.
  const root = passwordInput.closest('form') || passwordInput.parentElement
    ?.closest('[data-e2e="login-container"]') || document;
  const submit = Array.from(root.querySelectorAll('button, [role="button"]'))
    .find((button) => visible(button) && !button.disabled &&
      button.getAttribute('aria-disabled') !== 'true' &&
      (button.getAttribute('data-e2e') === 'login-button' ||
        /^(log\s*in|đăng nhập)$/i.test(button.textContent.trim())));
  if (!submit) return 'waiting-submit';
  // Latch before clicking in case navigation interrupts the result delivery.
  window.__flutterAutoLogin = { attempt: config.attempt, submitted: true };
  submit.click();
  return 'submitted';
}
''';
