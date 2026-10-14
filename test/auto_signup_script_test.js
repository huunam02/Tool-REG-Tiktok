// Run with: node --test test/auto_signup_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/core/scripts/auto_signup_script.dart', `file://${__filename}`), 'utf8',
);
const step = source.match(/autoSignupStepScript = r'''([\s\S]*?)''';/)[1];
const flush = () => new Promise(setImmediate);

function setup({ inputs = true, autoPaste = true, pasteResult = true, sendCodeAcknowledged = true } = {}) {
  const elements = [];
  const requests = [];
  const pending = [];
  const document = {
    hidden: false, activeElement: null,
    querySelectorAll: (selector) => elements.filter(
      (element) => selector.split(', ').includes(element.selector),
    ),
  };
  const location = { origin: 'https://www.tiktok.com', pathname: '/signup/phone-or-email' };
  const config = { email: 'test@example.com', password: 'test-password', month: 2, day: 3, year: 2001, attempt: 1, sendCodeDelayMs: 0, passwordSubmitDelayMs: 350 };
  let time = 0;
  function add(selector, textContent = '', tagName = 'DIV') {
    const element = {
      selector, textContent, tagName, value: '', disabled: false, readOnly: false,
      isConnected: true, hidden: false, clicks: 0, events: [],
      width: 100, height: 32,
      getClientRects() { return this.hidden ? [] : [{ width: this.width, height: this.height }]; },
      getAttribute() { return null; },
      focus() { document.activeElement = this; }, select() {},
      blur() { if (document.activeElement === this) document.activeElement = null; },
      click() {
        this.clicks++;
        this.events.push('click');
        if (sendCodeAcknowledged && /^(send code|send verification code)$/i.test(this.textContent.trim())) {
          this.textContent = 'Resend code (60s)';
          this.disabled = true;
        }
      },
      dispatchEvent(event) { this.events.push(event.type); },
      querySelectorAll() { return []; },
      querySelector() { return null; },
    };
    elements.push(element);
    return element;
  }
  const email = inputs ? add('input[name="email"]', '', 'INPUT') : null;
  const password = inputs ? add('input[type="password"]', '', 'INPUT') : null;
  const submit = add('button', 'Sign up', 'BUTTON');
  const window = {
    flutter_inappwebview: {
      callHandler(...args) {
        requests.push(args);
        return new Promise((resolve) => {
          const finish = () => {
            if (autoPaste && pasteResult) {
              document.activeElement.value = config[args[2]];
            }
            resolve(pasteResult);
          };
          pending.push(finish);
        });
      },
    },
  };
  class Select {
    constructor(options) {
      Object.assign(this, add('select', '', 'SELECT'));
      delete this.dispatchEvent;
      elements[elements.length - 1] = this;
      this.options = options;
      this.events = [];
    }
    get value() { return this._value; }
    set value(value) { this._value = value; }
    dispatchEvent(event) { this.events.push(event.type); }
  }
  const execute = runInNewContext(`(${step})`, {
    window, document, location, HTMLSelectElement: Select,
    Math: Object.assign(Object.create(Math), { random: () => 0.5 }),
    Event: class { constructor(type) { this.type = type; } },
    Date: class extends Date { static now() { return time; } },
    innerWidth: 400, innerHeight: 800,
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
  });
  return {
    window, document, location, config, email, password, submit, requests, add, Select,
    run: (allowSubmit = true) => execute(config, allowSubmit),
    advance: (ms) => { time += ms; },
    resolvePaste: async () => { pending.shift()(); await flush(); },
  };
}

async function fill(env) {
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
}

test('post-OTP Sign up waits ten seconds and dispatches a separate native gesture once', async () => {
  const env = setup();
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.allowOtpSubmit = false;
  env.config.useAccessibilityPasswordSubmit = true;
  delete env.config.passwordSubmitDelayMs;
  env.password.value = env.config.password;
  env.submit.getBoundingClientRect = () => ({left: 150, top: 240, width: 100, height: 40});
  env.window.visualViewport = {offsetLeft: 100, offsetTop: 200, width: 400, height: 600};
  env.document.elementFromPoint = () => env.submit;
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(350);
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(9999);
  assert.equal(env.run(false), 'waiting-password-submit');
  assert.equal(env.requests.length, 0);
  env.advance(1);
  assert.equal(env.run(false), 'password-submitted');
  await flush();
  assert.deepEqual(env.requests, [['FlutterSignupPasswordSubmit', 1]]);
  assert.equal(env.submit.clicks, 0);
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.canSubmitPasswordWithAccessibility(1), true);
  assert.equal(state.canSubmitPasswordWithAccessibility(2), false);
  assert.deepEqual(JSON.parse(JSON.stringify(state.getPasswordSubmitTarget(1))),
    {x: 100, y: 60, viewportWidth: 400, viewportHeight: 600});
  env.document.elementFromPoint = () => null;
  assert.equal(state.getPasswordSubmitTarget(1), null);
  env.config.allowPasswordSubmit = false;
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.requests.length, 1);
});

test('watches and likes a Home video before opening the signup flow', () => {
  const env = setup({ inputs: false });
  env.location.pathname = '/';
  const video = env.add('video', '', 'VIDEO');
  video.currentTime = 8.1;
  video.duration = 10;
  video.paused = true;
  video.ended = false;
  video.play = () => { video.paused = false; return Promise.resolve(); };
  video.getBoundingClientRect = () => ({left: 0, top: 0, right: 400, bottom: 800});
  const like = env.add('button', 'Like', 'BUTTON');
  const article = { querySelectorAll: () => [like] };
  video.closest = () => article;

  assert.equal(env.run(), 'home-video-liked');
  assert.equal(like.clicks, 1);
  assert.equal(env.run(), 'waiting-login-modal');
  assert.equal(like.clicks, 1);
});

test('failed Sign up gesture remains visible after Flutter latches final submission', async () => {
  const env = setup();
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.useAccessibilityPasswordSubmit = true;
  env.password.value = env.config.password;
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(false);
  };
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(350);
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(350);
  assert.equal(env.run(false), 'password-submitted');
  await flush();
  env.config.allowPasswordSubmit = false;
  assert.equal(env.run(false), 'password-submit-accessibility-failed');
  assert.equal(env.run(false), 'password-submit-accessibility-failed');
  assert.equal(env.submit.clicks, 0);
  assert.equal(env.requests.length, 1);
});

test('Sign up restarts its ten-second delay after the button is disabled or replaced', () => {
  const env = setup();
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.useAccessibilityPasswordSubmit = true;
  delete env.config.passwordSubmitDelayMs;
  env.password.value = env.config.password;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(350);
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(9999);
  env.submit.disabled = true;
  assert.equal(env.run(false), 'waiting-password-submit');
  env.submit.disabled = false;
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(9999);
  env.submit.hidden = true;
  const replacement = env.add('button', 'Sign up', 'BUTTON');
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(9999);
  assert.equal(env.run(false), 'waiting-password-submit');
  env.window.__flutterAutoSignup.stop();
  env.advance(1);
  assert.equal(env.run(false), 'cancelled');
  assert.equal(env.requests.length, 0);
  assert.equal(replacement.clicks, 0);
});

