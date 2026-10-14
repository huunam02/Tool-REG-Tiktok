// Run with: node --test test/auto_login_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/core/scripts/auto_login_script.dart', `file://${__filename}`), 'utf8',
);
const step = source.match(/autoLoginStepScript = r'''([\s\S]*?)''';/)[1];
const flush = () => new Promise(setImmediate);

function setup({ autoPaste = true, pasteResult = true, sendCodeAcknowledged = true } = {}) {
  const elements = [];
  const requests = [];
  const pending = [];
  let time = 0;
  const config = { email: 'test@example.com', password: 'test-password', attempt: 1 };
  const location = {
    origin: 'https://www.tiktok.com', pathname: '/login/phone-or-email/email',
  };
  const document = {
    hidden: false, activeElement: null,
    querySelectorAll: (selector) => elements.filter(
      (element) => selector.split(', ').some(part => part === element.selector || element.selectors?.includes(part)),
    ),
  };
  class Input {
    constructor(selector) {
      this.selector = selector;
      this.value = '';
      this.hidden = false;
      this.disabled = false;
      this.readOnly = false;
      this.isConnected = true;
      this.tagName = 'INPUT';
      this.parentElement = null;
      elements.push(this);
    }
    getClientRects() { return this.hidden ? [] : [{}]; }
    focus() { document.activeElement = this; }
    blur() { if (document.activeElement === this) document.activeElement = null; }
    select() {}
    dispatchEvent() { assert.fail('Input must be entered using native paste'); }
    closest() { return null; }
  }
  const email = new Input('input[name="username"]');
  const password = new Input('input[type="password"]');
  const submit = {
    selector: 'button', textContent: 'Log in', disabled: false, hidden: false, clicks: 0,
    getClientRects() { return this.hidden ? [] : [{}]; },
    getAttribute: (name) => name === 'data-e2e' ? 'login-button' : null,
    click() { this.clicks++; },
  };
  elements.push(submit);
  const window = {
    flutter_inappwebview: {
      callHandler(...args) {
        requests.push(args);
        return new Promise(resolve => pending.push(() => {
          if (autoPaste && pasteResult) document.activeElement.value = config[args[2]];
          resolve(pasteResult);
        }));
      },
    },
  };
  const execute = runInNewContext(`(${step})`, {
    window, location, document,
    Date: class extends Date { static now() { return time; } },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
  });
  return {
    window, location, document, email, password, submit, config, Input, requests,
    run: (allowSubmit = true, attempt = 1) => execute({ ...config, attempt }, allowSubmit),
    advance: (ms) => { time += ms; },
    resolvePaste: async () => { pending.shift()(); await flush(); },
    add: (selector, textContent = '') => {
      const element = { selector, textContent, disabled: false, hidden: false, clicks: 0,
        getClientRects() { return this.hidden ? [] : [{}]; }, getAttribute: () => null,
        click() {
          this.clicks++;
          if (sendCodeAcknowledged && /^(send code|send verification code)$/i.test(this.textContent.trim())) {
            this.textContent = 'Resend code (60s)';
            this.disabled = true;
          }
        },
        querySelectorAll() { return []; },
      };
      elements.push(element);
      return element;
    },
  };
}

async function fill(env) {
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
}

test('Android sends code through accessibility once and waits for TikTok feedback', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  env.email.value = env.config.email;
  env.password.value = env.config.password;
  new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  assert.equal(env.run(), 'requesting-verification');
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  assert.equal(send.clicks, 0);
  assert.deepEqual(env.requests, [['FlutterLoginSendCode', 1]]);
  const state = env.window.__flutterAutoLogin;
  assert.equal(state.canSendCodeWithAccessibility(1), true);
  assert.equal(state.canSendCodeWithAccessibility(2), false);
  send.disabled = true;
  assert.equal(state.canSendCodeWithAccessibility(1), false);
  send.textContent = 'Resend code 60s';
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  assert.equal(env.requests.length, 1);
});

test('accessibility failure stops without claiming a requested OTP or repeating the click', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  env.email.value = env.config.email;
  env.password.value = env.config.password;
  const send = env.add('button', 'Send code');
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(false);
  };
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  assert.equal(env.run(), 'send-code-accessibility-failed');
  assert.equal(env.run(), 'send-code-accessibility-failed');
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  assert.equal(env.requests.length, 1);
  assert.equal(send.clicks, 0);
});

