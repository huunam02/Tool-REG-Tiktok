// Run with: node --test test/auto_login_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/auto_login_script.dart', `file://${__filename}`), 'utf8',
);
const step = source.match(/autoLoginStepScript = r'''([\s\S]*?)''';/)[1];

function setup() {
  const elements = [];
  const window = {};
  const location = {
    origin: 'https://www.tiktok.com', pathname: '/login/phone-or-email/email',
  };
  class Input {
    constructor(selector) {
      this.selector = selector;
      this._value = '';
      this.events = [];
      this.hidden = false;
      this.parentElement = null;
      elements.push(this);
    }
    get value() { return this._value; }
    set value(value) { this._value = value; }
    getClientRects() { return this.hidden ? [] : [{}]; }
    dispatchEvent(event) { this.events.push(event.type); }
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
  const document = {
    querySelectorAll: (selector) => elements.filter(
      (element) => selector.split(', ').includes(element.selector),
    ),
  };
  const context = {
    window, location, document, HTMLInputElement: Input,
    Event: class { constructor(type) { this.type = type; } },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
  };
  const execute = runInNewContext(`(${step})`, context);
  return {
    window, location, email, password, submit,
    run: (allowSubmit = true, attempt = 1) => execute({
      email: 'test@example.com', password: 'test-password', attempt,
    }, allowSubmit),
    add: (selector, textContent = '') => elements.push({
      selector, textContent, getClientRects: () => [{}],
    }),
  };
}

test('fills React inputs and submits once even if result delivery is interrupted', () => {
  const env = setup();
  assert.equal(env.run(), 'submitted');
  assert.equal(env.email.value, 'test@example.com');
  assert.equal(env.password.value, 'test-password');
  assert.deepEqual(env.password.events, ['input', 'change']);
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
});

test('waits for a disabled submit button to become enabled', () => {
  const env = setup();
  env.submit.disabled = true;
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
  assert.equal(env.submit.clicks, 0);
});

test('does not enter credentials on another origin or a non-login page', () => {
  for (const origin of ['http://www.tiktok.com', 'https://example.com', 'https://www.tiktok.com.example.com']) {
    const env = setup();
    env.location.origin = origin;
    assert.equal(env.run(), 'wrong-origin');
    assert.equal(env.password.value, '');
    assert.equal(env.submit.clicks, 0);
  }
  const env = setup();
  env.location.pathname = '/';
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.password.value, '');
});

test('hands CAPTCHA and verification codes to the user before filling', () => {
  for (const selector of ['#captcha-verify-container', 'input[autocomplete="one-time-code"]']) {
    const env = setup();
    env.add(selector);
    assert.equal(env.run(), 'verification-required');
    assert.equal(env.password.value, '');
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