test('signup waits five seconds before the gesture; acknowledgement timeout starts after tapping', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  delete env.config.sendCodeDelayMs; // Use the production default.
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(), 'waiting-send-code');
  assert.equal(env.window.__flutterAutoSignup.codeRequest, null);
  env.advance(4999);
  assert.equal(env.run(), 'waiting-send-code');
  assert.equal(env.requests.length, 2); // Credential pastes only.
  assert.equal(send.clicks, 0);
  env.advance(1);
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  assert.equal(env.window.__flutterAutoSignup.codeRequest.at, 5000);
  env.advance(14999);
  assert.equal(env.run(), 'requesting-verification');
  env.advance(1);
  assert.equal(env.run(), 'verification-request-failed');
  assert.equal(env.requests.filter(args => args[0] === 'FlutterSignupSendCode').length, 1);
});

test('signup restarts the delay if the button becomes disabled or is replaced', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  env.config.sendCodeDelayMs = 5000;
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'waiting-send-code');
  env.advance(4000);
  send.disabled = true;
  assert.equal(env.run(), 'waiting-form');
  send.disabled = false;
  assert.equal(env.run(), 'waiting-send-code');
  env.advance(4000);
  send.hidden = true;
  env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-send-code');
  env.advance(4999);
  assert.equal(env.run(), 'waiting-send-code');
  assert.equal(env.requests.length, 2);
});

test('cancelling signup or encountering CAPTCHA during the delay prevents the gesture', async () => {
  for (const reason of ['cancel', 'captcha']) {
    const env = setup();
    env.config.useAccessibilitySendCode = true;
    env.config.waitForOtpApi = true;
    env.config.sendCodeDelayMs = 5000;
    const send = env.add('button', 'Send code', 'BUTTON');
    await fill(env);
    assert.equal(env.run(), 'waiting-send-code');
    if (reason === 'cancel') env.window.__flutterAutoSignup.stop();
    else env.add('#captcha-verify-container');
    env.advance(5000);
    assert.equal(env.run(), reason === 'cancel' ? 'cancelled' : 'verification-required');
    assert.equal(env.requests.length, 2);
    assert.equal(send.clicks, 0);
  }
});

test('Android signup sends code via the gesture bridge exactly once after pasting credentials', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.email.value, env.config.email);
  assert.equal(env.password.value, env.config.password);
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  assert.equal(env.run(), 'requesting-verification');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
  assert.equal(env.window.__flutterAutoSignup.canSendCodeWithAccessibility(1), true);
  assert.equal(env.window.__flutterAutoSignup.canSendCodeWithAccessibility(2), false);
  assert.equal(send.clicks, 0);
  assert.deepEqual(env.requests[2], ['FlutterSignupSendCode', 1]);
  send.textContent = 'Resend code (60s)';
  send.disabled = true;
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  assert.equal(env.requests.length, 3);
});

test('signup gesture failure stops without sending a DOM click or claiming an OTP request', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(false);
  };
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  assert.equal(env.run(), 'send-code-accessibility-failed');
  assert.equal(env.run(), 'send-code-accessibility-failed');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
  assert.equal(send.clicks, 0);
  assert.equal(env.requests.length, 3);
});

test('signup native target handles viewport offsets and rejects another overlay or stopped attempt', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  send.getBoundingClientRect = () => ({left: 150, top: 240, width: 100, height: 40});
  env.window.visualViewport = {offsetLeft: 100, offsetTop: 200, width: 400, height: 600};
  env.document.elementFromPoint = () => send;
  await fill(env);
  env.window.flutter_inappwebview.callHandler = () => Promise.resolve(true);
  assert.equal(env.run(), 'requesting-verification');
  const state = env.window.__flutterAutoSignup;
  assert.deepEqual(JSON.parse(JSON.stringify(state.getSendCodeTarget(1))),
    {x: 100, y: 60, viewportWidth: 400, viewportHeight: 600});
  assert.equal(state.getSendCodeTarget(2), null);
  env.document.elementFromPoint = () => null;
  assert.equal(state.getSendCodeTarget(1), null);
  env.document.elementFromPoint = () => send;
  state.stop();
  assert.equal(state.getSendCodeTarget(1), null);
});

test('signup does not request another gesture when React replaces the button', async () => {
  const env = setup();
  env.config.useAccessibilitySendCode = true;
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(), 'requesting-verification');
  await flush();
  send.hidden = true;
  const replacement = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'requesting-verification');
  env.advance(15000);
  assert.equal(env.run(), 'verification-request-failed');
  assert.equal(env.requests.filter(args => args[0] === 'FlutterSignupSendCode').length, 1);
  assert.equal(replacement.clicks, 0);
});

async function reachUsernameScreen() {
  const env = setup();
  env.location.pathname = '/';
  env.config.waitForOtpApi = true;
  env.password.hidden = true;
  const modal = env.add('[role="dialog"]');
  const title = env.add('h2', 'Sign up');
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector);
  const send = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'verification-requested');
  env.config.otpRequestedAt = 0;
  env.email.hidden = send.hidden = true;
  const otp = env.add('input[name="code"]', '', 'INPUT');
  env.config.otp = '012345';
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'otp-submitted');
  env.config.allowOtpSubmit = false;
  otp.hidden = true;
  env.password.hidden = false;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(false), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  env.config.allowPasswordSubmit = false;
  env.password.hidden = env.submit.hidden = true;
  const heading = env.add('div', 'Create username');
  const username = env.add('input[name="username"]', '', 'INPUT');
  username.value = 'Huu Nam';
  const warning = env.add('[role="alert"]', 'This username isn’t available.');
  const next = env.add('button', 'Continue', 'BUTTON');
  next.disabled = true;
  const skip = env.add('span', 'Skip');
  return { ...env, modal, title, heading, username, warning, next, skip };
}