test('DOM target accounts for the visual viewport and rejects covered or offscreen buttons', () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  env.email.value = env.config.email;
  env.password.value = env.config.password;
  const send = env.add('button', 'Send code');
  send.getBoundingClientRect = () => ({left: 150, top: 240, width: 100, height: 40});
  env.window.visualViewport = {offsetLeft: 100, offsetTop: 200, width: 400, height: 600};
  let covered = false;
  env.document.elementFromPoint = (x, y) => {
    assert.equal(x, 200);
    assert.equal(y, 260);
    return covered ? null : send;
  };
  env.window.flutter_inappwebview.callHandler = () => Promise.resolve(true);
  assert.equal(env.run(), 'requesting-verification');
  const state = env.window.__flutterAutoLogin;
  assert.deepEqual(JSON.parse(JSON.stringify(state.getSendCodeTarget(1))),
    {x: 100, y: 60, viewportWidth: 400, viewportHeight: 600});
  assert.equal(state.getSendCodeTarget(2), null);
  covered = true;
  assert.equal(state.getSendCodeTarget(1), null);
  covered = false;
  env.window.visualViewport.offsetTop = 300;
  assert.equal(state.getSendCodeTarget(1), null);
  state.stop();
  assert.equal(state.getSendCodeTarget(1), null);
});

test('identity Email selection can require a separate accessibility Send code click', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  const identity = identityDialog(env);
  const originalQuery = identity.modal.querySelectorAll;
  const send = env.add('button', 'Send code');
  send.hidden = true;
  identity.modal.querySelectorAll = selector => [
    ...originalQuery(selector), ...(selector.includes('button') ? [send] : []),
  ];
  assert.equal(env.run(false), 'email-verification-selected');
  identity.showCode();
  send.hidden = false;
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(false), 'requesting-verification');
  await flush();
  assert.equal(env.window.__flutterAutoLogin.canSendCodeWithAccessibility(1), true);
  assert.equal(env.run(false), 'requesting-verification');
  send.textContent = 'Resend code 60s';
  assert.equal(env.run(false), 'verification-requested');
  assert.deepEqual(env.requests, [['FlutterLoginSendCode', 1]]);
  assert.equal(send.clicks, 0);
});

test('detects an inline rate limit before pasting and after submission', async () => {
  const env = setup();
  const error = env.add('div', 'Maximum number of attempts reached. Try again later.');
  assert.equal(env.run(), 'account-rate-limited');
  assert.equal(env.requests.length, 0);
  error.hidden = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
  error.hidden = false;
  assert.equal(env.run(false), 'account-rate-limited');
  assert.equal(env.submit.clicks, 1);
  assert.equal(env.requests.length, 2);
});

test('ignores rate limit text when no account form is open', () => {
  const env = setup();
  env.location.pathname = '/';
  env.add('span', 'Too many requests. Try again later.');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 0);
});

function homeLogin(env, { navigate = false } = {}) {
  env.location.pathname = '/';
  const account = env.add('[data-e2e="nav-profile"]', 'Account');
  const modal = env.add('[role="dialog"]');
  const title = env.add('h2', 'Log in to TikTok');
  const method = env.add('[data-e2e="channel-item"]', 'Use phone / email / username');
  const phone = new env.Input('input[type="tel"]');
  const tab = env.add('a', 'Username or Email');
  const otp = new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  const members = new Set([title, method, phone, tab, otp, send, env.email, env.password, env.submit]);
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector).filter(el => members.has(el));
  modal.hidden = true;
  for (const el of members) el.hidden = true;
  account.click = () => {
    account.clicks++;
    modal.hidden = title.hidden = method.hidden = false;
  };
  method.click = () => {
    method.clicks++;
    method.hidden = true;
    phone.hidden = tab.hidden = otp.hidden = send.hidden = env.password.hidden = false;
    if (navigate) env.location.pathname = '/login/phone-or-email';
  };
  tab.click = () => {
    tab.clicks++;
    phone.hidden = tab.hidden = true;
    env.email.hidden = env.submit.hidden = false;
    if (navigate) env.location.pathname = '/login/phone-or-email/email';
  };
  return { account, modal, title, method, phone, tab, otp, send };
}

function identityDialog(env) {
  const modal = env.add('[aria-modal="true"]');
  const title = env.add('h2', 'Verify it’s\nreally you');
  const email = env.add('div', 'Email\nt***t@example.com');
  const phone = env.add('button', 'Phone');
  const code = new env.Input('input[autocomplete="one-time-code"]');
  const verify = env.add('button', 'Next');
  code.hidden = verify.hidden = true;
  const members = new Set([title, email, phone, code, verify]);
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector).filter(el => members.has(el));
  return {
    modal, title, email, phone, code, verify,
    showCode() {
      email.hidden = phone.hidden = true;
      title.textContent = 'Enter 6-digit code';
      code.hidden = verify.hidden = false;
    },
  };
}

