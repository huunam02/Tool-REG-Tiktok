import 'dart:convert';

import 'home_account_modal_script.dart';
import 'authenticated_session_script.dart';

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

  bool useAccessibilitySendCode = false,

  bool useAccessibilityContinue = false,

  bool useAccessibilityEmailVerification = false,

  int emailVerificationDelayMs = 5000,
}) =>
    '''

(() => {

  if (location.origin !== 'https://www.tiktok.com') return 'wrong-origin';

  return ($autoLoginStepScript)(

    ${jsonEncode({'email': email, 'password': password, 'attempt': attempt, 'otp': otp.trim(), 'otpRequestedAt': otpRequestedAt, 'emailVerificationRequestedAt': emailVerificationRequestedAt, 'allowOtpSubmit': allowOtpSubmit, 'waitForOtpApi': waitForOtpApi, 'useAccessibilitySendCode': useAccessibilitySendCode, 'useAccessibilityContinue': useAccessibilityContinue, 'useAccessibilityEmailVerification': useAccessibilityEmailVerification, 'emailVerificationDelayMs': emailVerificationDelayMs})}, $allowSubmit, ($openHomeAccountModalScript), ($authenticatedSessionScript)

  );

})();

''';

// Polled by Flutter while the login action is active. Credentials stay local

// to this call; Flutter pastes through the native editor and remembers submission.