test('Android skips username via a separate gesture once after the two-second delay', async () => {
  for (const vietnamese of [false, true]) {
    const env = await reachUsernameScreen();
    env.config.useAccessibilityUsernameSkip = true;
    if (vietnamese) {
      env.title.textContent = 'Đăng ký';
      env.heading.textContent = 'Tạo tên người dùng';
      env.skip.textContent = 'Bỏ qua';
    }
    env.skip.getBoundingClientRect = () => ({left: 150, top: 240, width: 100, height: 40});
    env.window.visualViewport = {offsetLeft: 100, offsetTop: 200, width: 400, height: 600};
    env.document.elementFromPoint = () => env.skip;
    env.window.flutter_inappwebview.callHandler = (...args) => {
      env.requests.push(args);
      return Promise.resolve(true);
    };
    assert.equal(env.run(false), 'waiting-username-skip');
    env.advance(1999);
    assert.equal(env.run(false), 'waiting-username-skip');
    assert.equal(env.requests.length, 3); // Credential pastes only.
    env.advance(1);
    assert.equal(env.run(false), 'username-skipped');
    await flush();
    assert.deepEqual(env.requests[3], ['FlutterSignupUsernameSkip', 1]);
    assert.equal(env.skip.clicks, 0);
    assert.equal(env.next.clicks, 0);
    assert.equal(env.username.value, 'Huu Nam');
    const state = env.window.__flutterAutoSignup;
    assert.equal(state.canSkipUsernameWithAccessibility(1), true);
    assert.equal(state.canSkipUsernameWithAccessibility(2), false);
    assert.deepEqual(JSON.parse(JSON.stringify(state.getUsernameSkipTarget(1))),
      {x: 100, y: 60, viewportWidth: 400, viewportHeight: 600});
    env.skip.hidden = true;
    const replacement = env.add('button', 'Skip', 'BUTTON');
    env.advance(10000);
    assert.equal(env.run(false), 'waiting-result');
    assert.equal(replacement.clicks, 0);
    assert.equal(env.requests.length, 4);
    env.add('[data-e2e="profile-icon"]');
    env.modal.hidden = env.title.hidden = env.heading.hidden = true;
    assert.equal(env.run(false), 'signup-success');
  }
});

test('a failed username Skip gesture stops without a DOM fallback or another gesture', async () => {
  for (const rejected of [false, true]) {
    const env = await reachUsernameScreen();
    env.config.useAccessibilityUsernameSkip = true;
    env.window.flutter_inappwebview.callHandler = (...args) => {
      env.requests.push(args);
      return rejected ? Promise.reject(new Error('gesture cancelled')) : Promise.resolve(false);
    };
    assert.equal(env.run(false), 'waiting-username-skip');
    env.advance(2000);
    assert.equal(env.run(false), 'username-skipped');
    await flush();
    assert.equal(env.run(false), 'username-skip-accessibility-failed');
    assert.equal(env.run(false), 'username-skip-accessibility-failed');
    assert.equal(env.window.__flutterAutoSignup.getUsernameSkipTarget(1), null);
    assert.equal(env.skip.clicks, 0);
    assert.equal(env.requests.length, 4);
  }
});

test('the Skip gesture target rejects a stale modal, blocked control or cancelled attempt', async () => {
  const env = await reachUsernameScreen();
  env.config.useAccessibilityUsernameSkip = true;
  env.skip.getBoundingClientRect = () => ({left: 50, top: 100, width: 100, height: 40});
  env.skip.contains = () => false;
  env.window.visualViewport = {width: 400, height: 600};
  env.document.elementFromPoint = () => env.skip;
  env.window.flutter_inappwebview.callHandler = () => Promise.resolve(true);
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(2000);
  assert.equal(env.run(false), 'username-skipped');
  const state = env.window.__flutterAutoSignup;
  const target = () => state.getUsernameSkipTarget(1);
  assert.notEqual(target(), null);
  env.skip.disabled = true;
  assert.equal(target(), null);
  env.skip.disabled = false;
  env.skip.hidden = true;
  assert.equal(target(), null);
  env.skip.hidden = false;
  env.document.elementFromPoint = () => env.next;
  assert.equal(target(), null);
  env.document.elementFromPoint = () => env.skip;
  env.modal.hidden = true;
  env.add('[role="dialog"]');
  assert.equal(target(), null);
  env.modal.hidden = false;
  env.heading.hidden = true;
  assert.equal(target(), null);
  env.heading.hidden = false;
  env.password.hidden = false;
  assert.equal(target(), null);
  env.password.hidden = true;
  assert.notEqual(target(), null);
  state.stop();
  assert.equal(target(), null);
});

test('after OTP and password waits two seconds then skips an unavailable username once', async () => {
  const env = await reachUsernameScreen();
  env.add('[data-e2e="profile-icon"]'); // Already visible behind the dialog.
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(1999);
  assert.equal(env.run(false), 'waiting-username-skip');
  assert.equal(env.skip.clicks, 0);
  env.advance(1);
  assert.equal(env.run(false), 'username-skipped');
  assert.equal(env.skip.clicks, 1);
  assert.equal(env.next.clicks, 0);
  assert.equal(env.username.value, 'Huu Nam');
  assert.deepEqual(env.requests.map(request => request[2]), ['email', 'otp', 'password']);
  env.skip.hidden = true;
  const replacement = env.add('button', 'Skip', 'BUTTON');
  env.advance(10000);
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(replacement.clicks, 0);
  env.modal.hidden = env.title.hidden = env.heading.hidden = true;
  assert.equal(env.run(false), 'signup-success');
});

test('restores the username step after navigation using the final password submit guard', async () => {
  const env = await reachUsernameScreen();
  delete env.window.__flutterAutoSignup;
  env.title.textContent = 'Create username';
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(2000);
  assert.equal(env.run(false), 'username-skipped');
  assert.equal(env.skip.clicks, 1);
});

test('does not skip before signup submission or in an unrelated dialog', () => {
  for (const titleText of ['Sign up', 'Log in']) {
    const env = setup({ inputs: false });
    env.location.pathname = '/';
    const modal = env.add('[role="dialog"]');
    env.add('h2', titleText);
    env.add('div', 'Create username');
    const skip = env.add('button', 'Skip', 'BUTTON');
    modal.querySelectorAll = selector => env.document.querySelectorAll(selector);
    env.run();
    env.advance(10000);
    env.run();
    assert.equal(skip.clicks, 0);
  }
});

test('username delay respects cancellation, hidden pages, changed origin and CAPTCHA', async () => {
  for (const issue of ['cancelled', 'hidden', 'origin', 'captcha']) {
    const env = await reachUsernameScreen();
    assert.equal(env.run(false), 'waiting-username-skip');
    env.advance(2000);
    if (issue === 'cancelled') env.window.__flutterAutoSignup.stop();
    if (issue === 'hidden') env.document.hidden = true;
    if (issue === 'origin') env.location.origin = 'https://example.com';
    if (issue === 'captcha') env.add('#captcha-verify-container');
    assert.equal(env.run(false), {
      cancelled: 'cancelled', hidden: 'waiting-form', origin: 'wrong-origin',
      captcha: 'verification-required',
    }[issue]);
    assert.equal(env.skip.clicks, 0);
  }
});

