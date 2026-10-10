import 'dart:convert';

String buildAutoSignupScript({
  required String email,
  required String password,
  required DateTime birthday,
  required int attempt,
  required bool allowSubmit,
}) =>
    '''
($autoSignupStepScript)(${jsonEncode({
          'email': email,
          'password': password,
          'year': birthday.year,
          'month': birthday.month,
          'day': birthday.day,
          'attempt': attempt,
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
  if (find('[data-e2e="profile-icon"]')) {
    return allowSubmit ? 'already-logged-in' : 'signup-success';
  }
  if (!location.pathname.startsWith('/signup')) return 'waiting-form';
  const emailInput = find('input[name="email"], input[type="email"], input[autocomplete="email"]');
  const passwordInput = find('input[type="password"]');
  const phoneInput = find('input[type="tel"], input[name="phone"], input[name="mobile"], input[autocomplete="tel"]');
  if (find('#captcha-verify-container, [id*="captcha"], [class*="Captcha"], ' +
      'iframe[src*="captcha"]')) {
    return 'verification-required';
  }
  const verification = find('input[autocomplete="one-time-code"], input[name="code"], input[name="verification_code"]');
  if (verification && verification.value?.trim()) {
    return 'verification-required';
  }
  // TikTok's existing-email warning is inline text rather than a role=alert.
  // Stop before requesting a code for an account that already exists.
  if (emailInput && Array.from(document.querySelectorAll('p, div, span')).some((el) => {
    const text = el.textContent.trim();
    return text.length < 160 && visible(el) &&
      /^(you['’]ve already signed up|this email is already registered|email này đã (được đăng ký|tồn tại))/i.test(text);
  })) return 'email-registered';
  const error = find('[data-e2e="signup-error"], [role="alert"]');
  if (error?.textContent.trim()) return 'signup-error';
  if (!allowSubmit) return 'waiting-result';

  let state = window.__flutterAutoSignup;
  if (!state || state.attempt !== config.attempt) {
    state?.stop();
    state = {
      attempt: config.attempt, active: true, pending: null,
      pasted: new WeakMap(), clicked: new WeakSet(), birthdayFields: new Set(),
      birthdayMenuIndex: null, birthdayMenuAt: 0,
      submitted: false, emailEntered: false,
      canPasteFromClipboard(attempt, field, text) {
        const p = this.pending;
        return this.active && !document.hidden &&
          location.origin === 'https://www.tiktok.com' &&
          location.pathname.startsWith('/signup') && !!p &&
          (attempt === undefined || attempt === this.attempt) &&
          (field === undefined || field === p.field) &&
          (text === undefined || text === p.text) &&
          p.editor.isConnected && visible(p.editor) &&
          !p.editor.disabled && !p.editor.readOnly &&
          document.activeElement === p.editor &&
          p.editor.tagName === 'INPUT' &&
          !find('input[type="tel"], input[name="phone"], input[name="mobile"], input[autocomplete="tel"]') &&
          (p.field === 'email' || p.field === 'password' && this.emailEntered);
      },
      stop() { this.active = false; this.pending = null; }
    };
    window.__flutterAutoSignup = state;
  }
  if (!state.active) return 'cancelled';
  if (state.submitted) return 'submitted';
  if (state.pending) {
    return Date.now() - state.pending.at < 10000 ? 'waiting-paste' : 'paste-failed';
  }
  const enabled = (button) => visible(button) && !button.disabled &&
    button.getAttribute('aria-disabled') !== 'true';
  const clickOnce = (button) => {
    if (!button || state.clicked.has(button)) return false;
    state.clicked.add(button);
    button.click();
    return true;
  };
  const button = (pattern) => Array.from(document.querySelectorAll('button, [role="button"]'))
    .find((el) => enabled(el) && pattern.test(el.textContent.trim()));

  // Switch method before processing birthday menus on the phone form.
  if (phoneInput || !emailInput && !state.emailEntered) {
    const emailTab = Array.from(document.querySelectorAll(
      'a, button, [role="tab"], [role="button"], [data-e2e="signup-email-tab"]'
    )).find((el) => enabled(el) && /^(email|e-mail|sign up with (email|e-mail)|use (email|e-mail)|đăng ký bằng (email|e-mail)|sử dụng (email|e-mail))$/i.test(el.textContent.trim()));
    if (emailTab) {
      clickOnce(emailTab);
      return 'waiting-form';
    }
    if (phoneInput) return 'waiting-form';
  }

  // Birthday controls can share the same page as the email/password inputs.
  // Complete them before entering credentials on either layout.
  const birthdayRoot = find('[class*="DivAgeSelector"], [data-e2e="birthday-selector"]');
  const fields = Array.from((birthdayRoot || document).querySelectorAll(
    'select, [role="combobox"], [class*="DivSelectContainer"]'
  )).filter(visible);
  if (fields.length === 3) {
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
  if (phoneInput || !emailInput && !state.emailEntered) {
    if (phoneInput || passwordInput) return 'waiting-form';
    if (verification) return 'verification-required';
    const method = Array.from(document.querySelectorAll('a, button, [role="button"]'))
      .find((el) => enabled(el) && /^(use phone or email|sử dụng số điện thoại hoặc email)$/i.test(el.textContent.trim()));
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
    };
    request.then(complete).catch(() => complete(false));
    return 'waiting-paste';
  };
  if (emailInput) {
    const result = paste(emailInput, 'email', config.email);
    if (result) return result;
    state.emailEntered = true;
  }
  if (passwordInput) {
    const result = paste(passwordInput, 'password', config.password);
    if (result) return result;
  }
  // Send the verification code at most once. Flutter hands further verification
  // to the user and never reports success merely because this button was clicked.
  const sendCode = button(/^(send code|send verification code|gửi mã|gửi mã xác minh)$/i);
  if (sendCode) {
    if (clickOnce(sendCode)) return 'verification-requested';
    return 'waiting-result';
  }
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
