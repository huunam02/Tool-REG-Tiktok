import 'dart:convert';

import 'home_account_modal_script.dart';

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

  bool useAccessibilitySendCode = false,

  int sendCodeDelayMs = 5000,

  bool useAccessibilityPasswordSubmit = false,

  int passwordSubmitDelayMs = 10000,

  bool useAccessibilityUsernameSkip = false,

  bool manualAccessibilityButtons = false,

  bool manualFieldInput = false,
}) =>
    '''

($autoSignupStepScript)(${jsonEncode({'email': email, 'password': password, 'year': birthday.year, 'month': birthday.month, 'day': birthday.day, 'attempt': attempt, 'otp': otp.trim(), 'otpRequestedAt': otpRequestedAt, 'allowOtpSubmit': allowOtpSubmit, 'allowPasswordSubmit': allowPasswordSubmit, 'waitForOtpApi': waitForOtpApi, 'useAccessibilitySendCode': useAccessibilitySendCode, 'sendCodeDelayMs': sendCodeDelayMs, 'useAccessibilityPasswordSubmit': useAccessibilityPasswordSubmit, 'passwordSubmitDelayMs': passwordSubmitDelayMs, 'useAccessibilityUsernameSkip': useAccessibilityUsernameSkip, 'manualAccessibilityButtons': manualAccessibilityButtons, 'manualFieldInput': manualFieldInput})}, $allowSubmit, ($openHomeAccountModalScript));

''';

// Flutter polls one step at a time. Input is entered using native clipboard

// paste; successful pastes and button clicks are remembered to avoid retries.