test('restarts the username delay when Skip is disabled, hidden or replaced', async () => {
  for (const issue of ['disabled', 'hidden', 'aria-disabled', 'replaced']) {
    const env = await reachUsernameScreen();
    assert.equal(env.run(false), 'waiting-username-skip');
    env.advance(1999);
    if (issue === 'disabled') env.skip.disabled = true;
    if (issue === 'hidden' || issue === 'replaced') env.skip.hidden = true;
    if (issue === 'aria-disabled') env.skip.getAttribute = () => 'true';
    const target = issue === 'replaced' ? env.add('a', 'Skip', 'A') : env.skip;
    assert.equal(env.run(false), 'waiting-username-skip');
    env.skip.disabled = env.skip.hidden = false;
    env.skip.getAttribute = () => null;
    assert.equal(env.run(false), 'waiting-username-skip');
    env.advance(1999);
    assert.equal(env.run(false), 'waiting-username-skip');
    assert.equal(target.clicks, 0);
    env.advance(1);
    assert.equal(env.run(false), 'username-skipped');
    assert.equal(target.clicks, 1);
  }
});

test('supports Vietnamese username and Skip labels and ignores controls outside the signup modal', async () => {
  const env = await reachUsernameScreen();
  env.title.textContent = 'Đăng ký';
  env.heading.textContent = 'Tạo tên người dùng';
  env.skip.textContent = 'Bỏ qua';
  const outside = env.add('button', 'Skip', 'BUTTON');
  const members = new Set([env.title, env.heading, env.username, env.warning, env.next, env.skip]);
  env.modal.querySelectorAll = selector => env.document.querySelectorAll(selector).filter(el => members.has(el));
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(2000);
  assert.equal(env.run(false), 'username-skipped');
  assert.equal(env.skip.clicks, 1);
  assert.equal(outside.clicks, 0);
});

test('does not click a Skip text nested inside a disabled button', async () => {
  const env = await reachUsernameScreen();
  const button = env.add('button', 'Skip', 'BUTTON');
  button.disabled = true;
  env.skip.closest = () => button.disabled ? button : null;
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(5000);
  assert.equal(env.run(false), 'waiting-username-skip');
  assert.equal(env.skip.clicks, 0);
  assert.equal(button.clicks, 0);
  button.disabled = false;
  assert.equal(env.run(false), 'waiting-username-skip');
  env.advance(2000);
  assert.equal(env.run(false), 'username-skipped');
  assert.equal(button.clicks, 1);
  assert.equal(env.skip.clicks, 0);
});

test('detects a plain inline rate limit before pasting or requesting a code', () => {
  for (const selector of ['div', 'span', '[role="alert"]']) {
    const env = setup();
    env.add(selector, 'Maximum number of attempts reached.\nTry again later.');
    const send = env.add('button', 'Send code', 'BUTTON');
    assert.equal(env.run(), 'account-rate-limited');
    assert.equal(env.requests.length, 0);
    assert.equal(env.submit.clicks, 0);
    assert.equal(send.clicks, 0);
  }
});

test('detects the screenshot error after submitting the separate password step', async () => {
  const env = setup();
  env.config.otpRequestedAt = 0;
  env.email.hidden = true;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(false), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  env.add('div', 'Maximum number of attempts reached. Try again later.');
  env.config.allowPasswordSubmit = false;
  assert.equal(env.run(false), 'account-rate-limited');
  assert.equal(env.run(false), 'account-rate-limited');
  assert.equal(env.submit.clicks, 1);
  assert.equal(env.requests.length, 1);
});

test('ignores rate limit text outside the active signup dialog or hidden in it', () => {
  const env = setup();
  env.location.pathname = '/';
  const outside = env.add('div', 'Maximum number of attempts reached. Try again later.');
  const modal = env.add('[role="dialog"]');
  env.add('h2', 'Sign up');
  const hidden = env.add('span', 'Too many attempts. Try again later.');
  hidden.hidden = true;
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector).filter(el => el !== outside);
  assert.equal(env.run(), 'waiting-paste');
  hidden.hidden = false;
  assert.equal(env.run(), 'account-rate-limited');
});

function newsletter(env, checked = false) {
  const label = env.add('label',
    'Get trending content, newsletters, promotions, recommendations and account updates sent to your email', 'LABEL');
  const checkbox = env.add('input[type="checkbox"]', '', 'INPUT');
  checkbox.type = 'checkbox';
  checkbox.checked = checked;
  checkbox.click = () => { checkbox.clicks++; checkbox.checked = !checkbox.checked; };
  // The actual TikTok label and hidden native checkbox share a parent div.
  checkbox.hidden = true;
  label.parentElement = { querySelector: () => checkbox };
  return checkbox;
}

test('opens Home Account, Login, Sign up, phone/email and Use Email before the existing OTP flow', async () => {
  const env = setup({ inputs: false });
  env.location.pathname = '/';
  env.config.otp = '012345';
  env.submit.hidden = true;
  const account = env.add('[data-e2e="nav-profile"]', 'Account');
  const modal = env.add('[role="dialog"]');
  modal.hidden = true;
  const title = env.add('h2', 'Log in to TikTok');
  const signup = env.add('[data-e2e="bottom-sign-up"]', 'Sign up', 'SPAN');
  const method = env.add('[data-e2e="channel-item"]', 'Use phone or email');
  const phone = env.add('input[type="tel"]', '', 'INPUT');
  const emailTab = env.add('a', 'Use Email', 'A');
  const email = env.add('input[name="email"]', '', 'INPUT');
  const password = env.add('input[type="password"]', '', 'INPUT');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  const members = new Set([title, signup, method, phone, emailTab, email, password, otp, sendCode, env.submit]);
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector).filter(el => members.has(el));
  for (const el of members) el.hidden = true;
  // An unrelated editor outside the dialog must never receive signup data.
  const outside = env.add('input[type="email"]', '', 'INPUT');
  account.click = () => {
    account.clicks++;
    modal.hidden = title.hidden = signup.hidden = false;
  };
  signup.click = () => {
    signup.clicks++;
    title.textContent = 'Sign up for TikTok';
    signup.hidden = true;
    method.hidden = false;
  };
  method.click = () => {
    method.clicks++;
    method.hidden = true;
    phone.hidden = emailTab.hidden = false;
  };
  emailTab.click = () => {
    emailTab.clicks++;
    phone.hidden = emailTab.hidden = true;
    email.hidden = password.hidden = otp.hidden = sendCode.hidden = env.submit.hidden = false;
  };
  for (let i = 0; i < 4; i++) {
    assert.equal(env.run(), 'waiting-form');
    assert.equal(env.requests.length, 0);
    assert.equal(sendCode.clicks, 0);
  }
  assert.deepEqual([account, signup, method, emailTab].map(el => el.clicks), [1, 1, 1, 1]);
  assert.equal(env.location.pathname, '/');
  assert.equal(phone.value, '');
  assert.equal(outside.value, '');
  assert.equal(env.run(), 'waiting-paste');
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(1, 'email', env.config.email), true);
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(env.run(false), 'submitted');
  assert.equal(sendCode.clicks, 1);
  assert.equal(env.submit.clicks, 1);
  assert.deepEqual(env.requests.map(request => request[2]), ['email', 'password', 'otp']);
});