test('Android Continue uses the live point inside the login modal after native paste', async () => {
  for (const label of ['Continue', 'Tiếp tục']) {
    const env = setup();
    env.config.useAccessibilityContinue = true;
    const flow = homeLogin(env);
    env.run(); env.run(); env.run();
    flow.send.hidden = flow.otp.hidden = true;
    env.submit.textContent = label;
    env.submit.getAttribute = () => null;
    env.submit.disabled = true;
    const outside = env.add('button', label);
    await fill(env);
    assert.equal(env.document.activeElement, null);
    assert.equal(env.run(), 'waiting-next');
    assert.equal(env.requests.length, 2);
    env.submit.getBoundingClientRect = () => ({left: 150, top: 240, width: 100, height: 40});
    env.window.visualViewport = {offsetLeft: 100, offsetTop: 200, width: 400, height: 600};
    env.document.elementFromPoint = () => env.submit;
    env.window.flutter_inappwebview.callHandler = (...args) => {
      env.requests.push(args);
      return Promise.resolve(true);
    };
    env.submit.disabled = false;
    assert.equal(env.run(), 'submitted');
    await flush();
    assert.deepEqual(env.requests[2], ['FlutterLoginPasswordContinue', 1]);
    assert.equal(env.submit.clicks, 0);
    assert.equal(outside.clicks, 0);
    const state = env.window.__flutterAutoLogin;
    assert.deepEqual(JSON.parse(JSON.stringify(state.getPasswordContinueTarget(1))),
      {x: 100, y: 60, viewportWidth: 400, viewportHeight: 600});
    assert.equal(state.getPasswordContinueTarget(2), null);
    env.submit.hidden = true;
    const replacement = env.add('button', label);
    const query = flow.modal.querySelectorAll;
    flow.modal.querySelectorAll = selector => [
      ...query(selector), ...(selector.includes('button') ? [replacement] : []),
    ];
    assert.equal(env.run(false), 'submitted');
    assert.equal(env.run(false), 'submitted');
    assert.equal(env.requests.length, 3);
    assert.equal(replacement.clicks, 0);
  }
});

test('password and OTP Continue dispatch independent gestures even when sharing a DOM button', async () => {
  const env = setup();
  env.config.useAccessibilityContinue = true;
  env.config.otp = '012345';
  env.email.value = env.config.email;
  env.password.value = env.config.password;
  env.submit.textContent = 'Continue';
  env.submit.getBoundingClientRect = () => ({left: 50, top: 100, width: 100, height: 40});
  env.window.visualViewport = {width: 400, height: 600};
  env.document.elementFromPoint = () => env.submit;
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(), 'submitted');
  await flush();
  const otp = new env.Input('input[name="code"]');
  otp.value = env.config.otp;
  assert.equal(env.run(false), 'otp-submitted');
  await flush();
  assert.deepEqual(env.requests, [
    ['FlutterLoginPasswordContinue', 1], ['FlutterLoginOtpContinue', 1],
  ]);
  const state = env.window.__flutterAutoLogin;
  assert.equal(state.getPasswordContinueTarget(1), null);
  assert.notEqual(state.getOtpContinueTarget(1), null);
  otp.value = '654321';
  assert.equal(state.getOtpContinueTarget(1), null);
  env.config.allowOtpSubmit = false;
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.requests.length, 2);
  assert.equal(env.submit.clicks, 0);
});

test('Continue gesture failures remain visible after either login submission is latched', async () => {
  for (const stage of ['password', 'otp']) {
    for (const rejected of [false, true]) {
      const env = setup();
      env.config.useAccessibilityContinue = true;
      env.email.value = env.config.email;
      env.password.value = env.config.password;
      env.submit.textContent = 'Continue';
      if (stage === 'otp') {
        env.config.otp = '012345';
        env.config.otpRequestedAt = 0;
        new env.Input('input[name="code"]').value = env.config.otp;
      }
      env.window.flutter_inappwebview.callHandler = (...args) => {
        env.requests.push(args);
        return rejected ? Promise.reject(new Error('gesture cancelled')) : Promise.resolve(false);
      };
      assert.equal(env.run(), stage === 'otp' ? 'otp-submitted' : 'submitted');
      await flush();
      env.config.allowOtpSubmit = false;
      assert.equal(env.run(false), 'continue-accessibility-failed');
      assert.equal(env.run(false), 'continue-accessibility-failed');
      assert.equal(env.submit.clicks, 0);
      assert.equal(env.requests.length, 1);
    }
  }
});

