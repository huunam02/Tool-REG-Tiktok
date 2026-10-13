import 'dart:convert';

String buildAutoSignupScript({
  required String email,
  required String password,
  required DateTime birthday,
  required int attempt,
  required bool allowSubmit,
  String otp = '',
  int? otpRequestedAt,
  bool allowOtpSubmit = true,
  bool allowPasswordSubmit = true,
  bool waitForOtpApi = false,
}) =>
    '''
($autoSignupStepScript)(${jsonEncode({
          'email': email,
          'password': password,
          'year': birthday.year,
          'month': birthday.month,
          'day': birthday.day,
          'attempt': attempt,
          'otp': otp.trim(),
          'otpRequestedAt': otpRequestedAt,
          'allowOtpSubmit': allowOtpSubmit,
          'allowPasswordSubmit': allowPasswordSubmit,
          'waitForOtpApi': waitForOtpApi,
        })}, $allowSubmit);
''';

// Flutter polls one step at a time. Input is entered using native clipboard
// paste; successful pastes and button clicks are remembered to avoid retries.
const String autoSignupStepScript = r'''
(config, allowSubmit) => {
  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';
  if (document.hidden) return 'waiting-form';
  const visible = (element) => {
    const style = getComputedStyle(element);
    return Array.from(element.getClientRects()).some(rect => rect.width > 0 && rect.height > 0) &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      Number(style.opacity) !== 0;
  };
  const find = (selector) => Array.from(document.querySelectorAll(selector)).find(visible);
  const dialog = () => find('[role="dialog"], [aria-modal="true"], ' +
    '[data-e2e="login-modal"], [data-e2e="signup-modal"], [class*="DivModalContainer"]');
  const signupFormVisible = () => {
    if (location.pathname.startsWith('/signup')) return true;
    if (find('[data-e2e="signup-container"]')) return true;
    const modal = dialog();
    const awaitingCode = config.otpRequestedAt != null ||
      window.__flutterAutoSignup?.attempt === config.attempt &&
        (window.__flutterAutoSignup.codeRequest || window.__flutterAutoSignup.otpRequestedAt != null);
    return !!modal && Array.from(modal.querySelectorAll(
      'h1, h2, h3, [data-e2e="signup-title"], [class*="DivTitle"], [class*="DivModalTitle"]'
    )).some(el => visible(el) &&
      (/^(sign\s*up( for tiktok)?|create (an |your )?account|đăng ký( tiktok)?)$/i.test(el.textContent.trim()) ||
        awaitingCode && /^(verify (your )?email|email verification|enter (the |your )?(verification |6[- ]digit )?code|nhập mã xác minh|xác minh email)$/i.test(el.textContent.trim())));
  };
  const findForm = (selector) => signupFormVisible() ?
    Array.from((dialog() || document).querySelectorAll(selector)).find(visible) : null;
  if (find('[data-e2e="profile-icon"]')) {
    return allowSubmit ? 'already-logged-in' : 'signup-success';
  }
  const emailInput = findForm('input[name="email"], input[type="email"], input[autocomplete="email"]');
  const passwordInput = findForm('input[type="password"]');
  const findVerification = () => findForm('input[autocomplete="one-time-code"], input[name="code"], ' +
    'input[name="verification_code"], input[name="otp"], input[name="verifyCode"], ' +
    'input[placeholder*="code" i], input[placeholder*="mã" i]');
  const verification = findVerification();
  const findPhone = () => signupFormVisible() && Array.from((dialog() || document).querySelectorAll(
    'input[type="tel"], input[name="phone"], input[name="mobile"], input[autocomplete="tel"]'
  )).find(el => visible(el) && el !== findVerification());
  const phoneInput = findPhone();
  const previousState = window.__flutterAutoSignup?.attempt === config.attempt
    ? window.__flutterAutoSignup : null;
  // Email signup can put the password on a separate screen after OTP. A
  // submitted OTP does not mean the final account form has been submitted.
  const passwordStep = !!passwordInput && !emailInput && !verification && !phoneInput &&
    (previousState?.emailEntered || previousState?.otpRequestedAt != null || config.otpRequestedAt != null);
  if (find('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], ' +
      'iframe[src*="captcha"]')) {
    return 'verification-required';
  }
  const otp = (config.otp || '').trim();
  if (verification && verification.value?.trim() && verification.value !== otp) {
    return 'verification-required';
  }
  // TikTok's existing-email warning is inline text rather than a role=alert.
  // Stop before requesting a code for an account that already exists.
  if (emailInput && Array.from((dialog() || document).querySelectorAll('p, div, span')).some((el) => {
    const text = el.textContent.trim();
    return text.length < 160 && visible(el) &&
      /^(you['’]ve already signed up|this email is already registered|email này đã (được đăng ký|tồn tại))/i.test(text);
  })) return 'email-registered';
  // The password screen renders this as plain inline text, without role=alert.
  // Inspect only the active account form, before any paste or submission.
  if (signupFormVisible() && Array.from((dialog() || document).querySelectorAll(
    'p, div, span, [role="alert"]'
  )).some(el => {
    const text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
    return visible(el) && text.length < 240 &&
      /^(maximum number of attempts reached|too many (attempts|requests))\b/i.test(text);
  })) return 'account-rate-limited';
  const error = findForm('[data-e2e="signup-error"], [role="alert"]');
  if (error?.textContent.trim()) return 'signup-error';
  if (passwordStep && (config.allowPasswordSubmit === false || previousState?.passwordSubmitted)) return 'waiting-result';
  if (!allowSubmit && !passwordStep && (!verification || !otp && !config.waitForOtpApi || config.allowOtpSubmit === false)) return 'waiting-result';

  let state = window.__flutterAutoSignup;
  if (!state || state.attempt !== config.attempt) {
    state?.stop();
    state = {
      attempt: config.attempt, active: true, pending: null,
      pasted: new WeakMap(), clicked: new WeakSet(), birthdayFields: new Set(),
      birthdayMenuIndex: null, birthdayMenuAt: 0,
      submitted: false, emailEntered: false, codeRequest: null,
      otpRequestedAt: config.otpRequestedAt ?? null, otpSubmitted: false,
      passwordSubmitted: false,
      passwordEditor: null, passwordScreenAt: null, passwordReadyAt: null,
      canPasteFromClipboard(attempt, field, text) {
        const p = this.pending;
        return this.active && !document.hidden &&
          location.origin === 'https://www.tiktok.com' &&
          signupFormVisible() && !!p &&
          (attempt === undefined || attempt === this.attempt) &&
          (field === undefined || field === p.field) &&
          (text === undefined || text === p.text) &&
          p.editor.isConnected && visible(p.editor) &&
          !p.editor.disabled && !p.editor.readOnly &&
          document.activeElement === p.editor &&
          p.editor.tagName === 'INPUT' &&
          !findPhone() &&
          (p.field === 'email' && p.editor === findForm('input[name="email"], input[type="email"], input[autocomplete="email"]') ||
            p.field === 'password' && (this.emailEntered || this.otpRequestedAt != null && !findVerification()) &&
              p.editor === findForm('input[type="password"]') ||
            p.field === 'otp' && p.editor === findVerification() &&
            this.otpRequestedAt != null);
      },
      stop() { this.active = false; this.pending = null; }
    };
    window.__flutterAutoSignup = state;
  }
  if (!state.active) return 'cancelled';
  if (state.submitted && !passwordStep && (!verification || !otp && !config.waitForOtpApi || state.otpSubmitted)) return 'submitted';
  if (state.pending) {
    return Date.now() - state.pending.at < 10000
      ? state.pending.field === 'otp' ? 'waiting-otp-paste' : 'waiting-paste'
      : 'paste-failed';
  }
  const enabled = (button) => visible(button) && !button.disabled &&
    button.getAttribute('aria-disabled') !== 'true';
  const clickOnce = (button) => {
    if (!button || state.clicked.has(button)) return false;
    state.clicked.add(button);
    button.click();
    return true;
  };
  const button = (pattern) => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))
    .find((el) => enabled(el) && pattern.test(el.textContent.trim()));
  if (state.otpRequestedAt == null && config.otpRequestedAt != null) {
    state.otpRequestedAt = config.otpRequestedAt;
  }
  const controlText = el => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const sendCodePattern = /^(send code|send verification code|gửi mã|gửi mã xác minh)$/i;
  const codeControls = () => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))
    .filter(visible);
  const codeRequestResult = () => {
    const request = state.codeRequest;
    const acknowledged = codeControls().some(el =>
      /^(resend( code)?|send (code )?again|gửi lại( mã)?)(\b|\s|\()/i.test(controlText(el)) ||
      /^(\d+\s*s|resend.*\d|send.*\d+\s*s|gửi lại.*\d)/i.test(controlText(el))) ||
      !!findVerification() && !emailInput && !passwordInput &&
        !codeControls().some(el => sendCodePattern.test(controlText(el)));
    if (acknowledged) {
      state.otpRequestedAt = request.at;
      state.codeRequest = null;
      return 'verification-requested';
    }
    // A dispatched click is not proof of delivery. Never request an API code
    // or send another click while the result of this request is unknown.
    return Date.now() - request.at >= 15000 ? 'verification-request-failed' : 'requesting-verification';
  };
  if (state.codeRequest) return codeRequestResult();

  // Start on Home and open the login dialog through the Account icon. The
  // signup dialog can keep the Home URL, so identify its visible form too.
  if (!signupFormVisible()) {
    const modal = dialog();
    if (modal || location.pathname.startsWith('/login')) {
      const signup = Array.from((modal || document).querySelectorAll(
        'a, button, [role="button"], [role="link"], [data-e2e="bottom-sign-up"], [data-e2e="signup-link"]'
      )).find(el => enabled(el) && /^(sign\s*up|đăng ký)$/i.test(el.textContent.trim()));
      clickOnce(signup);
      return 'waiting-form';
    }
    const account = find('[data-e2e="nav-profile"], [data-e2e="nav-account"], ' +
      '[data-e2e="account-icon"], a[href^="/profile"], ' +
      '[aria-label="Account"], [aria-label="Profile"], [aria-label="Tài khoản"], [aria-label="Hồ sơ"]') ||
      Array.from(document.querySelectorAll('a, button, [role="button"], [role="link"]'))
        .find(el => enabled(el) && /^(account|profile|tài khoản|hồ sơ)$/i.test(el.textContent.trim()));
    if (account && enabled(account)) clickOnce(account);
    return 'waiting-form';
  }

  // Switch method before processing birthday menus on the phone form.
  if (phoneInput || !emailInput && !state.emailEntered && state.otpRequestedAt == null) {
    const emailTab = Array.from((dialog() || document).querySelectorAll(
      'a, button, [role="tab"], [role="button"], [data-e2e="signup-email-tab"]'
    )).find((el) => enabled(el) && /^(email|e-mail|sign up with (email|e-mail)|use (email|e-mail)|đăng ký bằng (email|e-mail)|sử dụng (email|e-mail))$/i.test(el.textContent.trim()));
    if (emailTab) {
      clickOnce(emailTab);
      return 'waiting-form';
    }
    if (phoneInput) return 'waiting-form';
  }

  // Opt in to the newsletter checkbox requested by the user. The input can
  // be visually hidden; its visible label identifies this specific option.
  if (emailInput && !phoneInput && state.otpRequestedAt == null) {
    const newsletterLabel = Array.from((dialog() || document).querySelectorAll('label')).find(el =>
      visible(el) && /^(get trending content, newsletters|nhận.*(bản tin|khuyến mãi))/i.test(el.textContent.trim()));
    const newsletterCheckbox = newsletterLabel?.control ||
      newsletterLabel?.parentElement?.querySelector('input[type="checkbox"]');
    if (newsletterCheckbox?.type === 'checkbox' && !newsletterCheckbox.checked) {
      if (newsletterCheckbox.disabled) return 'waiting-form';
      if (!clickOnce(newsletterCheckbox)) return 'checkbox-failed';
      return 'waiting-form';
    }
  }

  // Birthday controls can share the same page as the email/password inputs.
  // Complete them before entering credentials on either layout.
  const birthdayRoot = findForm('[class*="DivAgeSelector"], [data-e2e="birthday-selector"]');
  const fields = Array.from((birthdayRoot || dialog() || document).querySelectorAll(
    'select, [role="combobox"], [class*="DivSelectContainer"]'
  )).filter(visible);
  if (fields.length === 3 && state.otpRequestedAt == null) {
    const values = [config.month, config.day, config.year];
    const months = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    for (let i = 0; i < fields.length; i++) {
      const field = fields[i];
      if (state.birthdayFields.has(i)) continue;
      if (field.tagName === 'SELECT') {
        const options = Array.from(field.options);
        const option = options.find((o) => o.textContent.trim() === String(values[i]) ||
          i === 0 && (o.textContent.trim().toLowerCase() === months[config.month - 1].toLowerCase() ||
            o.textContent.trim().toLowerCase() === `tháng ${config.month}`));
        if (!option) return 'birthday-required';
        Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(field, option.value);
        field.dispatchEvent(new Event('input', { bubbles: true }));
        field.dispatchEvent(new Event('change', { bubbles: true }));
        state.birthdayFields.add(i);
        return 'waiting-form';
      }
      const option = Array.from(field.querySelectorAll('[role="option"], [class*="DivOption"]'))
        .filter(visible).find((o) => o.textContent.trim() === String(values[i]) ||
          i === 0 && (o.textContent.trim().toLowerCase() === months[config.month - 1].toLowerCase() ||
            o.textContent.trim().toLowerCase() === `tháng ${config.month}`));
      if (option) {
        option.click();
        state.birthdayFields.add(i);
        state.birthdayMenuIndex = null;
      } else {
        if (state.birthdayMenuIndex !== i) {
          // TikTok's combobox handles keyboard events on the root, but the
          // pointer handler lives on its label. Clicking the root does nothing.
          const label = field.querySelector('[class*="DivSelectLabel"]');
          (label || field).click();
          state.birthdayMenuIndex = i;
          state.birthdayMenuAt = Date.now();
        } else if (Date.now() - state.birthdayMenuAt >= 3000) {
          return 'birthday-required';
        }
      }
      return 'waiting-form';
    }
    if (!emailInput && !passwordInput && !phoneInput) {
      clickOnce(button(/^(next|continue|tiếp|tiếp theo|tiếp tục)$/i));
      return 'waiting-form';
    }
  }

  // A phone signup form can also contain a password and a Send code button.
  // Always switch to email before pasting credentials or requesting a code.
  if (phoneInput || !emailInput && !state.emailEntered && state.otpRequestedAt == null && !verification) {
    if (phoneInput || passwordInput) return 'waiting-form';
    if (verification) return 'verification-required';
    const method = Array.from((dialog() || document).querySelectorAll(
      'a, button, [role="button"], [role="link"], [data-e2e="channel-item"]'
    )).find((el) => enabled(el) && /^(use phone or email|use phone\s*\/\s*email|sử dụng số điện thoại hoặc email)$/i.test(el.textContent.trim()));
    clickOnce(method);
    return 'waiting-form';
  }

  const paste = (editor, field, text) => {
    if (state.pasted.get(editor)?.failed) return 'paste-failed';
    if (editor.value === text) return null;
    if (state.pasted.has(editor)) {
      const previous = state.pasted.get(editor);
      return Date.now() - previous.at < 2000 ? 'waiting-paste' : 'paste-failed';
    }
    if (editor.value) return 'draft-exists';
    if (editor.disabled || editor.readOnly) return 'waiting-form';
    editor.focus();
    editor.select();
    state.pending = { editor, field, text, at: Date.now() };
    state.pasted.set(editor, { at: Date.now() });
    let request;
    try {
      request = window.flutter_inappwebview?.callHandler(
        'FlutterSignupPaste', config.attempt, field
      );
    } catch (_) {}
    if (!request?.then) {
      state.pending = null;
      return 'paste-failed';
    }
    const complete = (pasted) => {
      if (!state.active || window.__flutterAutoSignup !== state) return;
      state.pending = null;
      state.pasted.set(editor, { at: Date.now(), failed: pasted !== true });
      // Native paste can leave the editor focused. Commit blur validation
      // before the next poll clicks Send code or submits the form.
      if (pasted === true && document.activeElement === editor) editor.blur?.();
    };
    request.then(complete).catch(() => complete(false));
    return 'waiting-paste';
  };
  if (passwordStep) {
    if (passwordInput.value && passwordInput.value !== config.password) return 'draft-exists';
    // Let the post-OTP screen settle before pasting, then give validation
    // time to finish before the one final click. OTP polling stays fast.
    if (state.passwordEditor !== passwordInput) {
      state.passwordEditor = passwordInput;
      state.passwordScreenAt = Date.now();
      state.passwordReadyAt = null;
    }
    if (Date.now() - state.passwordScreenAt < 2500) return 'waiting-password-screen';
    const result = paste(passwordInput, 'password', config.password);
    if (result) return result;
    const submit = button(/^(sign\s*up|register|đăng ký)$/i);
    if (!submit) {
      state.passwordReadyAt = null;
      return 'waiting-form';
    }
    state.passwordReadyAt ??= Date.now();
    if (Date.now() - state.passwordReadyAt < 3000) return 'waiting-password-submit';
    state.passwordSubmitted = true;
    state.submitted = true;
    clickOnce(submit);
    return 'password-submitted';
  }
  // Keep polling after Send code. Enter the supplied OTP as soon as it is ready,
  // including when navigation replaces the original email/password form.
  const sendCodeControl = codeControls().find(el => sendCodePattern.test(controlText(el)));
  const sendCode = sendCodeControl && enabled(sendCodeControl) ? sendCodeControl : null;
  if (verification && state.otpRequestedAt == null && !sendCodeControl) {
    if (!otp && !config.waitForOtpApi) return 'verification-required';
    state.otpRequestedAt = Date.now();
  }
  if (state.otpRequestedAt != null) {
    if (!otp) return config.waitForOtpApi ? 'otp-required' : 'waiting-result';
    if (config.allowOtpSubmit === false) return 'waiting-result';
    if (!verification) return 'waiting-otp';
    const result = paste(verification, 'otp', otp);
    if (result) return result === 'waiting-paste' ? 'waiting-otp-paste' : result;
    const verify = button(/^(sign\s*up|register|verify|confirm|continue|next|đăng ký|xác minh|xác nhận|tiếp tục|tiếp theo)$/i);
    if (!verify) return 'waiting-form';
    state.submitted = true;
    state.otpSubmitted = true;
    verify.click();
    return 'otp-submitted';
  }
  if (emailInput) {
    const result = paste(emailInput, 'email', config.email);
    if (result) return result;
    state.emailEntered = true;
  }
  if (passwordInput) {
    const result = paste(passwordInput, 'password', config.password);
    if (result) return result;
  }
  // Focus and pointer events also commit the editor and support controls whose
  // handlers run on pointer/mouse down. Dispatch exactly one click, then wait
  // for TikTok's countdown or OTP step before starting the mailbox API.
  if (sendCode) {
    if (!state.clicked.has(sendCode)) {
      sendCode.scrollIntoView?.({ block: 'center', inline: 'nearest' });
      sendCode.focus({ preventScroll: true });
      if (!enabled(sendCode)) return 'waiting-form';
      const rect = sendCode.getBoundingClientRect?.();
      const eventOptions = { bubbles: true, cancelable: true, view: window,
        clientX: rect ? rect.left + rect.width / 2 : 0,
        clientY: rect ? rect.top + rect.height / 2 : 0,
        button: 0, pointerId: 1, pointerType: 'mouse', isPrimary: true };
      state.codeRequest = { at: Date.now() };
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
        const Constructor = type.startsWith('pointer') && typeof PointerEvent !== 'undefined'
          ? PointerEvent : typeof MouseEvent !== 'undefined' ? MouseEvent : Event;
        sendCode.dispatchEvent(new Constructor(type, {
          ...eventOptions, buttons: type.endsWith('down') ? 1 : 0,
        }));
      }
      if (enabled(sendCode)) clickOnce(sendCode);
      else state.clicked.add(sendCode);
      return codeRequestResult();
    }
    return 'waiting-result';
  }
  if (sendCodeControl) return 'waiting-form';
  if (verification) return 'verification-required';
  const submit = button(/^(sign\s*up|register|đăng ký)$/i);
  if (submit && state.emailEntered && passwordInput) {
    state.submitted = true;
    submit.click();
    return 'submitted';
  }
  clickOnce(button(/^(next|continue|tiếp|tiếp theo|tiếp tục)$/i));
  return 'waiting-form';
}
''';

String buildAutoSignupStopScript(int attempt) => '''
(() => {
  if (window.__flutterAutoSignup?.attempt === $attempt) {
    window.__flutterAutoSignup.stop();
    delete window.__flutterAutoSignup;
  }
})();
''';