test('waits for navigation without clicking Account or Sign up again', () => {
  const env = setup({ inputs: false });
  env.location.pathname = '/';
  env.submit.hidden = true;
  const account = env.add('a[href^="/profile"]', 'Account', 'A');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(account.clicks, 1);
  env.location.pathname = '/login';
  env.submit.hidden = false;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.submit.clicks, 1);
  assert.equal(account.clicks, 1);
  env.window.__flutterAutoSignup.stop();
  assert.equal(env.run(), 'cancelled');
  assert.equal(env.requests.length, 0);
});

test('never pastes signup credentials into a login dialog or after the signup dialog closes', async () => {
  const env = setup();
  env.location.pathname = '/';
  const modal = env.add('[role="dialog"]');
  const title = env.add('h2', 'Log in to TikTok');
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector);
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 0);
  assert.equal(sendCode.clicks, 0);
  title.textContent = 'Sign up for TikTok';
  assert.equal(env.run(), 'waiting-paste');
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.canPasteFromClipboard(), true);
  title.textContent = 'Log in to TikTok';
  assert.equal(state.canPasteFromClipboard(), false);
  title.textContent = 'Sign up for TikTok';
  modal.hidden = true;
  assert.equal(state.canPasteFromClipboard(), false);
  state.stop();
  await env.resolvePaste();
});

test('checks the newsletter option once before pasting and requesting a code', async () => {
  const env = setup();
  const checkbox = newsletter(env);
  const unrelated = env.add('input[type="checkbox"]', '', 'INPUT');
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(checkbox.checked, true);
  assert.equal(env.requests.length, 0);
  assert.equal(sendCode.clicks, 0);
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'waiting-result');
  assert.equal(checkbox.checked, true);
  assert.equal(checkbox.clicks, 1);
  assert.equal(unrelated.clicks, 0);
});

test('keeps an already checked newsletter option checked', async () => {
  const env = setup();
  const checkbox = newsletter(env, true);
  await fill(env);
  assert.equal(env.run(), 'submitted');
  assert.equal(checkbox.checked, true);
  assert.equal(checkbox.clicks, 0);
});

test('stops if the newsletter checkbox rejects the change without requesting a code', () => {
  const env = setup();
  const checkbox = newsletter(env);
  checkbox.click = () => { checkbox.clicks++; };
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'checkbox-failed');
  assert.equal(checkbox.clicks, 1);
  assert.equal(sendCode.clicks, 0);
  assert.equal(env.requests.length, 0);
});

test('pastes each credential through the bridge and submits once', async () => {
  const env = setup();
  assert.equal(env.run(), 'waiting-paste');
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(1, 'email', env.config.email), true);
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(2, 'email', env.config.email), false);
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(1, 'password', env.config.password), false);
  assert.equal(env.email.value, '');
  assert.equal(env.run(), 'waiting-paste');
  assert.equal(env.requests.length, 1);
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
  assert.deepEqual(env.requests, [
    ['FlutterSignupPaste', 1, 'email'], ['FlutterSignupPaste', 1, 'password'],
  ]);
  assert.equal(env.run(), 'submitted');
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
});

test('does not paste or submit on another origin, page, or while hidden', () => {
  for (const origin of ['http://www.tiktok.com', 'https://example.com', 'https://www.tiktok.com.example.com']) {
    const env = setup();
    env.location.origin = origin;
    assert.equal(env.run(), 'wrong-origin');
    assert.equal(env.requests.length, 0);
  }
  const env = setup();
  env.location.pathname = '/login';
  assert.equal(env.run(), 'waiting-form');
  env.location.pathname = '/signup';
  env.document.hidden = true;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 0);
});

test('preserves an existing draft', () => {
  const env = setup();
  env.email.value = 'someone@example.com';
  assert.equal(env.run(), 'draft-exists');
  assert.equal(env.requests.length, 0);
  assert.equal(env.submit.clicks, 0);
});

test('switches from phone signup to email before pasting or sending a code', async () => {
  for (const label of ['Sign up with email', 'Đăng ký bằng email', 'Email']) {
    const env = setup();
    env.email.hidden = true;
    const phone = env.add('input[type="tel"]', '', 'INPUT');
    env.add('input[name="code"]', '', 'INPUT');
    const sendCode = env.add('button', 'Send code', 'BUTTON');
    const tab = env.add('a', label, 'A');
    assert.equal(env.run(), 'waiting-form');
    assert.equal(env.run(), 'waiting-form');
    assert.equal(tab.clicks, 1);
    assert.equal(env.requests.length, 0);
    assert.equal(sendCode.clicks, 0);
    assert.equal(env.password.value, '');
    phone.hidden = true;
    tab.hidden = true;
    env.email.hidden = false;
    await fill(env);
    assert.equal(env.run(), 'verification-requested');
    assert.equal(sendCode.clicks, 1);
  }
});

test('waits without pasting or sending a code if the email switch is unavailable', () => {
  const env = setup();
  env.email.hidden = true;
  env.add('input[type="tel"]', '', 'INPUT');
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 0);
  assert.equal(sendCode.clicks, 0);
  assert.equal(env.submit.clicks, 0);
});

test('switches to email before birthday menus on the phone form from the screenshot', () => {
  const env = setup();
  env.email.hidden = true;
  env.password.hidden = true;
  env.add('input[name="mobile"]', '', 'INPUT');
  for (const label of ['Month', 'Day', 'Year']) env.add('[role="combobox"]', label);
  new env.Select([{ textContent: 'English (UK)', value: 'en-GB' }]);
  const tab = env.add('a', 'Sign up with email', 'A');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(tab.clicks, 1);
  assert.equal(env.requests.length, 0);
});

test('ignores an empty CAPTCHA container while filling the email form', async () => {
  const env = setup();
  const captcha = env.add('#captcha-verify-container');
  captcha.width = 0;
  captcha.height = 0;
  await fill(env);
  assert.equal(env.run(), 'submitted');
});

test('continues a password-only step after the email was entered', async () => {
  const env = setup();
  env.password.hidden = true;
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-next');
  env.email.hidden = true;
  env.password.hidden = false;
  assert.equal(env.run(), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.requests.length, 2);
  assert.equal(env.password.value, env.config.password);
  assert.equal(env.run(), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(), 'password-submitted');
  assert.equal(env.submit.clicks, 1);
});