test('Continue rejects a changed password form, blocked button or stopped attempt before tapping', () => {
  const env = setup();
  env.config.useAccessibilityContinue = true;
  env.email.value = env.config.email;
  env.password.value = env.config.password;
  env.submit.textContent = 'Continue';
  const form = {querySelectorAll: () => [env.submit]};
  env.password.closest = () => form;
  env.submit.getBoundingClientRect = () => ({left: 50, top: 100, width: 100, height: 40});
  env.submit.contains = () => false;
  env.window.visualViewport = {width: 400, height: 600};
  env.document.elementFromPoint = () => env.submit;
  env.window.flutter_inappwebview.callHandler = () => Promise.resolve(true);
  assert.equal(env.run(), 'submitted');
  const state = env.window.__flutterAutoLogin;
  const target = () => state.getPasswordContinueTarget(1);
  assert.notEqual(target(), null);
  env.submit.disabled = true;
  assert.equal(target(), null);
  env.submit.disabled = false;
  env.document.elementFromPoint = () => env.add('div', 'overlay');
  assert.equal(target(), null);
  env.document.elementFromPoint = () => env.submit;
  env.password.closest = () => ({querySelectorAll: () => [env.submit]});
  assert.equal(target(), null);
  env.password.closest = () => form;
  env.password.value = 'another password';
  assert.equal(target(), null);
  env.password.value = env.config.password;
  env.location.pathname = '/signup';
  assert.equal(target(), null);
  env.location.pathname = '/login/phone-or-email/email';
  assert.notEqual(target(), null);
  state.stop();
  assert.equal(target(), null);
});

test('clicks the real IDV Email row instead of its non-clickable list wrapper', () => {
  for (const allowSubmit of [true, false]) {
    const env = setup();
    env.location.pathname = '/';
    const identity = identityDialog(env);
    const root = env.add('#idv-modal-container');
    const list = env.add('div', 'Email\nl***c@outlook.com');
    list.className = 'pc-home-items-l9mnww';
    const row = env.add('div', 'Email\nl***c@outlook.com');
    row.selectors = ['[class*="pc-home-item-"]'];
    row.className = 'pc-home-item-IxNc0F';
    const content = env.add('div', 'Email\nl***c@outlook.com');
    content.className = 'pc-home-item-content-W0UYH7';
    identity.email.hidden = true;
    const members = new Set([identity.title, list, row, content]);
    root.querySelectorAll = identity.modal.querySelectorAll = selector =>
      env.document.querySelectorAll(selector).filter(el => members.has(el));
    // This also covers starting a new login action while already at IDV.
    assert.equal(env.run(allowSubmit), 'email-verification-selected');
    assert.equal(row.clicks, 1);
    assert.equal(list.clicks, 0);
    assert.equal(content.clicks, 0);
    assert.equal(env.requests.length, 0);
  }
});

test('selects Email in the foreground identity dialog and waits for OTP feedback', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  const flow = homeLogin(env);
  env.run(); env.run(); env.run();
  flow.send.hidden = flow.otp.hidden = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
  // Keep the original login dialog visible underneath the identity overlay.
  const outsideEmail = env.add('button', 'Email');
  const identity = identityDialog(env);
  assert.equal(env.run(false), 'email-verification-selected');
  assert.equal(identity.email.clicks, 1);
  assert.equal(identity.phone.clicks, 0);
  assert.equal(outsideEmail.clicks, 0);
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  env.config.emailVerificationRequestedAt = 0;
  assert.equal(env.run(false), 'requesting-verification');
  env.advance(1000);
  assert.equal(env.run(false), 'requesting-verification');
  assert.equal(identity.email.clicks, 1);

  identity.showCode();
  identity.title.textContent = 'Verify identity';
  assert.equal(env.run(false), 'verification-requested');
  assert.equal(env.run(false), 'otp-required');
  env.config.otp = '012345';
  assert.equal(env.run(false), 'waiting-otp-paste');
  const state = env.window.__flutterAutoLogin;
  assert.equal(state.canPasteFromClipboard(1, 'otp', env.config.otp), true);
  await env.resolvePaste();
  assert.equal(identity.code.value, '012345');
  identity.verify.disabled = true;
  assert.equal(env.run(false), 'waiting-next');
  assert.equal(identity.verify.clicks, 0);
  identity.verify.disabled = false;
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(identity.verify.clicks, 1);
  assert.equal(env.submit.clicks, 1);
  assert.deepEqual(env.requests.map(request => request[2]), ['email', 'password', 'otp']);
  // A new document must not paste or click Next again while login completes.
  env.config.allowOtpSubmit = false;
  env.config.otpRequestedAt = 0;
  delete env.window.__flutterAutoLogin;
  identity.code.value = '';
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(identity.verify.clicks, 1);
  assert.equal(env.requests.length, 3);
  identity.modal.hidden = flow.modal.hidden = true;
  env.add('[data-e2e="profile-icon"]');
  assert.equal(env.run(false), 'login-success');
});

