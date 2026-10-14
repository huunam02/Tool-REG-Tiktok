import 'dart:convert';

String buildAutoLoginScript({
  required String email,
  required String password,
  required bool allowSubmit,
  required int attempt,
  String otp = '',
  int? otpRequestedAt,
  int? emailVerificationRequestedAt,
  bool allowOtpSubmit = true,
  bool waitForOtpApi = false,
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
          'emailVerificationRequestedAt': emailVerificationRequestedAt,
          'allowOtpSubmit': allowOtpSubmit,
          'waitForOtpApi': waitForOtpApi,
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
  const modalSelector = '[role="dialog"], [aria-modal="true"], ' +
    '[data-e2e="login-modal"], [data-e2e="signup-modal"], [class*="DivModalContainer"]';
  const headingSelector = 'h1, h2, h3, [data-e2e="login-title"], ' +
    '[class*="DivTitle"], [class*="DivModalTitle"]';
  const controlText = el => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const identityTitle = /^(verify (it['’]s|it is) really you|verify (your )?identity|xác minh (danh tính|đó thực sự là bạn))$/i;
  const codeTitle = /^(verify (your )?email|email verification|enter (the |your )?(verification |6[- ]digit )?code|nhập mã( xác minh)?|xác minh email)$/i;
  const verificationActive = () => !allowSubmit || config.otpRequestedAt != null ||
    config.emailVerificationRequestedAt != null ||
    window.__flutterAutoLogin?.attempt === config.attempt &&
      (window.__flutterAutoLogin.submitted || window.__flutterAutoLogin.emailVerificationSelected ||
        window.__flutterAutoLogin.codeRequest || window.__flutterAutoLogin.otpRequestedAt != null) ||
    !!find('#idv-modal-container') && (hasTitle(find('#idv-modal-container'), identityTitle) ||
      hasTitle(find('#idv-modal-container'), codeTitle));
  const hasTitle = (root, pattern) => Array.from(root.querySelectorAll(headingSelector))
    .some(el => visible(el) && pattern.test(controlText(el)));
  const dialog = () => {
    const idv = find('#idv-modal-container');
    if (idv && (hasTitle(idv, identityTitle) || hasTitle(idv, codeTitle))) return idv;
    const modals = Array.from(document.querySelectorAll(modalSelector)).filter(visible);
    // The identity dialog can overlay the original Log in dialog on Home.
    return verificationActive() && modals.slice().reverse().find(el =>
      hasTitle(el, identityTitle) || hasTitle(el, codeTitle)) || modals[0];
  };
  const loginFormVisible = () => {
    const modal = dialog();
    if (modal) {
      return hasTitle(modal, /^(log\s*in( to tiktok)?|đăng nhập( tiktok)?)$/i) ||
        verificationActive() && (hasTitle(modal, identityTitle) || hasTitle(modal, codeTitle));
    }
    return location.pathname.startsWith('/login') || !!find('[data-e2e="login-container"]');
  };
  const findForm = (selector) => loginFormVisible() ?
    Array.from((dialog() || document).querySelectorAll(selector)).find(visible) : null;

  if (find('[data-e2e="profile-icon"]')) {
    return allowSubmit ? 'already-logged-in' : 'login-success';
  }
  if (find('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], ' +
      'iframe[src*="captcha"]')) {
    return 'verification-required';
  }
  if (loginFormVisible() && Array.from((dialog() || document).querySelectorAll(
    'p, div, span, [role="alert"]'
  )).some(el => {
    const text = controlText(el);
    return visible(el) && text.length < 240 &&
      /^(maximum number of attempts reached|too many (attempts|requests))\b/i.test(text);
  })) return 'account-rate-limited';
  const error = findForm('[data-e2e="login-error"], [role="alert"]');
  if (error?.textContent.trim()) return 'login-error';
  let state = window.__flutterAutoLogin;
  if (!state || state.attempt !== config.attempt) {
    state?.stop();
    state = {
      attempt: config.attempt, active: true, pending: null, pasted: new WeakMap(), clicked: new WeakSet(), actions: new Set(),
      codeRequest: null,
      submitted: false, otpSubmitted: false, otpRequestedAt: config.otpRequestedAt ?? null,
      emailVerificationSelected: config.emailVerificationRequestedAt != null,
      emailVerificationRequest: config.emailVerificationRequestedAt != null && config.otpRequestedAt == null
        ? { at: config.emailVerificationRequestedAt } : null,
      canPasteFromClipboard(attempt, field, text) {
        const p = this.pending;
        return this.active && !document.hidden &&
          location.origin === 'https://www.tiktok.com' &&
          loginFormVisible() && !findPhone() && !!p &&
          (attempt === undefined || attempt === this.attempt) &&
          (field === undefined || field === p.field) &&
          (text === undefined || text === p.text) &&
          p.editor.isConnected && visible(p.editor) &&
          !p.editor.disabled && !p.editor.readOnly &&
          document.activeElement === p.editor && p.editor.tagName === 'INPUT' &&
          (p.field === 'email' && p.editor === findEmail() ||
            p.field === 'password' && p.editor === findForm('input[type="password"]') ||
            p.field === 'otp' && p.editor === findVerification() &&
            this.otpRequestedAt != null);
      },
      stop() { this.active = false; this.pending = null; }
    };
    window.__flutterAutoLogin = state;
  }
  const findVerification = () => findForm('input[autocomplete="one-time-code"], input[name="code"], ' +
    'input[name="verification_code"], input[name="otp"], input[name="verifyCode"], ' +
    'input[placeholder*="code" i], input[placeholder*="mã" i]');
  const verification = findVerification();
  const findPhone = () => loginFormVisible() && Array.from((dialog() || document).querySelectorAll(
    'input[type="tel"], input[name="phone"], input[name="mobile"], input[autocomplete="tel"]'
  )).find(el => visible(el) && el !== findVerification());
  const phoneInput = findPhone();
  const otp = (config.otp || '').trim();
  const enabled = (button) => visible(button) && !button.disabled &&
    button.getAttribute('aria-disabled') !== 'true';
  const button = (pattern) => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))
    .find((element) => enabled(element) && pattern.test(element.textContent.trim()));

  const findEmail = () => findForm('input[name="username"], input[name="email"], ' +
    'input[type="email"], input[autocomplete="username"]');
  const emailInput = findEmail();
  const passwordInput = findForm('input[type="password"]');

  if (!state.active) return 'cancelled';
  if (state.pending) {
    return Date.now() - state.pending.at < 10000
      ? state.pending.field === 'otp' ? 'waiting-otp-paste' : 'waiting-paste'
      : 'paste-failed';
  }
  const clickOnce = (control, action) => {
    if (!control || !enabled(control) ||
        (action ? state.actions.has(action) : state.clicked.has(control))) return false;
    // A named step survives React replacing the DOM node. The same node may
    // legitimately be reused for password submission and then OTP submission.
    if (action) state.actions.add(action);
    else state.clicked.add(control);
    control.click();
    return true;
  };
  const sendCodePattern = /^(send code|send verification code|gửi mã|gửi mã xác minh)$/i;
  const codeControls = () => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))
    .filter(visible);
  const codeRequestResult = () => {
    const request = state.emailVerificationRequest || state.codeRequest;
    const controls = codeControls();
    const acknowledged = verification && !controls.some(el => sendCodePattern.test(controlText(el))) ||
      controls.some(el => /^(resend( code)?|send (code )?again|gửi lại( mã)?)(\b|\s|\()/i.test(controlText(el)) ||
        /^(\d+\s*s|resend.*\d|send.*\d+\s*s|gửi lại.*\d)/i.test(controlText(el)));
    if (acknowledged) {
      state.otpRequestedAt = request.at;
      state.emailVerificationRequest = null;
      state.codeRequest = null;
      return 'verification-requested';
    }
    return Date.now() - request.at >= 15000
      ? 'verification-request-failed' : 'requesting-verification';
  };
  if (state.emailVerificationRequest || state.codeRequest) return codeRequestResult();
  const verificationModal = dialog();
  if (verificationActive() && verificationModal && hasTitle(verificationModal, identityTitle) && !verification) {
    if (state.emailVerificationSelected || state.otpSubmitted || config.allowOtpSubmit === false) return 'waiting-result';
    // IDV's list, row and content all have the same text. Only the row owns
    // the click handler; clicking its parent list does not bubble down to it.
    const isEmailMethod = el => enabled(el) &&
      /^e-?mail\s*([^\s@]+@[^\s@]+\.[^\s@]+)?$/i.test(controlText(el));
    const idvRow = Array.from(verificationModal.querySelectorAll('[class*="pc-home-item-"]'))
      .find(isEmailMethod);
    const semanticMethod = Array.from(verificationModal.querySelectorAll(
      'button, [role="button"], a, [role="link"]'
    )).find(isEmailMethod);
    const methods = Array.from(verificationModal.querySelectorAll(
      'div, span'
    )).filter(isEmailMethod).reverse();
    const emailMethod = idvRow || semanticMethod ||
      methods.find(el => /@/.test(controlText(el))) || methods[0];
    if (!emailMethod) return 'waiting-form';
    state.emailVerificationSelected = true;
    state.emailVerificationRequest = { at: Date.now() };
    clickOnce(emailMethod, 'select-verification-email');
    return 'email-verification-selected';
  }
  // Open Login through Home's Account icon. Its dialog can keep the Home URL.
  if (!loginFormVisible()) {
    if (!allowSubmit || state.submitted) return 'waiting-result';
    if (!dialog()) {
      const account = find('[data-e2e="nav-profile"], [data-e2e="nav-account"], ' +
        '[data-e2e="account-icon"], a[href^="/profile"], ' +
        '[aria-label="Account"], [aria-label="Profile"], [aria-label="Tài khoản"], [aria-label="Hồ sơ"]') ||
        Array.from(document.querySelectorAll('a, button, [role="button"], [role="link"]'))
          .find(el => enabled(el) && /^(account|profile|tài khoản|hồ sơ)$/i.test(el.textContent.trim()));
      if (account && enabled(account)) clickOnce(account, 'open-account');
    }
    return 'waiting-form';
  }
  // Switch away from phone login before entering credentials or requesting OTP.
  if (phoneInput || !emailInput && !verification && state.otpRequestedAt == null) {
    if (!allowSubmit || state.submitted) return 'waiting-result';
    const controls = Array.from((dialog() || document).querySelectorAll(
      'a, button, [role="tab"], [role="button"], [role="link"], ' +
      '[data-e2e="login-email-tab"], [data-e2e="channel-item"]'
    ));
    const emailTab = controls.find(el => enabled(el) &&
      /^(username or e-?mail|e-?mail or username|(use|log\s*in with) (e-?mail or username|username or e-?mail)|đăng nhập bằng (email hoặc tên người dùng|tên người dùng hoặc email))$/i.test(el.textContent.trim()));
    if (emailTab) {
      clickOnce(emailTab, 'select-email-tab');
      return 'waiting-form';
    }
    if (phoneInput) return 'waiting-form';
    const method = controls.find(el => enabled(el) &&
      /^(use phone or email|use phone\s*\/\s*email(\s*\/\s*username)?|sử dụng số điện thoại hoặc email)$/i.test(el.textContent.trim()));
    clickOnce(method, 'select-login-method');
    return 'waiting-form';
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
      // Commit the native editor before checking validation and Continue.
      if (pasted === true && document.activeElement === editor) editor.blur?.();
    };
    request.then(complete).catch(() => complete(false));
    return 'waiting-paste';
  };
  // A code challenge can follow a password submission. Handle it even when
  // Flutter has already latched the first submission, without requesting again.
  const sendCodeControl = Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))
    .find(element => visible(element) && sendCodePattern.test(element.textContent.trim()));
  const sendCode = sendCodeControl && enabled(sendCodeControl) ? sendCodeControl : null;
  if (state.otpRequestedAt == null && config.otpRequestedAt != null) {
    state.otpRequestedAt = config.otpRequestedAt;
  }
  if (verification && !otp && !config.waitForOtpApi && (!sendCodeControl || !allowSubmit)) return 'verification-required';
  if (verification && state.otpRequestedAt == null && (!sendCodeControl || !allowSubmit)) {
    state.otpRequestedAt = Date.now();
  }
  if (state.otpRequestedAt != null) {
    if (!otp) return config.waitForOtpApi ? 'otp-required' : 'verification-required';
    if (state.otpSubmitted || config.allowOtpSubmit === false) return 'waiting-result';
    if (!verification || verification.disabled || verification.readOnly) return 'waiting-otp';
    const result = paste(verification, 'otp', otp);
    if (result) return result === 'waiting-paste' ? 'waiting-otp-paste' : result;
    const verify = button(/^(log\s*in|verify|confirm|continue|next|đăng nhập|xác minh|xác nhận|tiếp tục|tiếp theo)$/i);
    if (!verify) return 'waiting-submit';
    state.otpSubmitted = true;
    clickOnce(verify, 'submit-otp');
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
    state.codeRequest = { at: Date.now() };
    clickOnce(sendCode, 'send-code');
    return codeRequestResult();
  }
  if (sendCodeControl) return 'waiting-submit';
  if (verification) return 'verification-required';

  // Stay inside the password form so a signup/third-party button is not used.
  const root = passwordInput.closest('form') || passwordInput.parentElement
    ?.closest('[data-e2e="login-container"]') || dialog() || document;
  const submit = Array.from(root.querySelectorAll('button, [role="button"]'))
    .find((button) => visible(button) && !button.disabled &&
      button.getAttribute('aria-disabled') !== 'true' &&
      (button.getAttribute('data-e2e') === 'login-button' ||
        /^(log\s*in|continue|đăng nhập|tiếp tục)$/i.test(button.textContent.trim())));
  if (!submit) return 'waiting-submit';
  // Latch before clicking in case navigation interrupts the result delivery.
  state.submitted = true;
  clickOnce(submit, 'submit-password');
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