test('continues from email and OTP to the password-only signup dialog and submits once', async () => {
  const env = setup();
  env.location.pathname = '/';
  env.config.waitForOtpApi = true;
  env.password.hidden = true;
  const modal = env.add('[role="dialog"]');
  const title = env.add('h2', 'Sign up');
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector);
  const send = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'verification-requested');
  env.config.otpRequestedAt = 0;
  env.email.hidden = send.hidden = true;
  title.textContent = 'Enter 6-digit code';
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(), 'otp-required');
  env.config.otp = '012345';
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'otp-submitted');
  env.config.allowOtpSubmit = false;
  assert.equal(env.run(false), 'waiting-result');

  otp.hidden = true;
  title.textContent = 'Sign up';
  env.password.hidden = false;
  env.submit.disabled = true;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(false), 'waiting-next');
  assert.equal(env.run(false), 'waiting-next');
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.canPasteFromClipboard(1, 'password', env.config.password), true);
  assert.equal(state.canPasteFromClipboard(1, 'otp', env.config.otp), false);
  await env.resolvePaste();
  assert.equal(env.password.value, env.config.password);
  assert.equal(env.document.activeElement, null);
  assert.equal(env.run(false), 'waiting-password-submit');
  assert.equal(env.submit.clicks, 1); // Only the earlier OTP submit.
  env.submit.disabled = false;
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 2);
  assert.equal(send.clicks, 1);
  assert.deepEqual(env.requests.map(request => request[2]), ['email', 'otp', 'password']);

  // Persist the final submit guard outside the page's JavaScript state.
  env.config.allowPasswordSubmit = false;
  delete env.window.__flutterAutoSignup;
  env.password.value = '';
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.requests.length, 3);
  assert.equal(env.submit.clicks, 2);
  env.add('[data-e2e="profile-icon"]');
  assert.equal(env.run(false), 'signup-success');
});

test('restores password paste authorization after navigation from OTP', async () => {
  const env = setup();
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.allowOtpSubmit = false;
  // There is no JavaScript state or remaining OTP value in the new document.
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(false), 'waiting-next');
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.emailEntered, false);
  assert.equal(state.canPasteFromClipboard(1, 'password', env.config.password), true);
  env.document.activeElement = null;
  assert.equal(state.canPasteFromClipboard(), false);
  env.password.focus();
  env.location.pathname = '/login';
  assert.equal(state.canPasteFromClipboard(), false);
  env.location.pathname = '/signup';
  await env.resolvePaste();
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  assert.equal(env.requests.length, 1);
  assert.equal(env.submit.clicks, 1);
});

test('paces the password screen and requires a stable enabled button before submitting', async () => {
  const env = setup();
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.allowOtpSubmit = false;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(349);
  assert.equal(env.run(false), 'waiting-password-screen');
  assert.equal(env.requests.length, 0);
  env.advance(1);
  assert.equal(env.run(false), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(349);
  assert.equal(env.run(false), 'waiting-password-submit');
  assert.equal(env.submit.clicks, 0);
  env.submit.disabled = true;
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(5000);
  env.submit.disabled = false;
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 1);
  assert.equal(env.requests.length, 1);
});

test('still checks cancellation, CAPTCHA and errors during password delays', async () => {
  for (const issue of ['cancelled', 'captcha', 'error']) {
    const env = setup();
    env.email.hidden = true;
    env.config.otpRequestedAt = 0;
    assert.equal(env.run(false), 'waiting-password-screen');
    env.advance(2500);
    assert.equal(env.run(false), 'waiting-next');
    await env.resolvePaste();
    assert.equal(env.run(false), 'waiting-password-submit');
    if (issue === 'cancelled') env.window.__flutterAutoSignup.stop();
    if (issue === 'captcha') env.add('#captcha-verify-container');
    if (issue === 'error') env.add('[role="alert"]', 'Too many attempts');
    env.advance(5000);
    assert.equal(env.run(false), {
      cancelled: 'cancelled', captcha: 'verification-required', error: 'account-rate-limited',
    }[issue]);
    assert.equal(env.submit.clicks, 0);
    assert.equal(env.requests.length, 1);
  }
});

test('preserves drafts and handles CAPTCHA or errors on the password step after OTP', () => {
  for (const issue of ['draft', 'captcha', 'error', 'phone', 'cancelled']) {
    const env = setup();
    env.email.hidden = true;
    env.config.otpRequestedAt = 0;
    env.config.allowOtpSubmit = false;
    if (issue === 'draft') env.password.value = 'user draft';
    if (issue === 'captcha') env.add('#captcha-verify-container');
    if (issue === 'error') env.add('[role="alert"]', 'Invalid password');
    if (issue === 'phone') env.add('input[type="tel"]', '', 'INPUT');
    if (issue === 'cancelled') {
      env.window.__flutterAutoSignup = { attempt: 1, active: false, otpRequestedAt: 0 };
    }
    assert.equal(env.run(false), {
      draft: 'draft-exists', captcha: 'verification-required', error: 'signup-error',
      phone: 'waiting-result', cancelled: 'cancelled',
    }[issue]);
    assert.equal(env.requests.length, 0);
    assert.equal(env.submit.clicks, 0);
  }
});

test('post-OTP password stays focused until an acknowledged native paste reaches the DOM', async () => {
  const env = setup({ autoPaste: false });
  env.email.hidden = true;
  env.config.otpRequestedAt = 0;
  env.config.allowOtpSubmit = false;
  env.config.useAccessibilityPasswordSubmit = true;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(350);
  assert.equal(env.run(false), 'waiting-next');
  await env.resolvePaste(); // Android accepted the command; input has not arrived.
  assert.equal(env.password.value, '');
  assert.equal(env.document.activeElement, env.password);
  env.advance(1000);
  assert.equal(env.run(false), 'waiting-next');
  assert.equal(env.document.activeElement, env.password);
  assert.equal(env.requests.length, 1);
  // Chromium delivers the input asynchronously after the native acknowledgement.
  env.password.value = env.config.password;
  assert.equal(env.run(false), 'waiting-password-submit');
  assert.equal(env.document.activeElement, null);
  assert.equal(env.submit.clicks, 0);
  env.advance(350);
  env.window.flutter_inappwebview.callHandler = (...args) => {
    env.requests.push(args);
    return Promise.resolve(true);
  };
  assert.equal(env.run(false), 'password-submitted');
  assert.deepEqual(env.requests, [
    ['FlutterSignupPaste', 1, 'password'], ['FlutterSignupPasswordSubmit', 1],
  ]);
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

test('native paste authorization is revoked on focus change, navigation, or cancellation', async () => {
  const env = setup();
  env.run();
  const state = env.window.__flutterAutoSignup;
  env.document.activeElement = env.password;
  assert.equal(state.canPasteFromClipboard(), false);
  env.document.activeElement = env.email;
  env.location.pathname = '/login';
  assert.equal(state.canPasteFromClipboard(), false);
  env.location.pathname = '/signup';
  state.stop();
  assert.equal(state.canPasteFromClipboard(), false);
  await env.resolvePaste();
  assert.equal(env.run(), 'cancelled');
  assert.equal(env.submit.clicks, 0);
});

test('hands CAPTCHA to the user before pasting', () => {
  const env = setup();
  env.add('#captcha-verify-container');
  assert.equal(env.run(), 'verification-required');
  assert.equal(env.requests.length, 0);
});

test('stops on the actual inline existing-email warning instead of requesting verification', async () => {
  const env = setup();
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  env.add('div', "You've already signed up, Log in");
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  assert.equal(env.run(), 'email-registered');
  assert.equal(env.requests.length, 1);
  assert.equal(sendCode.clicks, 0);
  assert.equal(env.submit.clicks, 0);
});

test('ignores a hidden existing-email warning', async () => {
  const env = setup();
  env.add('div', "You've already signed up, Log in").hidden = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
});

test('fills credentials before requesting an initially empty verification code, once', async () => {
  const env = setup();
  env.add('input[name="code"]', '', 'INPUT');
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'waiting-result');
  assert.equal(sendCode.clicks, 1);
  assert.equal(env.submit.clicks, 0);
});

test('waits for submit to be enabled and never repeats a submitted form after navigation', async () => {
  const env = setup();
  env.submit.disabled = true;
  await fill(env);
  assert.equal(env.run(), 'waiting-next');
  env.submit.disabled = false;
  assert.equal(env.run(), 'submitted');
  delete env.window.__flutterAutoSignup;
  env.email.value = '';
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.requests.length, 2);
  assert.equal(env.submit.clicks, 1);
});