const String autoLoginStepScript = r'''

(config, allowSubmit, openHomeAccountModal, isAuthenticated) => {

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



  if (isAuthenticated()) {

    return allowSubmit ? 'already-logged-in' : 'login-success';

  }

  if (find('#captcha-verify-container, .captcha-verify-container, .captcha-disable-scroll, [id*="captcha"], [class*="Captcha"], ' +

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

      continueRequests: { password: null, otp: null },

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

  if (Object.values(state.continueRequests).some(request => request?.failed)) return 'continue-accessibility-failed';

  if (state.pending) {

    return Date.now() - state.pending.at < 10000

      ? state.pending.field === 'otp' ? 'waiting-otp-paste' :
        state.pending.field === 'password' ? 'waiting-next' : 'waiting-paste'

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

  state.canSendCodeWithAccessibility = (attempt) =>
    state.active && window.__flutterAutoLogin === state &&
    state.attempt === attempt && !document.hidden &&
    location.origin === 'https://www.tiktok.com' && loginFormVisible() && !findPhone() &&
    !!state.codeRequest && !state.codeRequest.failed &&
    state.codeRequest.control?.isConnected !== false &&
    codeControls().includes(state.codeRequest.control) &&
    enabled(state.codeRequest.control) && sendCodePattern.test(controlText(state.codeRequest.control));

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

  state.getSendCodeTarget = (attempt) => state.canSendCodeWithAccessibility(attempt)
    ? nativeButtonTarget(state.codeRequest.control, 'login/send-code') : null;

  const findEmailVerificationMethod = (root) => {
    const isEmailMethod = el => enabled(el) &&
      /^e-?mail\s*([^\s@]+@[^\s@]+\.[^\s@]+)?$/i.test(controlText(el));
    const row = Array.from(root.querySelectorAll('[class*="pc-home-item-"]')).find(isEmailMethod);
    const semantic = Array.from(root.querySelectorAll(
      'button, [role="button"], a, [role="link"]')).find(isEmailMethod);
    const methods = Array.from(root.querySelectorAll('div, span')).filter(isEmailMethod).reverse();
    return row || semantic || methods.find(el => /@/.test(controlText(el))) || methods[0];
  };
  state.getEmailVerificationTarget = (attempt) => {
    const request = state.emailVerificationRequest;
    const root = dialog();
    if (!state.active || window.__flutterAutoLogin !== state || state.attempt !== attempt ||
        document.hidden || location.origin !== 'https://www.tiktok.com' ||
        location.pathname.startsWith('/signup') || !verificationActive() || !root ||
        root !== request?.root || !hasTitle(root, identityTitle) || findVerification() ||
        !request?.pending || request.failed || request.control.isConnected === false ||
        findEmailVerificationMethod(root) !== request.control ||
        find('#captcha-verify-container, .captcha-verify-container, .captcha-disable-scroll, [id*="captcha"], [class*="Captcha"], iframe[src*="captcha"]')) return null;
    return nativeButtonTarget(request.control, 'login/select-verification-email');
  };

  // OTP dialogs can label the same native confirmation action as Next.
  const continuePattern = /^(continue|next|tiếp tục|tiếp theo)$/i;
  const passwordFormRoot = () => {
    const editor = findForm('input[type="password"]');
    return editor?.closest('form') || editor?.parentElement
      ?.closest('[data-e2e="login-container"]') || dialog() || document;
  };
  const continueTarget = (attempt, stage) => {
    const request = state.continueRequests[stage];
    if (!state.active || window.__flutterAutoLogin !== state || state.attempt !== attempt ||
        document.hidden || location.origin !== 'https://www.tiktok.com' || !loginFormVisible() ||
        findPhone() || state.pending || !request || request.failed ||
        request.control.isConnected === false || !enabled(request.control) ||
        !continuePattern.test(controlText(request.control))) return null;
    const root = stage === 'password' ? passwordFormRoot() : dialog() || document;
    if (root !== request.root ||
        !Array.from(root.querySelectorAll('button, [role="button"]')).includes(request.control)) return null;
    const editor = stage === 'password' ? findForm('input[type="password"]') : findVerification();
    if (!editor || editor !== request.editor || editor.disabled || editor.readOnly ||
        editor.value !== (stage === 'password' ? config.password : otp)) return null;
    if (stage === 'password') {
      const email = findEmail();
      if (findVerification() || !email || email !== request.email || email.value !== config.email) return null;
    } else if (state.otpRequestedAt == null) return null;
    return nativeButtonTarget(request.control, 'login/continue-' + stage);
  };
  state.getPasswordContinueTarget = (attempt) => continueTarget(attempt, 'password');
  state.getOtpContinueTarget = (attempt) => continueTarget(attempt, 'otp');

  const submitButton = (control, stage) => {
    const action = stage === 'password' ? 'submit-password' : 'submit-otp';
    const status = stage === 'password' ? 'submitted' : 'otp-submitted';
    if (!config.useAccessibilityContinue || !continuePattern.test(controlText(control))) {
      clickOnce(control, action);
      return status;
    }
    state.actions.add(action);
    const current = state.continueRequests[stage] = {
      control, root: stage === 'password' ? passwordFormRoot() : dialog() || document,
      editor: stage === 'password' ? passwordInput : verification,
      email: emailInput, failed: false,
    };
    const handler = stage === 'password' ? 'FlutterLoginPasswordContinue' : 'FlutterLoginOtpContinue';
    try {
      const request = window.gecko_bridge?.callHandler(handler, config.attempt);
      if (!request?.then) current.failed = true;
      else request.then(tapped => {
        if (state.active && state.continueRequests[stage] === current) current.failed = tapped !== true;
      }).catch(() => { current.failed = true; });
    } catch (_) { current.failed = true; }
    return current.failed ? 'continue-accessibility-failed' : status;
  };

  const requestCode = (control) => {
    if (!config.useAccessibilitySendCode) {
      state.codeRequest = { at: Date.now() };
      clickOnce(control, 'send-code');
      return codeRequestResult();
    }
    state.codeRequest = { at: Date.now(), control, failed: false };
    state.actions.add('send-code');
    const current = state.codeRequest;
    try {
      const request = window.gecko_bridge?.callHandler('FlutterLoginSendCode', config.attempt);
      if (!request?.then) current.failed = true;
      else request.then(clicked => {
        if (state.active && state.codeRequest === current) current.failed = clicked !== true;
      }).catch(() => { current.failed = true; });
    } catch (_) { current.failed = true; }
    return current.failed ? 'send-code-accessibility-failed' : 'requesting-verification';
  };

  const codeRequestResult = () => {

    const request = state.emailVerificationRequest || state.codeRequest;

    if (request.failed) return 'send-code-accessibility-failed';

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

  if (state.emailVerificationRequest || state.codeRequest) {
    const emailRequest = state.emailVerificationRequest;
    if (emailRequest?.failed) return 'email-verification-accessibility-failed';
    if (emailRequest?.pending) return 'requesting-email-verification';
    if (emailRequest?.selectedReported === false) {
      emailRequest.selectedReported = true;
      return 'email-verification-selected';
    }
    // Some identity flows show a separate Send code screen after selecting Email.
    const send = state.emailVerificationRequest && codeControls().find(el =>
      enabled(el) && sendCodePattern.test(controlText(el)));
    if (send) {
      state.emailVerificationRequest = null;
      return requestCode(send);
    }
    return codeRequestResult();
  }

  const verificationModal = dialog();

  if (verificationActive() && verificationModal && hasTitle(verificationModal, identityTitle) && !verification) {

    if (state.emailVerificationSelected || state.otpSubmitted || config.allowOtpSubmit === false) return 'waiting-result';

    // Select the actionable row inside the foreground identity dialog.
    const emailMethod = findEmailVerificationMethod(verificationModal);
    if (!emailMethod) {
      state.emailVerificationPreparation = null;
      return 'waiting-form';
    }
    if (!state.emailVerificationPreparation ||
        state.emailVerificationPreparation.control !== emailMethod ||
        state.emailVerificationPreparation.root !== verificationModal) {
      emailMethod.scrollIntoView?.({ block: 'center', inline: 'nearest' });
      emailMethod.focus?.({ preventScroll: true });
      state.emailVerificationPreparation = { control: emailMethod, root: verificationModal, at: Date.now() };
    }
    const delayMs = Number.isFinite(config.emailVerificationDelayMs)
      ? Math.max(0, config.emailVerificationDelayMs) : 5000;
    if (Date.now() - state.emailVerificationPreparation.at < delayMs) return 'waiting-email-verification';
    state.emailVerificationPreparation = null;
    state.emailVerificationSelected = true;
    if (!config.useAccessibilityEmailVerification) {
      state.emailVerificationRequest = { at: Date.now() };
      clickOnce(emailMethod, 'select-verification-email');
      return 'email-verification-selected';
    }
    // Reserve this selection before crossing the bridge, and wait for the
    // native gesture to finish before starting TikTok's acknowledgement timer.
    state.actions.add('select-verification-email');
    const current = state.emailVerificationRequest = {
      control: emailMethod, root: verificationModal,
      at: null, pending: true, failed: false, selectedReported: false,
    };
    try {
      const request = window.gecko_bridge?.callHandler('FlutterLoginEmailVerification', config.attempt);
      if (!request?.then) {
        current.pending = false;
        current.failed = true;
      } else request.then(tapped => {
        if (!state.active || window.__flutterAutoLogin !== state || state.emailVerificationRequest !== current) return;
        current.pending = false;
        current.failed = tapped !== true;
        if (!current.failed) current.at = Date.now();
      }).catch(() => {
        if (state.active && state.emailVerificationRequest === current) {
          current.pending = false;
          current.failed = true;
        }
      });
    } catch (_) {
      current.pending = false;
      current.failed = true;
    }
    return current.failed ? 'email-verification-accessibility-failed' : 'requesting-email-verification';

  }

  // Home can render before TikTok attaches its click handlers.
  if (!loginFormVisible()) {
    if (!allowSubmit || state.submitted) return 'waiting-result';
    if (!dialog()) return openHomeAccountModal(state, visible, enabled, find);
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

      request = window.gecko_bridge?.callHandler('FlutterLoginPaste', config.attempt, field);

    } catch (_) {}

    if (!request?.then) {

      state.pending = null;

      return 'paste-failed';

    }

    const complete = (pasted) => {

      if (!state.active || window.__flutterAutoLogin !== state) return;

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

  // A code challenge can follow a password submission. Handle it even when

  // Flutter has already latched the first submission, without requesting again.

  const sendCodeControl = Array.from((dialog() || document).querySelectorAll('button, [role="button"]'))

    .find(element => visible(element) && sendCodePattern.test(element.textContent.trim()));

  const sendCode = sendCodeControl && enabled(sendCodeControl) ? sendCodeControl : null;

  if (state.otpRequestedAt == null && config.otpRequestedAt != null) {

    state.otpRequestedAt = config.otpRequestedAt;

  }

  if (sendCode && state.otpRequestedAt == null &&
      (state.submitted || !allowSubmit || state.emailVerificationSelected)) {
    return requestCode(sendCode);
  }

  if (verification && !otp && !config.waitForOtpApi && !sendCodeControl) return 'verification-required';

  if (verification && state.otpRequestedAt == null && !sendCodeControl) {

    state.otpRequestedAt = Date.now();

  }

  if (state.otpRequestedAt != null) {

    if (!otp) return config.waitForOtpApi ? 'otp-required' : 'verification-required';

    if (state.otpSubmitted || config.allowOtpSubmit === false) return 'waiting-result';

    if (!verification || verification.disabled || verification.readOnly) return 'waiting-otp';

    const result = paste(verification, 'otp', otp);

    if (result) return result === 'waiting-paste' ? 'waiting-otp-paste' : result;

    const verify = button(/^(log\s*in|verify|confirm|continue|next|đăng nhập|xác minh|xác nhận|tiếp tục|tiếp theo)$/i);

    if (!verify) return 'waiting-next';

    state.otpSubmitted = true;

    return submitButton(verify, 'otp');

  }

  if (state.submitted) return 'submitted';

  if (!allowSubmit) return 'waiting-result';

  if (!emailInput || (!passwordInput && !sendCodeControl)) return 'waiting-form';

  const emailResult = paste(emailInput, 'email', config.email);

  if (emailResult) return emailResult;

  if (passwordInput) {

    const passwordResult = paste(passwordInput, 'password', config.password);

    if (passwordResult) return passwordResult === 'waiting-paste'
      ? 'waiting-next' : passwordResult;

  }

  if (sendCode) {
    return requestCode(sendCode);

  }

  if (sendCodeControl) return 'waiting-submit';

  if (verification) return 'verification-required';



  // Stay inside the password form so a signup/third-party button is not used.

  const root = passwordFormRoot();

  const submit = Array.from(root.querySelectorAll('button, [role="button"]'))

    .find((button) => visible(button) && !button.disabled &&

      button.getAttribute('aria-disabled') !== 'true' &&

      (button.getAttribute('data-e2e') === 'login-button' ||

        /^(log\s*in|continue|đăng nhập|tiếp tục)$/i.test(button.textContent.trim())));

  if (!submit) return 'waiting-next';

  // Latch before clicking in case navigation interrupts the result delivery.

  state.submitted = true;

  return submitButton(submit, 'password');

}

''';

String buildAutoLoginStopScript(int attempt) =>
    '''

(() => {

  if (window.__flutterAutoLogin?.attempt === $attempt) {

    window.__flutterAutoLogin.stop();

    delete window.__flutterAutoLogin;

  }

})();

''';