test('restores the Email request after navigation without clicking it again', async () => {
  const env = setup();
  env.location.pathname = '/';
  env.config.waitForOtpApi = true;
  const identity = identityDialog(env);
  assert.equal(env.run(false), 'email-verification-selected');
  env.config.emailVerificationRequestedAt = 0;
  delete env.window.__flutterAutoLogin;
  assert.equal(env.run(false), 'requesting-verification');
  assert.equal(identity.email.clicks, 1);
  identity.showCode();
  identity.title.textContent = 'Verify identity';
  assert.equal(env.run(false), 'verification-requested');
  env.config.otpRequestedAt = 0;
  delete env.window.__flutterAutoLogin;
  env.config.otp = '012345';
  assert.equal(env.run(false), 'waiting-otp-paste');
  assert.equal(env.window.__flutterAutoLogin.canPasteFromClipboard(), true);
  await env.resolvePaste();
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(identity.email.clicks, 1);
  assert.equal(identity.verify.clicks, 1);
});

test('does not claim a sent Email code or repeat the click without TikTok feedback', () => {
  const env = setup();
  env.location.pathname = '/';
  const identity = identityDialog(env);
  assert.equal(env.run(false), 'email-verification-selected');
  env.advance(14999);
  assert.equal(env.run(false), 'requesting-verification');
  env.advance(1);
  assert.equal(env.run(false), 'verification-request-failed');
  assert.equal(identity.email.clicks, 1);
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  assert.equal(env.requests.length, 0);
});

test('does not select Email while disabled, hidden, cancelled, at CAPTCHA or on signup', () => {
  for (const issue of ['disabled', 'hidden', 'cancelled', 'captcha', 'signup', 'origin']) {
    const env = setup();
    env.location.pathname = '/';
    const identity = identityDialog(env);
    if (issue === 'disabled') identity.email.disabled = true;
    if (issue === 'hidden') env.document.hidden = true;
    if (issue === 'cancelled') {
      env.window.__flutterAutoLogin = { attempt: 1, active: false };
    }
    if (issue === 'captcha') env.add('#captcha-verify-container');
    if (issue === 'signup') identity.title.textContent = 'Sign up';
    if (issue === 'origin') env.location.origin = 'https://example.com';
    assert.equal(env.run(false), {
      disabled: 'waiting-form', hidden: 'waiting-form', cancelled: 'cancelled',
      captcha: 'verification-required', signup: 'waiting-result', origin: 'wrong-origin',
    }[issue]);
    assert.equal(identity.email.clicks, 0);
    assert.equal(env.requests.length, 0);
  }
});

for (const navigate of [false, true]) {
  test(`opens Account, Login, phone/email, Username or Email and continues OTP (navigate=${navigate})`, async () => {
    const env = setup();
    env.config.waitForOtpApi = true;
    const flow = homeLogin(env, { navigate });
    if (!navigate) flow.method.textContent = 'Use phone or email';
    // Inputs and submit controls elsewhere on Home must remain untouched.
    const outside = new env.Input('input[name="email"]');
    const outsideSubmit = env.add('button', 'Log in');
    for (const control of [flow.account, flow.method, flow.tab]) {
      assert.equal(env.run(), 'waiting-form');
      assert.equal(control.clicks, 1);
      assert.equal(env.requests.length, 0);
      assert.equal(flow.send.clicks, 0);
    }
    assert.deepEqual([flow.account, flow.method, flow.tab].map(el => el.clicks), [1, 1, 1]);
    assert.equal(env.location.pathname, navigate ? '/login/phone-or-email/email' : '/');
    assert.equal(flow.phone.value, '');
    assert.equal(env.password.value, '');
    assert.equal(env.run(), 'waiting-paste');
    assert.equal(env.window.__flutterAutoLogin.canPasteFromClipboard(1, 'email', env.config.email), true);
    await env.resolvePaste();
    assert.equal(env.run(), 'waiting-next');
    await env.resolvePaste();
    assert.equal(env.run(), 'verification-requested');
    assert.equal(env.run(), 'otp-required');
    env.config.otp = '012345';
    assert.equal(env.run(), 'waiting-otp-paste');
    assert.equal(env.window.__flutterAutoLogin.canPasteFromClipboard(1, 'otp', env.config.otp), true);
    await env.resolvePaste();
    assert.equal(env.run(), 'otp-submitted');
    assert.equal(env.run(false), 'waiting-result');
    assert.equal(flow.otp.value, '012345');
    assert.equal(flow.send.clicks, 1);
    assert.equal(env.submit.clicks, 1);
    assert.equal(outside.value, '');
    assert.equal(outsideSubmit.clicks, 0);
    assert.deepEqual(env.requests.map(request => request[2]), ['email', 'password', 'otp']);
  });
}

