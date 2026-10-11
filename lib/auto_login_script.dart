import 'dart:convert';

String buildAutoLoginScript({
  required String email,
  required String password,
  required bool allowSubmit,
  required int attempt,
  String otp = '',
  int? otpRequestedAt,
  bool allowOtpSubmit = true,
}) =>
    '''
(() => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  return ($autoLoginStepScript)(
    ${jsonEncode({
          'email': email,
          'password': password,
          'attempt': attempt,
          'otp': otp.trim(),
          'otpRequestedAt': otpRequestedAt,
          'allowOtpSubmit': allowOtpSubmit,
        })}, $allowSubmit
  );
})();
''';

// Polled by Flutter while the login action is active. Credentials stay local
// to this call; Flutter pastes through the native editor and remembers submission.
const String autoLoginStepScript = r'''
(config, allowSubmit) => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  const visible = (element) => {
    const style = getComputedStyle(element);
    return element.getClientRects().length > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      Number(style.opacity) !== 0;
  };
  if (document.hidden) return 'waiting-form';
  const find = (selector) => Array.from(document.querySelectorAll(selector))
    .find(visible);

  if (find('[data-e2e="profile-icon"]')) {
    return allowSubmit ? 'already-logged-in' : 'login-success';
  }
  if (find('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], ' +
      'iframe[src*="captcha"]')) {
    return 'verification-required';
  }
  if (!location.pathname.startsWith('/login')) return 'waiting-form';
  const error = find('[data-e2e="login-error"], [role="alert"]');
  if (error?.textContent.trim()) return 'login-error';
  let state = window.__flutterAutoLogin;
  if (!state || state.attempt !== config.attempt) {
    state?.stop();
    state = {
      attempt: config.attempt, active: true, pending: null, pasted: new WeakMap(),
      submitted: false, otpSubmitted: false, otpRequestedAt: config.otpRequestedAt ?? null,
      canPasteFromClipboard(attempt, field, text) {
        const p = this.pending;
        return this.active && !document.hidden &&
          location.origin === 'https://www.tiktok.com' &&
          location.pathname.startsWith('/login') && !!p &&
          (attempt === undefined || attempt === this.attempt) &&
          (field === undefined || field === p.field) &&
          (text === undefined || text === p.text) &&
          p.editor.isConnected && visible(p.editor) &&
          !p.editor.disabled && !p.editor.readOnly &&
          document.activeElement === p.editor && p.editor.tagName === 'INPUT' &&
          (p.field === 'email' && p.editor === findEmail() ||
            p.field === 'password' && p.editor === find('input[type="password"]') ||
            p.field === 'otp' && p.editor === findVerification() &&
            this.otpRequestedAt != null && Date.now() - this.otpRequestedAt >= 5000);
      },
      stop() { this.active = false; this.pending = null; }
    };
    window.__flutterAutoLogin = state;
  }
  const findVerification = () => find('input[autocomplete="one-time-code"], input[name="code"], ' +
    'input[name="verification_code"], input[name="otp"], input[name="verifyCode"], ' +
    'input[placeholder*="code" i], input[placeholder*="mã" i]');
  const verification = findVerification();
  const otp = (config.otp || '').trim();
  const enabled = (button) => visible(button) && !button.disabled &&
    button.getAttribute('aria-disabled') !== 'true';
  const button = (pattern) => Array.from(document.querySelectorAll('button, [role="button"]'))
    .find((element) => enabled(element) && pattern.test(element.textContent.trim()));

  const findEmail = () => find('input[name="username"], input[name="email"], ' +
    'input[type="email"], input[autocomplete="username"]');
  const emailInput = findEmail();
  const passwordInput = find('input[type="password"]');

  if (!state.active) return 'cancelled';
  if (state.pending) {
    return Date.now() - state.pending.at < 10000 ? 'waiting-paste' : 'paste-failed';
  }
  const paste = (editor, field, text) => {
    if (state.pasted.get(editor)?.failed) return 'paste-failed';
    if (editor.value === text) return null;
    if (state.pasted.has(editor)) {
      return Date.now() - state.pasted.get(editor).at < 2000 ? 'waiting-paste' : 'paste-failed';
    }
    if (editor.value) return 'draft-exists';
    if (editor.disabled || editor.readOnly) return 'waiting-form';
    editor.focus();
    editor.select();
    state.pending = { editor, field, text, at: Date.now() };
    state.pasted.set(editor, { at: Date.now() });
    let request;
    try {
      request = window.flutter_inappwebview?.callHandler('FlutterLoginPaste', config.attempt, field);
    } catch (_) {}
    if (!request?.then) {
      state.pending = null;
      return 'paste-failed';
    }
    const complete = (pasted) => {
      if (!state.active || window.__flutterAutoLogin !== state) return;
      state.pending = null;
      state.pasted.set(editor, { at: Date.now(), failed: pasted !== true });
    };
    request.then(complete).catch(() => complete(false));
    return 'waiting-paste';
  };
  // A code challenge can follow a password submission. Handle it even when
  // Flutter has already latched the first submission, without requesting again.
  const sendCodePattern = /^(send code|send verification code|gửi mã|gửi mã xác minh)$/i;
  const sendCodeControl = Array.from(document.querySelectorAll('button, [role="button"]'))
    .find(element => visible(element) && sendCodePattern.test(element.textContent.trim()));
  const sendCode = sendCodeControl && enabled(sendCodeControl) ? sendCodeControl : null;
  if (state.otpRequestedAt == null && config.otpRequestedAt != null) {
    state.otpRequestedAt = config.otpRequestedAt;
  }
  if (verification && !otp && (!sendCodeControl || !allowSubmit)) return 'verification-required';
  if (verification && state.otpRequestedAt == null && (!sendCodeControl || !allowSubmit)) {
    state.otpRequestedAt = Date.now();
  }
  if (state.otpRequestedAt != null) {
    if (!otp) return 'verification-required';
    if (state.otpSubmitted || config.allowOtpSubmit === false) return 'waiting-result';
    if (Date.now() - state.otpRequestedAt < 5000) return 'waiting-otp';
    if (!verification || verification.disabled || verification.readOnly) return 'waiting-otp';
    const result = paste(verification, 'otp', otp);
    if (result) return result;
    const verify = button(/^(log\s*in|verify|confirm|continue|next|đăng nhập|xác minh|xác nhận|tiếp tục|tiếp theo)$/i);
    if (!verify) return 'waiting-submit';
    state.otpSubmitted = true;
    verify.click();
    return 'otp-submitted';
  }
  if (state.submitted) return 'submitted';
  if (!allowSubmit) return 'waiting-result';
  if (!emailInput || (!passwordInput && !sendCodeControl)) return 'waiting-form';
  const emailResult = paste(emailInput, 'email', config.email);
  if (emailResult) return emailResult;
  if (passwordInput) {
    const passwordResult = paste(passwordInput, 'password', config.password);
    if (passwordResult) return passwordResult;
  }
  if (sendCode) {
    state.otpRequestedAt = Date.now();
    sendCode.click();
    return 'verification-requested';
  }
  if (sendCodeControl) return 'waiting-submit';
  if (verification) return 'verification-required';

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
  state.submitted = true;
  submit.click();
  return 'submitted';
}
''';

String buildAutoLoginStopScript(int attempt) => '''
(() => {
  if (window.__flutterAutoLogin?.attempt === $attempt) {
    window.__flutterAutoLogin.stop();
    delete window.__flutterAutoLogin;
  }
})();
''';
