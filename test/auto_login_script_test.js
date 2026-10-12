// Run with: node --test test/auto_login_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/auto_login_script.dart', `file://${__filename}`), 'utf8',
);
const step = source.match(/autoLoginStepScript = r'''([\s\S]*?)''';/)[1];
const flush = () => new Promise(setImmediate);

function setup({ autoPaste = true, pasteResult = true } = {}) {
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
      (element) => selector.split(', ').includes(element.selector),
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
    select() {}
    dispatchEvent() { assert.fail('Input must be entered using native paste'); }
    closest() { return null; }
  }
  const email = new Input('input[name="username"]');
  const password = new Input('input[type="password"]');
  const submit = {
    selector: 'button', textContent: 'Log in', disabled: false, clicks: 0,
    getClientRects: () => [{}],
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
      const element = { selector, textContent, disabled: false, clicks: 0,
        getClientRects: () => [{}], getAttribute: () => null,
        click() { this.clicks++; },
      };
      elements.push(element);
      return element;
    },
  };
}

async function fill(env) {
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
}

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
  assert.equal(env.run(), 'waiting-paste');
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
  assert.equal(env.run(), 'waiting-submit');
  assert.equal(env.submit.clicks, 0);
  env.submit.disabled = false;
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
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

test('requests a code once and pastes OTP only after five seconds', async () => {
  const env = setup();
  env.config.otp = '012345';
  const otp = new env.Input('input[name="code"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  assert.equal(send.clicks, 1);
  assert.equal(otp.value, '');
  env.advance(4999);
  assert.equal(env.run(), 'waiting-otp');
  assert.equal(env.requests.length, 2);
  env.advance(1);
  assert.equal(env.run(), 'waiting-paste');
  assert.equal(env.window.__flutterAutoLogin.canPasteFromClipboard(1, 'otp', env.config.otp), true);
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  env.submit.disabled = true;
  assert.equal(env.run(), 'waiting-submit');
  env.submit.disabled = false;
  assert.equal(env.run(), 'otp-submitted');
  assert.equal(env.run(), 'waiting-result');
  assert.deepEqual(env.requests[2], ['FlutterLoginPaste', 1, 'otp']);
  assert.equal(env.submit.clicks, 1);
  assert.equal(send.clicks, 1);
});

test('pastes an OTP challenge after password submission', async () => {
  const env = setup();
  env.config.otp = '123456';
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = new env.Input('input[autocomplete="one-time-code"]');
  assert.equal(env.run(false), 'waiting-otp');
  env.advance(5000);
  assert.equal(env.run(false), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(otp.value, env.config.otp);
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'waiting-result');
  assert.equal(env.submit.clicks, 2); // Password, then OTP.
});

test('preserves the request delay and submission latch across page replacement', async () => {
  const env = setup();
  env.config.otp = '654321';
  const otp = new env.Input('input[name="otp"]');
  const send = env.add('button', 'Send code');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  env.config.otpRequestedAt = 0;
  env.advance(3000);
  delete env.window.__flutterAutoLogin;
  assert.equal(env.run(), 'waiting-otp');
  env.advance(2000);
  assert.equal(env.run(), 'waiting-paste');
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
  assert.equal(env.run(), 'waiting-otp');
  env.advance(5000);
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
  assert.equal(env.run(), 'waiting-otp');
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
  assert.equal(env.run(), 'waiting-paste');
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
  env.advance(5000);
  env.config.otp = '012345';
  assert.equal(env.run(false), 'waiting-paste');
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