test('continues password submission and a delayed OTP challenge inside the Home dialog', async () => {
  const env = setup();
  env.config.otp = '012345';
  env.submit.textContent = 'Continue';
  env.submit.getAttribute = () => null;
  const flow = homeLogin(env);
  env.run(); env.run(); env.run();
  flow.send.hidden = flow.otp.hidden = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
  flow.otp.hidden = false;
  assert.equal(env.run(false), 'waiting-otp-paste');
  assert.equal(env.run(false), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 2);
  assert.equal(flow.send.clicks, 0);
  assert.deepEqual([flow.account, flow.method, flow.tab].map(el => el.clicks), [1, 1, 1]);
});

test('waits for each navigation control without clicking it again and supports stopping on Home', () => {
  const env = setup();
  const flow = homeLogin(env);
  flow.account.click = () => { flow.account.clicks++; };
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(flow.account.clicks, 1);
  flow.modal.hidden = flow.title.hidden = flow.method.hidden = false;
  flow.method.click = () => { flow.method.clicks++; };
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(flow.method.clicks, 1);
  flow.method.hidden = true;
  flow.phone.hidden = flow.tab.hidden = false;
  flow.tab.click = () => { flow.tab.clicks++; };
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(flow.tab.clicks, 1);
  env.window.__flutterAutoLogin.stop();
  assert.equal(env.run(), 'cancelled');
  assert.equal(env.requests.length, 0);
});

test('recognizes email/username login tabs and never pastes or sends a code on the phone form', async () => {
  for (const label of ['Username or Email', 'Email or username', 'Log in with email or username', 'Use email or username']) {
    const env = setup();
    const flow = homeLogin(env);
    env.run();
    env.run();
    flow.tab.textContent = label;
    flow.tab.disabled = true;
    assert.equal(env.run(), 'waiting-form');
    assert.equal(env.requests.length, 0);
    assert.equal(flow.send.clicks, 0);
    assert.equal(env.password.value, '');
    flow.tab.disabled = false;
    assert.equal(env.run(), 'waiting-form');
    assert.equal(flow.tab.clicks, 1);
    await fill(env);
    assert.equal(env.run(), 'verification-requested');
  }
});

test('revokes native paste when the Home login dialog closes or switches to signup', async () => {
  const env = setup();
  const flow = homeLogin(env);
  env.run(); env.run(); env.run();
  assert.equal(env.run(), 'waiting-paste');
  const state = env.window.__flutterAutoLogin;
  assert.equal(state.canPasteFromClipboard(), true);
  flow.modal.hidden = true;
  assert.equal(state.canPasteFromClipboard(), false);
  flow.modal.hidden = false;
  flow.title.textContent = 'Sign up for TikTok';
  assert.equal(state.canPasteFromClipboard(), false);
  // A dialog takes precedence even if a login URL remains after an SPA switch.
  env.location.pathname = '/login/phone-or-email/email';
  assert.equal(state.canPasteFromClipboard(), false);
  state.stop();
  await env.resolvePaste();
});

test('does not reopen Account or navigate login methods after Flutter latched submission', () => {
  const env = setup();
  const flow = homeLogin(env);
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(flow.account.clicks, 0);
  flow.modal.hidden = flow.title.hidden = flow.method.hidden = false;
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(flow.method.clicks, 0);
  assert.equal(env.requests.length, 0);
});

test('pastes each login credential through the bridge and submits once', async () => {
  const env = setup();
  assert.equal(env.run(), 'waiting-paste');
  const state = env.window.__flutterAutoLogin;
  assert.equal(state.canPasteFromClipboard(1, 'email', env.config.email), true);
  assert.equal(state.canPasteFromClipboard(2, 'email', env.config.email), false);
  assert.equal(state.canPasteFromClipboard(1, 'password', env.config.password), false);
  assert.equal(env.email.value, '');
  assert.equal(env.run(), 'waiting-paste');
  assert.equal(env.requests.length, 1);
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(), 'submitted');
  assert.equal(env.email.value, 'test@example.com');
  assert.equal(env.password.value, 'test-password');
  assert.deepEqual(env.requests, [
    ['FlutterLoginPaste', 1, 'email'], ['FlutterLoginPaste', 1, 'password'],
  ]);
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
});

test('waits for a disabled submit button to become enabled', async () => {
  const env = setup();
  env.submit.disabled = true;
  await fill(env);
  assert.equal(env.run(), 'waiting-next');
  assert.equal(env.submit.clicks, 0);
  env.submit.disabled = false;
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
});

test('commits native input and clicks Continue without a login-button attribute once', async () => {
  for (const label of ['Continue', 'Tiếp tục']) {
    const env = setup();
    env.submit.textContent = label;
    env.submit.getAttribute = () => null;
    env.submit.disabled = true;
    env.submit.click = () => {
      assert.equal(env.document.activeElement, null);
      assert.equal(env.password.value, env.config.password);
      env.submit.clicks++;
    };
    await fill(env);
    assert.equal(env.document.activeElement, null);
    assert.equal(env.run(), 'waiting-next');
    assert.equal(env.submit.clicks, 0);
    env.submit.disabled = false;
    assert.equal(env.run(), 'submitted');
    assert.equal(env.run(), 'submitted');
    assert.equal(env.run(false), 'submitted');
    assert.equal(env.submit.clicks, 1);
    assert.equal(env.requests.length, 2);
  }
});