test('sets birthday using option labels rather than assuming month values are one-based', () => {
  const env = setup({ inputs: false });
  const month = new env.Select([{ textContent: 'February', value: '1' }]);
  const day = new env.Select([{ textContent: '3', value: '3' }]);
  const year = new env.Select([{ textContent: '2001', value: '2001' }]);
  const next = env.add('button', 'Next', 'BUTTON');
  for (const status of ['waiting-form', 'waiting-form', 'waiting-next', 'next-submitted', 'waiting-next']) {
    assert.equal(env.run(), status);
  }
  assert.equal(month.value, '1');
  assert.equal(day.value, '3');
  assert.equal(year.value, '2001');
  assert.deepEqual(month.events, ['input', 'change']);
  assert.equal(next.clicks, 1);
  assert.equal(env.requests.length, 0);
});

test('completes birthday on a combined email signup form before pasting credentials', async () => {
  const env = setup();
  const month = new env.Select([{ textContent: 'February', value: '1' }]);
  const day = new env.Select([{ textContent: '3', value: '3' }]);
  const year = new env.Select([{ textContent: '2001', value: '2001' }]);
  const language = new env.Select([{ textContent: 'English (UK)', value: 'en-GB' }]);
  const birthdayRoot = env.add('[class*="DivAgeSelector"]');
  birthdayRoot.querySelectorAll = () => [month, day, year];
  env.add('input[name="code"]', '', 'INPUT');
  const sendCode = env.add('button', 'Send code', 'BUTTON');
  for (let i = 0; i < 3; i++) {
    assert.equal(env.run(), i === 2 ? 'waiting-next' : 'waiting-form');
    assert.equal(env.requests.length, 0);
  }
  assert.equal(month.value, '1');
  assert.equal(day.value, '3');
  assert.equal(year.value, '2001');
  assert.equal(language.value, '');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(sendCode.clicks, 1);
  assert.equal(env.submit.clicks, 0);
});

test('chooses options inside each actual-style birthday combobox and pastes on the email form', async () => {
  const env = setup();
  const birthdayRoot = env.add('[class*="DivAgeSelector"]');
  const fields = ['Month', 'Day', 'Year'].map(label => env.add('[role="combobox"]', label));
  birthdayRoot.querySelectorAll = () => fields;
  new env.Select([{ textContent: 'English (UK)', value: 'en-GB' }]);
  for (const [index, expected] of ['February', '3', '2001'].entries()) {
    const field = fields[index];
    const option = env.add('[role="option"]', expected);
    option.hidden = true;
    field.querySelectorAll = () => [option];
    // The real combobox root only has onKeyDown; its child label has onClick.
    const label = env.add('[class*="DivSelectLabel"]', field.textContent);
    field.querySelector = selector => selector === '[class*="DivSelectLabel"]' ? label : null;
    label.click = () => { label.clicks++; option.hidden = false; };
    option.click = () => { option.clicks++; field.textContent = expected; option.hidden = true; };
  }
  for (let i = 0; i < 6; i++) {
    assert.equal(env.run(), i === 5 ? 'waiting-next' : 'waiting-form');
    assert.equal(env.requests.length, 0);
  }
  assert.deepEqual(fields.map(field => field.textContent), ['February', '3', '2001']);
  assert.deepEqual(fields.map(field => field.clicks), [0, 0, 0]);
  await fill(env);
  assert.equal(env.run(), 'submitted');
});

test('does not toggle a birthday menu repeatedly when the requested option is missing', () => {
  const env = setup();
  const root = env.add('[class*="DivAgeSelector"]');
  const fields = ['Month', 'Day', 'Year'].map(label => env.add('[role="combobox"]', label));
  root.querySelectorAll = () => fields;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(fields[0].clicks, 1);
  env.advance(3001);
  assert.equal(env.run(), 'birthday-required');
  assert.equal(env.requests.length, 0);
});

test('reports an error and requires a visible profile to report success', () => {
  const env = setup();
  env.add('[data-e2e="signup-error"]', 'Account already exists');
  assert.equal(env.run(), 'signup-error');
  assert.equal(env.requests.length, 0);
  const profile = env.add('[data-e2e="profile-icon"]');
  profile.hidden = true;
  assert.equal(env.run(false), 'signup-error');
  profile.hidden = false;
  assert.equal(env.run(), 'already-logged-in');
  assert.equal(env.run(false), 'signup-success');
});


test('pastes a ready OTP immediately after requesting a code and submits once', async () => {
  const env = setup();
  env.config.otp = '012345';
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(otp.value, '');
  assert.equal(env.requests.length, 3);
  assert.equal(env.run(), 'waiting-otp-paste');
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.canPasteFromClipboard(1, 'otp', env.config.otp), true);
  assert.equal(state.canPasteFromClipboard(1, 'email', env.config.otp), false);
  assert.equal(send.clicks, 1);
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  env.submit.disabled = true;
  assert.equal(env.run(), 'waiting-next');
  env.submit.disabled = false;
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
  assert.deepEqual(env.requests[2], ['FlutterSignupPaste', 1, 'otp']);
  assert.equal(env.requests.length, 3);
  assert.equal(send.clicks, 1);
});

test('continues on an OTP-only page after navigation without requesting again', async () => {
  const env = setup();
  env.config.otp = '123456';
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  env.config.otpRequestedAt = 0;
  delete env.window.__flutterAutoSignup;
  env.email.hidden = true;
  env.password.hidden = true;
  const otp = env.add('input[autocomplete="one-time-code"]', '', 'INPUT');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(), true);
  await env.resolvePaste();
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(otp.value, env.config.otp);
  assert.equal(send.clicks, 1);
  env.config.allowOtpSubmit = false;
  delete env.window.__flutterAutoSignup;
  otp.value = '';
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 1);
});