const String autoSignupStepScript = r'''

(config, allowSubmit, openHomeAccountModal) => {

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

        awaitingCode && /^(verify (your )?email|email verification|enter (the |your )?(verification |6[- ]digit )?code|create (a |your )?username|nhập mã xác minh|xác minh email|tạo tên người dùng)$/i.test(el.textContent.trim())));

  };

  const findForm = (selector) => signupFormVisible() ?

    Array.from((dialog() || document).querySelectorAll(selector)).find(visible) : null;

  const emailInput = findForm('input[name="email"], input[type="email"], input[autocomplete="email"]');

  const passwordInput = findForm('input[type="password"]');

  const findVerificationInputs = () => {
    if (!signupFormVisible()) return [];
    const root = dialog() || document;
    const known = Array.from(root.querySelectorAll(
      'input[autocomplete="one-time-code"], input[name="code"], ' +
      'input[name="verification_code"], input[name="otp"], input[name="verifyCode"], ' +
      'input[placeholder*="code" i], input[placeholder*="mã" i]')).filter(visible);
    const singles = Array.from(root.querySelectorAll('input[maxlength="1"]'))
      .filter(el => visible(el) && el.type !== 'password');
    const waitingForCode = config.otpRequestedAt != null ||
      window.__flutterAutoSignup?.attempt === config.attempt &&
        (window.__flutterAutoSignup.codeRequest || window.__flutterAutoSignup.otpRequestedAt != null);
    if (singles.length === 6 && (waitingForCode || known.some(el => singles.includes(el)))) return singles;
    return known.slice(0, 1);
  };
  const findVerification = () => findVerificationInputs()[0] || null;

  const verification = findVerification();

  const findPhone = () => signupFormVisible() && Array.from((dialog() || document).querySelectorAll(

    'input[type="tel"], input[name="phone"], input[name="mobile"], input[autocomplete="tel"]'

  )).find(el => visible(el) && !findVerificationInputs().includes(el));

  const phoneInput = findPhone();

  const previousState = window.__flutterAutoSignup?.attempt === config.attempt

    ? window.__flutterAutoSignup : null;

  const usernameScreen = signupFormVisible() && !emailInput && !passwordInput &&

    !verification && !phoneInput && Array.from((dialog() || document).querySelectorAll(

      'h1, h2, h3, p, div, span, label'

    )).some(el => visible(el) && /^(create (a |your )?username|tạo tên người dùng)$/i.test(

      (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()));

  const usernameStep = usernameScreen && (previousState?.passwordSubmitted ||

    config.manualAccessibilityButtons && previousState?.otpRequestedAt != null ||

    config.allowPasswordSubmit === false || previousState?.submitted && previousState?.otpSubmitted ||

    !allowSubmit && config.allowOtpSubmit === false);

  // The profile icon can already be visible behind the username dialog.

  // Finish the requested Skip step before reporting account success.

  if (!usernameScreen && find('[data-e2e="profile-icon"]')) {

    return allowSubmit ? 'already-logged-in' : 'signup-success';

  }

  // Email signup can put the password on a separate screen after OTP. A

  // submitted OTP does not mean the final account form has been submitted.

  const passwordStep = !!passwordInput && !emailInput && !verification && !phoneInput &&

    (previousState?.emailEntered || previousState?.otpRequestedAt != null || config.otpRequestedAt != null);

  if (find('#captcha-verify-container, .captcha-verify-container, .captcha-disable-scroll, [id*="captcha"], [class*="Captcha"], ' +

      'iframe[src*="captcha"]')) {

    return 'verification-required';

  }

  const enteredOtp = findVerificationInputs().map(el => el.value || '').join('');
  const otp = config.manualFieldInput ? enteredOtp.trim() : (config.otp || '').trim();
  const pastingOwnOtp = previousState?.pending?.field === 'otp' &&
    previousState.pending.text === otp;
  if (!config.manualFieldInput && verification && enteredOtp.trim() && enteredOtp !== otp && !pastingOwnOtp) {

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

  // An unavailable suggested username does not prevent using Skip.

  if (error?.textContent.trim() && !usernameStep) return 'signup-error';

  if (previousState?.passwordRequest?.failed) return 'password-submit-accessibility-failed';
  if (previousState?.usernameSkipRequest?.failed) return 'username-skip-accessibility-failed';

  if (passwordStep && (config.allowPasswordSubmit === false || previousState?.passwordSubmitted)) return 'waiting-result';

  if (!allowSubmit && !passwordStep && !usernameStep && (!verification || !otp && !config.waitForOtpApi && !config.manualFieldInput || config.allowOtpSubmit === false)) return 'waiting-result';



  let state = window.__flutterAutoSignup;

  if (!state || state.attempt !== config.attempt) {

    state?.stop();

    state = {

      attempt: config.attempt, active: true, pending: null,

      pasted: new WeakMap(), clicked: new WeakSet(), actions: new Set(), birthdayFields: new Set(),

      birthdayMenuIndex: null, birthdayMenuAt: 0,

      submitted: false, emailEntered: false, codeRequest: null,

      otpRequestedAt: config.otpRequestedAt ?? null, otpSubmitted: false,

      passwordSubmitted: false,

      passwordEditor: null, passwordScreenAt: null, passwordReadyAt: null,
      passwordSubmitButton: null, passwordRequest: null,

      usernameSkipButton: null, usernameSkipReadyAt: null, usernameSkipped: false,
      usernameSkipRequest: null,

      canPasteFromClipboard(attempt, field, text) {

        const p = this.pending;

        return !config.manualFieldInput && this.active && !document.hidden &&

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

  if (state.submitted && !passwordStep && !usernameStep && (!verification || !otp && !config.waitForOtpApi || state.otpSubmitted)) return 'submitted';

  if (state.pending) {

    return Date.now() - state.pending.at < 10000

      ? state.pending.field === 'otp' ? 'waiting-otp-paste' :
        state.pending.field === 'password' ? 'waiting-next' : 'waiting-paste'

      : 'paste-failed';

  }

  const enabled = (button) => visible(button) && !button.disabled &&

    button.getAttribute('aria-disabled') !== 'true';

  const clickOnce = (button, action) => {

    if (!button || (action && !enabled(button)) ||

        (action ? state.actions.has(action) : state.clicked.has(button))) return false;

    if (action) state.actions.add(action);

    else state.clicked.add(button);

    button.click();

    return true;

  };

  const button = (pattern) => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))

    .find((el) => enabled(el) && pattern.test(el.textContent.trim()));

  const nativeButtonTarget = (control, action = 'button') => {
    const viewport = window.visualViewport;
    const offsetX = viewport?.offsetLeft || 0;
    const offsetY = viewport?.offsetTop || 0;
    const viewportWidth = viewport?.width || window.innerWidth;
    const viewportHeight = viewport?.height || window.innerHeight;
    const geometry = [offsetX, offsetY, viewportWidth, viewportHeight,
      window.devicePixelRatio || 1].join(':');
    // Keep only geometry, never account data or detached DOM nodes. A new
    // attempt can reuse a region when the live button still occupies it.
    const cache = window.__flutterNativeTapTargets ||= new Map();
    const pointIn = rect => {
      // Always the exact centre of the control; no random offset.
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      if (![x, y, viewportWidth, viewportHeight].every(Number.isFinite) ||
          rect.width <= 0 || rect.height <= 0 || viewportWidth <= 0 || viewportHeight <= 0 ||
          x < offsetX || y < offsetY || x >= offsetX + viewportWidth ||
          y >= offsetY + viewportHeight) return null;
      // A cache hit still has to land on the currently authorized control.
      const hit = document.elementFromPoint(x, y);
      if (!hit || hit !== control && !control.contains(hit)) return null;
      return { x: x - offsetX, y: y - offsetY, viewportWidth, viewportHeight };
    };
    const cached = cache.get(action);
    if (cached?.geometry === geometry) {
      const point = pointIn(cached.rect);
      if (point) return point;
    }
    cache.delete(action);
    const bounds = control.getBoundingClientRect();
    const rect = {left: bounds.left, top: bounds.top, width: bounds.width, height: bounds.height};
    const point = pointIn(rect);
    if (!point) return null;
    if (cache.size >= 16) cache.delete(cache.keys().next().value);
    cache.set(action, {geometry, rect});
    return point;
  };

  if (usernameScreen) {

    if (!usernameStep || state.usernameSkipped) return 'waiting-result';

    const root = dialog() || document;

    const isSkip = el => enabled(el) && !el.closest?.('[disabled], [aria-disabled="true"]') && /^(skip|bỏ qua)$/i.test(

      (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim());

    const skip = Array.from(root.querySelectorAll('a, button, [role="button"], [role="link"]')).find(isSkip) ||

      Array.from(root.querySelectorAll('div, span')).reverse().find(isSkip);

    state.canSkipUsernameWithAccessibility = (attempt) => {
      const request = state.usernameSkipRequest;
      const currentRoot = dialog() || document;
      const titleVisible = Array.from(currentRoot.querySelectorAll('h1, h2, h3, p, div, span, label'))
        .some(el => visible(el) && /^(create (a |your )?username|tạo tên người dùng)$/i.test(
          (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()));
      return state.active && window.__flutterAutoSignup === state && state.attempt === attempt &&
        !document.hidden && location.origin === 'https://www.tiktok.com' && signupFormVisible() &&
        !state.pending && !findPhone() && !findVerification() &&
        !findForm('input[name="email"], input[type="email"], input[autocomplete="email"], input[type="password"]') &&
        titleVisible && !!request && !request.failed && request.control?.isConnected !== false &&
        currentRoot === root && isSkip(request.control) &&
        Array.from(currentRoot.querySelectorAll('a, button, [role="button"], [role="link"], div, span'))
          .includes(request.control);
    };
    state.getUsernameSkipTarget = (attempt) => state.canSkipUsernameWithAccessibility(attempt)
      ? nativeButtonTarget(state.usernameSkipRequest.control, 'signup/skip-username') : null;

    if (!skip) {

      state.usernameSkipButton = null;

      state.usernameSkipReadyAt = null;

      return 'waiting-username-skip';

    }

    if (state.usernameSkipButton !== skip) {

      state.usernameSkipButton = skip;

      state.usernameSkipReadyAt = Date.now();

    }

    if (config.manualAccessibilityButtons) return 'waiting-manual-username-skip';

    if (Date.now() - state.usernameSkipReadyAt < 2000) return 'waiting-username-skip';

    state.usernameSkipped = true;

    if (config.useAccessibilityUsernameSkip) {
      state.actions.add('skip-username');
      const current = state.usernameSkipRequest = { control: skip, at: Date.now(), failed: false };
      try {
        const request = window.flutter_inappwebview?.callHandler('FlutterSignupUsernameSkip', config.attempt);
        if (!request?.then) current.failed = true;
        else request.then(tapped => {
          if (state.active && state.usernameSkipRequest === current) current.failed = tapped !== true;
        }).catch(() => { current.failed = true; });
      } catch (_) { current.failed = true; }
      return current.failed ? 'username-skip-accessibility-failed' : 'username-skipped';
    }

    clickOnce(skip, 'skip-username');

    return 'username-skipped';

  }

  if (state.otpRequestedAt == null && config.otpRequestedAt != null) {

    state.otpRequestedAt = config.otpRequestedAt;

  }

  const controlText = el => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();

  const sendCodePattern = /^(send code|send verification code|gửi mã|gửi mã xác minh)$/i;

  const codeControls = () => Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))

    .filter(visible);

  if (state.sendCodePreparation &&
      (!enabled(state.sendCodePreparation.control) ||
        !codeControls().includes(state.sendCodePreparation.control))) {
    state.sendCodePreparation = null;
  }

  state.canSendCodeWithAccessibility = (attempt) =>
    state.active && window.__flutterAutoSignup === state &&
    state.attempt === attempt && !document.hidden &&
    location.origin === 'https://www.tiktok.com' && signupFormVisible() && !findPhone() &&
    !state.pending && !!state.codeRequest && !state.codeRequest.failed &&
    state.codeRequest.control?.isConnected !== false &&
    codeControls().includes(state.codeRequest.control) &&
    enabled(state.codeRequest.control) && sendCodePattern.test(controlText(state.codeRequest.control));

  state.getSendCodeTarget = (attempt) => state.canSendCodeWithAccessibility(attempt)
    ? nativeButtonTarget(state.codeRequest.control, 'signup/send-code') : null;

  state.canSubmitPasswordWithAccessibility = (attempt) => {
    const request = state.passwordRequest;
    const editor = findForm('input[type="password"]');
    return state.active && window.__flutterAutoSignup === state && state.attempt === attempt &&
      !document.hidden && location.origin === 'https://www.tiktok.com' && signupFormVisible() &&
      !state.pending && !findPhone() && !findVerification() &&
      !findForm('input[name="email"], input[type="email"], input[autocomplete="email"]') &&
      !!editor && editor === state.passwordEditor && !editor.disabled && !editor.readOnly &&
      (config.manualFieldInput ? editor.value === request?.value && editor.value.length >= 8
        : editor.value === config.password) && !!request && !request.failed &&
      request.control?.isConnected !== false && codeControls().includes(request.control) &&
      enabled(request.control) && /^(sign\s*up|register|đăng ký)$/i.test(controlText(request.control));
  };

  state.getPasswordSubmitTarget = (attempt) => state.canSubmitPasswordWithAccessibility(attempt)
    ? nativeButtonTarget(state.passwordRequest.control, 'signup/submit-password') : null;

  const codeAcknowledged = () => codeControls().some(el =>

      /^(resend( code)?|send (code )?again|gửi lại( mã)?)(\b|\s|\()/i.test(controlText(el)) ||

      /^(\d+\s*s|resend.*\d|send.*\d+\s*s|gửi lại.*\d)/i.test(controlText(el))) ||

      !!findVerification() && !emailInput && !passwordInput &&

        !codeControls().some(el => sendCodePattern.test(controlText(el)));

  // A manual tap must be acknowledged by TikTok before fetching an API OTP.
  // Waiting for the user does not start the automatic gesture's 15s timeout.
  if (config.manualAccessibilityButtons && state.otpRequestedAt == null && codeAcknowledged()) {
    state.otpRequestedAt = Date.now();
    return 'verification-requested';
  }

  const codeRequestResult = () => {

    const request = state.codeRequest;

    if (request.failed) return 'send-code-accessibility-failed';

    if (codeAcknowledged()) {

      state.otpRequestedAt = request.at;

      state.codeRequest = null;

      return 'verification-requested';

    }

    // A dispatched click is not proof of delivery. Never request an API code

    // or send another click while the result of this request is unknown.

    return Date.now() - request.at >= 15000 ? 'verification-request-failed' : 'requesting-verification';

  };

  if (state.codeRequest) return codeRequestResult();

  // The Home URL can stay unchanged while the account dialog opens.
  if (!signupFormVisible()) {

    const modal = dialog();

    if (modal || location.pathname.startsWith('/login')) {

      const signup = Array.from((modal || document).querySelectorAll(

        'a, button, [role="button"], [role="link"], [data-e2e="bottom-sign-up"], [data-e2e="signup-link"]'

      )).find(el => enabled(el) && /^(sign\s*up|đăng ký)$/i.test(el.textContent.trim()));

      clickOnce(signup, 'open-signup');

      return 'waiting-form';

    }

    if (!state.emailEntered && state.otpRequestedAt == null) {
      return openHomeAccountModal(state, visible, enabled, find);
    }
    return 'waiting-form';
  }

  // Switch method before processing birthday menus on the phone form.

  if (phoneInput || !emailInput && !state.emailEntered && state.otpRequestedAt == null) {

    const emailTab = Array.from((dialog() || document).querySelectorAll(

      'a, button, [role="tab"], [role="button"], [data-e2e="signup-email-tab"]'

    )).find((el) => enabled(el) && /^(email|e-mail|sign up with (email|e-mail)|use (email|e-mail)|đăng ký bằng (email|e-mail)|sử dụng (email|e-mail))$/i.test(el.textContent.trim()));

    if (emailTab) {

      clickOnce(emailTab, 'select-email-tab');

      return 'waiting-form';

    }

    if (phoneInput) return 'waiting-form';

  }



  // Opt in to the newsletter checkbox requested by the user. The input can

  // be visually hidden; its visible label identifies this specific option.

  if (!config.manualFieldInput && emailInput && !phoneInput && state.otpRequestedAt == null) {

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

  if (config.manualFieldInput && fields.length === 3 && state.otpRequestedAt == null &&
      !emailInput && !passwordInput && !phoneInput) {
    const next = button(/^(next|continue|tiếp|tiếp theo|tiếp tục)$/i);
    return clickOnce(next, 'birthday-next') ? 'next-submitted' : 'waiting-manual-birthday';
  }

  if (!config.manualFieldInput && fields.length === 3 && state.otpRequestedAt == null) {

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

        return i === fields.length - 1 ? 'waiting-next' : 'waiting-form';

      }

      const option = Array.from(field.querySelectorAll('[role="option"], [class*="DivOption"]'))

        .filter(visible).find((o) => o.textContent.trim() === String(values[i]) ||

          i === 0 && (o.textContent.trim().toLowerCase() === months[config.month - 1].toLowerCase() ||

            o.textContent.trim().toLowerCase() === `tháng ${config.month}`));

      if (option) {

        clickOnce(option, `birthday-option-${i}`);

        state.birthdayFields.add(i);

        state.birthdayMenuIndex = null;

      } else {

        if (state.birthdayMenuIndex !== i) {

          // TikTok's combobox handles keyboard events on the root, but the

          // pointer handler lives on its label. Clicking the root does nothing.

          const label = field.querySelector('[class*="DivSelectLabel"]');

          clickOnce(label || field, `birthday-menu-${i}`);

          state.birthdayMenuIndex = i;

          state.birthdayMenuAt = Date.now();

        } else if (Date.now() - state.birthdayMenuAt >= 3000) {

          return 'birthday-required';

        }

      }

      return i === fields.length - 1 && state.birthdayFields.has(i)
        ? 'waiting-next' : 'waiting-form';

    }

    if (!emailInput && !passwordInput && !phoneInput) {

      const next = button(/^(next|continue|tiếp|tiếp theo|tiếp tục)$/i);
      return clickOnce(next, 'birthday-next') ? 'next-submitted' : 'waiting-next';

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

    clickOnce(method, 'select-signup-method');

    return 'waiting-form';

  }



  const paste = (editor, field, text) => {

    // Manual mode only observes values. Do not focus, select, blur, dispatch
    // input events or call the native typing/clipboard bridge.
    if (config.manualFieldInput) {
      const value = editor.value || '';
      if (!value || editor.checkValidity?.() === false ||
          field === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) ||
          field === 'password' && (value.length < 8 || value.length > 20) ||
          field === 'otp' && !/^\d{6}$/.test(value)) {
        if (field === 'email') {
          state.manualEmailValue = null;
          state.sendCodePreparation = null;
        }
        if (field === 'password') {
          state.passwordReadyValue = null;
          state.passwordReadyAt = null;
        }
        return `waiting-manual-${field}`;
      }
      if (field === 'email' && state.manualEmailValue !== value) {
        state.manualEmailValue = value;
        state.sendCodePreparation = null;
      }
      return null;
    }

    const previousPaste = state.pasted.get(editor);

    if (previousPaste?.failed) return 'paste-failed';

    if (editor.value === text) {
      if (previousPaste?.accepted && !previousPaste.committed) {
        previousPaste.committed = true;
        if (document.activeElement === editor) editor.blur?.();
      }
      return null;
    }

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

      const result = { at: Date.now(), failed: pasted !== true,
        accepted: pasted === true, committed: false };
      state.pasted.set(editor, result);

      // Android can acknowledge paste before Chromium delivers the input.
      // Keep focus until the expected value arrives, then commit validation.
      if (pasted === true && editor.value === text) {
        result.committed = true;
        if (document.activeElement === editor) editor.blur?.();
      }

    };

    request.then(complete).catch(() => complete(false));

    return 'waiting-paste';

  };

  if (passwordStep) {

    if (state.passwordSubmitted) return 'waiting-result';

    if (!config.manualFieldInput && passwordInput.value && passwordInput.value !== config.password) return 'draft-exists';

    // Let the post-OTP screen settle before pasting, then give validation

    // time to finish before the one final click. OTP polling stays fast.

    if (state.passwordEditor !== passwordInput) {

      state.passwordEditor = passwordInput;

      state.passwordScreenAt = Date.now();

      state.passwordReadyAt = null;

    }

    if (Date.now() - state.passwordScreenAt < 350) return 'waiting-password-screen';

    const result = paste(passwordInput, 'password', config.password);

    if (result) return result === 'waiting-paste' ? 'waiting-next' : result;

    const submit = button(/^(sign\s*up|register|đăng ký)$/i);

    if (!submit) {

      state.passwordReadyAt = null;
      state.passwordSubmitButton = null;

      return 'waiting-password-submit';

    }

    if (state.passwordSubmitButton !== submit ||
        config.manualFieldInput && state.passwordReadyValue !== passwordInput.value) {
      state.passwordSubmitButton = submit;
      state.passwordReadyValue = passwordInput.value;
      state.passwordReadyAt = Date.now();
    }
    state.passwordReadyAt ??= Date.now();

    if (config.manualAccessibilityButtons) return 'waiting-manual-password-submit';

    const submitDelayMs = Number.isFinite(config.passwordSubmitDelayMs)
      ? Math.max(0, config.passwordSubmitDelayMs) : 10000;
    if (Date.now() - state.passwordReadyAt < submitDelayMs) return 'waiting-password-submit';

    state.passwordSubmitted = true;

    state.submitted = true;

    if (config.useAccessibilityPasswordSubmit) {
      // Latch before dispatch, so navigation cannot submit the final form again.
      state.actions.add('submit-password');
      const current = state.passwordRequest = { control: submit, at: Date.now(), failed: false,
        value: config.manualFieldInput ? passwordInput.value : undefined };
      try {
        const request = window.flutter_inappwebview?.callHandler('FlutterSignupPasswordSubmit', config.attempt);
        if (!request?.then) current.failed = true;
        else request.then(tapped => {
          if (state.active && state.passwordRequest === current) current.failed = tapped !== true;
        }).catch(() => { current.failed = true; });
      } catch (_) { current.failed = true; }
      return current.failed ? 'password-submit-accessibility-failed' : 'password-submitted';
    }

    clickOnce(submit, 'submit-password');

    return 'password-submitted';

  }

  // Keep polling after Send code. Enter the supplied OTP as soon as it is ready,

  // including when navigation replaces the original email/password form.

  const sendCodeControl = codeControls().find(el => sendCodePattern.test(controlText(el)));

  const sendCode = sendCodeControl && enabled(sendCodeControl) ? sendCodeControl : null;

  if (verification && state.otpRequestedAt == null && !sendCodeControl) {

    if (!otp && !config.waitForOtpApi && !config.manualFieldInput) return 'verification-required';

    state.otpRequestedAt = Date.now();

  }

  if (state.otpRequestedAt != null) {

    if (config.manualFieldInput && !/^\d{6}$/.test(otp)) return 'waiting-manual-otp';
    if (!otp) return config.waitForOtpApi ? 'otp-required' : 'waiting-result';

    if (config.allowOtpSubmit === false) return 'waiting-result';

    if (!verification) return 'waiting-otp';

    const otpInputs = findVerificationInputs();
    const splitCodeComplete = otpInputs.length === 6 && enteredOtp === otp;
    const result = splitCodeComplete ? null : paste(verification, 'otp', otp);

    if (result) return result === 'waiting-paste' ? 'waiting-otp-paste' : result;

    if (!config.manualFieldInput && splitCodeComplete && otpInputs.includes(document.activeElement)) {
      document.activeElement.blur?.();
    }

    const verify = button(/^(sign\s*up|register|verify|confirm|continue|next|đăng ký|xác minh|xác nhận|tiếp tục|tiếp theo)$/i);

    if (!verify) return 'waiting-next';

    state.submitted = true;

    state.otpSubmitted = true;

    clickOnce(verify, 'submit-otp');

    return 'otp-submitted';

  }

  if (emailInput) {

    const result = paste(emailInput, 'email', config.email);

    if (result) return result;

    state.emailEntered = true;

  }

  if (passwordInput) {

    const result = paste(passwordInput, 'password', config.password);

    if (result) return result === 'waiting-paste' ? 'waiting-next' : result;

  }

  // Activate once and wait for TikTok's countdown before starting the OTP API.

  if (sendCode) {

    if (config.manualAccessibilityButtons) return 'waiting-manual-send-code';

    if (!state.actions.has('send-code')) {
      if (!state.sendCodePreparation || state.sendCodePreparation.control !== sendCode) {
        sendCode.scrollIntoView?.({ block: 'center', inline: 'nearest' });
        sendCode.focus({ preventScroll: true });
        if (!enabled(sendCode)) return 'waiting-form';
        state.sendCodePreparation = { control: sendCode, at: Date.now() };
      }
      const delayMs = Number.isFinite(config.sendCodeDelayMs)
        ? Math.max(0, config.sendCodeDelayMs) : 5000;
      if (Date.now() - state.sendCodePreparation.at < delayMs) return 'waiting-send-code';
      state.sendCodePreparation = null;

      if (config.useAccessibilitySendCode) {
        // Reserve the action before calling Flutter; DOM replacement and polling
        // must not issue a second request while Android performs the gesture.
        state.actions.add('send-code');
        const current = state.codeRequest = { at: Date.now(), control: sendCode, failed: false };
        try {
          const request = window.flutter_inappwebview?.callHandler('FlutterSignupSendCode', config.attempt);
          if (!request?.then) current.failed = true;
          else request.then(tapped => {
            if (state.active && state.codeRequest === current) current.failed = tapped !== true;
          }).catch(() => { current.failed = true; });
        } catch (_) { current.failed = true; }
        return current.failed ? 'send-code-accessibility-failed' : 'requesting-verification';
      }

      state.codeRequest = { at: Date.now() };

      clickOnce(sendCode, 'send-code');

      return codeRequestResult();

    }

    return 'waiting-result';

  }

  if (sendCodeControl) return 'waiting-form';

  if (verification) return 'verification-required';

  const submit = button(/^(sign\s*up|register|đăng ký)$/i);

  if (submit && state.emailEntered && passwordInput) {

    state.submitted = true;

    clickOnce(submit, 'submit-signup');

    return 'submitted';

  }

  const next = button(/^(next|continue|tiếp|tiếp theo|tiếp tục)$/i);
  return clickOnce(next, 'form-next') ? 'next-submitted' :
    state.emailEntered ? 'waiting-next' : 'waiting-form';

}

''';

String buildAutoSignupStopScript(int attempt) =>
    '''

(() => {

  if (window.__flutterAutoSignup?.attempt === $attempt) {

    window.__flutterAutoSignup.stop();

    delete window.__flutterAutoSignup;

  }

})();

''';