test('only uses Continue inside the password form', async () => {
  const env = setup();
  const outside = env.add('button', 'Continue');
  env.submit.textContent = 'Continue';
  env.submit.getAttribute = () => null;
  const form = { querySelectorAll: () => [env.submit] };
  env.password.closest = selector => selector === 'form' ? form : null;
  env.submit.disabled = true;
  await fill(env);
  assert.equal(env.run(), 'waiting-next');
  assert.equal(outside.clicks, 0);
  env.submit.disabled = false;
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
  assert.equal(outside.clicks, 0);
});

test('does not refill or resubmit after navigation when Flutter remembers submission', () => {
  const env = setup();
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.email.value, '');
  assert.equal(env.requests.length, 0);
  assert.equal(env.submit.clicks, 0);
});

test('does not paste credentials on another origin, non-login page, or hidden document', () => {
  for (const origin of ['http://www.tiktok.com', 'https://example.com', 'https://www.tiktok.com.example.com']) {
    const env = setup();
    env.location.origin = origin;
    assert.equal(env.run(), 'wrong-origin');
    assert.equal(env.requests.length, 0);
  }
  const env = setup();
  env.location.pathname = '/';
  assert.equal(env.run(), 'waiting-form');
  env.location.pathname = '/login';
  env.document.hidden = true;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 0);
});

test('hands CAPTCHA and missing verification codes to the user before pasting', () => {
  for (const selector of ['#captcha-verify-container', 'input[autocomplete="one-time-code"]']) {
    const env = setup();
    env.add(selector);
    assert.equal(env.run(), 'verification-required');
    assert.equal(env.requests.length, 0);
    assert.equal(env.submit.clicks, 0);
  }
});

test('reports a login error without retrying credentials', () => {
  const env = setup();
  env.add('[data-e2e="login-error"]', 'Invalid account');
  assert.equal(env.run(), 'login-error');
  assert.equal(env.submit.clicks, 0);
});

test('requires a visible account avatar to report a logged-in session', () => {
  const env = setup();
  env.add('[data-e2e="profile-icon"]');
  assert.equal(env.run(), 'already-logged-in');
  assert.equal(env.run(false), 'login-success');
  assert.equal(env.submit.clicks, 0);
});

test('requests a code once and pastes OTP as soon as it is ready', async () => {
  const env = setup();
  env.config.otp = '012345';
  const otp = new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(send.clicks, 1);
  assert.equal(otp.value, '');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.requests.length, 3);
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.window.__flutterAutoLogin.canPasteFromClipboard(1, 'otp', env.config.otp), true);
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  env.submit.disabled = true;
  assert.equal(env.run(), 'waiting-next');
  env.submit.disabled = false;
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(env.run(), 'waiting-result');
  assert.deepEqual(env.requests[2], ['FlutterLoginPaste', 1, 'otp']);
  assert.equal(env.submit.clicks, 1);
  assert.equal(send.clicks, 1);
});

test('login waits for Send code feedback and never clicks a replacement button', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  send.hidden = true;
  const replacement = env.add('button', 'Send code');
  env.advance(14999);
  assert.equal(env.run(), 'requesting-verification');
  env.advance(1);
  assert.equal(env.run(), 'verification-request-failed');
  assert.equal(send.clicks, 1);
  assert.equal(replacement.clicks, 0);
  assert.equal(env.requests.length, 2);
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
});

test('login starts OTP only after a delayed resend countdown confirms Send code', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  send.disabled = true;
  env.advance(3000);
  assert.equal(env.run(), 'requesting-verification');
  send.textContent = 'Resend code 43s';
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  assert.equal(send.clicks, 1);
});

test('login follows the code screen with a new heading after Send code', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const flow = homeLogin(env);
  env.run(); env.run(); env.run();
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  env.email.hidden = env.password.hidden = flow.send.hidden = true;
  flow.title.textContent = 'Enter 6-digit code';
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  assert.equal(flow.send.clicks, 1);
});

test('login does not reopen Account when React replaces its button', () => {
  const env = setup();
  env.location.pathname = '/';
  const account = env.add('[data-e2e="nav-profile"]', 'Account');
  assert.equal(env.run(), 'waiting-form');
  account.hidden = true;
  const replacement = env.add('[data-e2e="nav-profile"]', 'Account');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(account.clicks, 1);
  assert.equal(replacement.clicks, 0);
});