test('does not paste OTP while hidden or after cancellation', async () => {
  const env = setup();
  env.config.otp = '123456';
  env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  env.add('input[name="code"]', '', 'INPUT');
  env.document.hidden = true;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 2);
  env.document.hidden = false;
  assert.equal(env.run(), 'waiting-otp-paste');
  const state = env.window.__flutterAutoSignup;
  state.stop();
  assert.equal(state.canPasteFromClipboard(), false);
  assert.equal(env.run(), 'cancelled');
  assert.equal(env.submit.clicks, 0);
});


test('fills credentials before waiting for Send code to become enabled', async () => {
  const env = setup();
  env.config.otp = '123456';
  const otp = env.add('input[name="code"]', '', 'INPUT');
  const send = env.add('button', 'Send code', 'BUTTON');
  send.disabled = true;
  await fill(env);
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
  env.advance(10000);
  send.disabled = false;
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(otp.value, '');
  assert.equal(env.requests.length, 3);
});

test('supports a delayed OTP challenge after initial signup submission', async () => {
  const env = setup();
  env.config.otp = '123456';
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(false), 'waiting-otp-paste');
  assert.equal(env.run(false), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, env.config.otp);
  env.submit.disabled = true;
  assert.equal(env.run(false), 'waiting-next');
  assert.equal(env.run(false), 'waiting-next');
  env.submit.disabled = false;
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'submitted');
  assert.equal(env.submit.clicks, 2);
});

test('waits for an API OTP after Send code without requesting another code', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.run(), 'otp-required');
  env.advance(180000);
  assert.equal(env.run(), 'otp-required');
  assert.equal(send.clicks, 1);
  assert.equal(env.requests.length, 2);
  env.config.otp = '012345';
  assert.equal(env.run(), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  assert.equal(env.run(), 'otp-submitted');
});

test('commits an email-only form and activates Send code with a single click event', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  env.password.hidden = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  const originalClick = send.click;
  send.click = function() {
    assert.notEqual(env.document.activeElement, env.email);
    assert.equal(env.email.value, env.config.email);
    assert.deepEqual(this.events, []);
    originalClick.call(this);
  };
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.document.activeElement, null);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.requests.length, 1);
  assert.equal(env.run(), 'otp-required');
  assert.equal(send.clicks, 1);
  assert.deepEqual(send.events, ['click']);
});

test('does not activate both pointer handlers and click handlers for Send code', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  let activations = 0;
  send.dispatchEvent = function(event) {
    this.events.push(event.type);
    if (event.type === 'mousedown' || event.type === 'pointerdown') activations++;
  };
  const originalClick = send.click;
  send.click = function() { activations++; originalClick.call(this); };
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  for (let i = 0; i < 4; i++) { env.advance(300); env.run(); }
  assert.equal(activations, 1);
  assert.deepEqual(send.events, ['click']);
});

test('does not click a replacement Send code button while waiting for acknowledgement', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const first = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  first.hidden = true;
  const replacement = env.add('button', 'Send code', 'BUTTON');
  env.advance(300);
  assert.equal(env.run(), 'requesting-verification');
  env.advance(15000);
  assert.equal(env.run(), 'verification-request-failed');
  assert.equal(first.clicks, 1);
  assert.equal(replacement.clicks, 0);
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
});

test('signup does not reopen Account when React replaces its button', () => {
  const env = setup({ inputs: false });
  env.location.pathname = '/';
  const account = env.add('[data-e2e="nav-profile"]', 'Account');
  assert.equal(env.run(), 'waiting-form');
  account.hidden = true;
  const replacement = env.add('[data-e2e="nav-profile"]', 'Account');
  assert.equal(env.run(), 'waiting-form');
  assert.equal(account.clicks, 1);
  assert.equal(replacement.clicks, 0);
});

test('signup does not resubmit a password after React replaces the submit button', async () => {
  const env = setup();
  env.config.otpRequestedAt = 0;
  env.email.hidden = true;
  assert.equal(env.run(false), 'waiting-password-screen');
  env.advance(2500);
  assert.equal(env.run(false), 'waiting-next');
  await env.resolvePaste();
  assert.equal(env.run(false), 'waiting-password-submit');
  env.advance(3000);
  assert.equal(env.run(false), 'password-submitted');
  env.submit.hidden = true;
  const replacement = env.add('button', 'Sign up', 'BUTTON');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 1);
  assert.equal(replacement.clicks, 0);
});

test('does not claim OTP was requested or retry a Send code click without TikTok feedback', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  env.add('input[name="code"]', '', 'INPUT');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
  env.advance(14999);
  assert.equal(env.run(), 'requesting-verification');
  env.advance(1);
  assert.equal(env.run(), 'verification-request-failed');
  assert.equal(send.clicks, 1);
  assert.equal(env.requests.length, 2);
  assert.equal(env.submit.clicks, 0);
});

test('waits through a loading button before accepting a delayed countdown', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.config.waitForOtpApi = true;
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  send.disabled = true;
  env.advance(4000);
  assert.equal(env.run(), 'requesting-verification');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
  send.textContent = 'Resend code (60s)';
  assert.equal(env.run(), 'verification-requested');
  assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, 0);
  assert.equal(env.run(), 'otp-required');
  assert.equal(send.clicks, 1);
});

test('continues an OTP-only dialog with a changed heading after Send code', async () => {
  const env = setup({ sendCodeAcknowledged: false });
  env.location.pathname = '/';
  env.config.waitForOtpApi = true;
  const modal = env.add('[role="dialog"]');
  const title = env.add('h2', 'Sign up');
  modal.querySelectorAll = selector => env.document.querySelectorAll(selector);
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'requesting-verification');
  env.email.hidden = env.password.hidden = send.hidden = true;
  title.textContent = 'Enter 6-digit code';
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(), 'verification-requested');
  env.config.otp = '012345';
  assert.equal(env.run(), 'waiting-otp-paste');
  assert.equal(env.window.__flutterAutoSignup.canPasteFromClipboard(), true);
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(send.clicks, 1);
});

test('still reports CAPTCHA and inline errors while waiting for Send code feedback', async () => {
  for (const error of ['captcha', 'email']) {
    const env = setup({ sendCodeAcknowledged: false });
    env.config.waitForOtpApi = true;
    const send = env.add('button', 'Send code', 'BUTTON');
    await fill(env);
    assert.equal(env.run(), 'requesting-verification');
    if (error === 'captcha') env.add('#captcha-verify-container');
    else env.add('div', "You've already signed up, Log in");
    assert.equal(env.run(), error === 'captcha' ? 'verification-required' : 'email-registered');
    assert.equal(env.window.__flutterAutoSignup.otpRequestedAt, null);
    assert.equal(send.clicks, 1);
  }
});

test('reports an API OTP challenge after initial signup submission', async () => {
  const env = setup();
  env.config.waitForOtpApi = true;
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(false), 'otp-required');
  env.config.otp = '012345';
  assert.equal(env.run(false), 'waiting-otp-paste');
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  assert.equal(env.run(false), 'otp-submitted');
});