test('login keeps password and OTP submission latched after button replacement', async () => {
  const env = setup();
  env.config.otp = '012345';
  await fill(env);
  assert.equal(env.run(), 'submitted');
  env.submit.hidden = true;
  const replacement = env.add('button', 'Log in');
  assert.equal(env.run(false), 'submitted');
  assert.equal(replacement.clicks, 0);
  const otp = new env.Input('input[name="code"]');
  otp.value = env.config.otp;
  assert.equal(env.run(false), 'otp-submitted');
  replacement.hidden = true;
  const next = env.add('button', 'Next');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(replacement.clicks, 1);
  assert.equal(next.clicks, 0);
});

test('pastes an OTP challenge after password submission', async () => {
  const env = setup();
  env.config.otp = '123456';
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = new env.Input('input[autocomplete="one-time-code"]');
  assert.equal(env.run(false), 'waiting-otp-paste');
  assert.equal(env.run(false), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, env.config.otp);
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 2); // Password, then OTP.
});

test('preserves the request timestamp and submission latch across page replacement', async () => {
  const env = setup();
  env.config.otp = '654321';
  const otp = new env.Input('input[name="otp"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  env.config.otpRequestedAt = 0;
  delete env.window.__flutterAutoLogin;
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(send.clicks, 1);
  assert.equal(env.run(), 'otp-submitted');
  env.config.allowOtpSubmit = false;
  delete env.window.__flutterAutoLogin;
  otp.value = '';
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(otp.value, '');
  assert.equal(env.submit.clicks, 1);
});

test('preserves a manually entered OTP and stops at CAPTCHA even with a configured code', () => {
  const env = setup();
  env.config.otp = '123456';
  const otp = new env.Input('input[name="code"]');
  otp.value = '654321';
  assert.equal(env.run(), 'draft-exists');
  assert.equal(otp.value, '654321');
  env.add('#captcha-verify-container');
  assert.equal(env.run(), 'verification-required');
  assert.equal(env.requests.length, 0);
});

test('pastes credentials before waiting for a disabled Send code button', async () => {
  const env = setup();
  env.config.otp = '123456';
  const otp = new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  send.disabled = true;
  await fill(env);
  assert.equal(env.run(), 'waiting-submit');
  assert.equal(env.email.value, env.config.email);
  assert.equal(env.password.value, env.config.password);
  assert.equal(env.window.__flutterAutoLogin.otpRequestedAt, null);
  env.advance(10000);
  send.disabled = false;
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(otp.value, '');
  assert.equal(send.clicks, 1);
});

test('failed or ineffective native paste stops without submitting or retrying', async () => {
  for (const options of [{ pasteResult: false }, { autoPaste: false }]) {
    const env = setup(options);
    assert.equal(env.run(), 'waiting-paste');
    await env.resolvePaste();
    env.advance(2001);
    assert.equal(env.run(), 'paste-failed');
    assert.equal(env.requests.length, 1);
    assert.equal(env.submit.clicks, 0);
  }
});

test('revokes paste authorization after focus change, navigation, and cancellation', async () => {
  const env = setup();
  assert.equal(env.run(), 'waiting-paste');
  const state = env.window.__flutterAutoLogin;
  env.document.activeElement = env.password;
  assert.equal(state.canPasteFromClipboard(), false);
  env.document.activeElement = env.email;
  env.location.pathname = '/signup';
  assert.equal(state.canPasteFromClipboard(), false);
  env.location.pathname = '/login';
  state.stop();
  assert.equal(state.canPasteFromClipboard(), false);
  await env.resolvePaste();
  assert.equal(env.run(), 'cancelled');
  assert.equal(env.submit.clicks, 0);
});

test('preserves an existing login draft without pasting over it', () => {
  const env = setup();
  env.email.value = 'someone@example.com';
  assert.equal(env.run(), 'draft-exists');
  assert.equal(env.requests.length, 0);
  assert.equal(env.submit.clicks, 0);
});

test('waits for an API code without sending another challenge and pastes it natively', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  const otp = new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  env.advance(180000);
  assert.equal(env.run(), 'otp-required');
  assert.equal(send.clicks, 1);
  assert.equal(env.requests.length, 2);
  assert.equal(env.submit.clicks, 0);
  env.config.otp = '012345';
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(env.submit.clicks, 1);
});

test('reports the OTP challenge after password login while waiting for the API', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = new env.Input('input[name="code"]');
  assert.equal(env.run(false), 'otp-required');
  env.config.otp = '012345';
  assert.equal(env.run(false), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  assert.equal(env.run(false), 'otp-submitted');
});

test('still stops at CAPTCHA before fetching an API OTP', () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  new env.Input('input[name="code"]');
  env.add('#captcha-verify-container');
  assert.equal(env.run(), 'verification-required');
  assert.equal(env.requests.length, 0);
});
