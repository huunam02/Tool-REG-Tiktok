// Run with: node --test test/auto_signup_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/auto_signup_script.dart', `file://${__filename}`), 'utf8',
);
const step = source.match(/autoSignupStepScript = r'''([\s\S]*?)''';/)[1];
const flush = () => new Promise(setImmediate);

function setup({ inputs = true, autoPaste = true, pasteResult = true } = {}) {
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
  const config = { email: 'test@example.com', password: 'test-password', month: 2, day: 3, year: 2001, attempt: 1 };
  let time = 0;
  function add(selector, textContent = '', tagName = 'DIV') {
    const element = {
      selector, textContent, tagName, value: '', disabled: false, readOnly: false,
      isConnected: true, hidden: false, clicks: 0,
      width: 100, height: 32,
      getClientRects() { return this.hidden ? [] : [{ width: this.width, height: this.height }]; },
      getAttribute() { return null; },
      focus() { document.activeElement = this; }, select() {},
      click() { this.clicks++; }, dispatchEvent() {},
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
    Event: class { constructor(type) { this.type = type; } },
    Date: class extends Date { static now() { return time; } },
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
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
}

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
  assert.equal(env.run(), 'waiting-paste');
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
  assert.equal(env.run(), 'waiting-form');
  env.email.hidden = true;
  env.password.hidden = false;
  assert.equal(env.run(), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(env.requests.length, 2);
  assert.equal(env.password.value, env.config.password);
  assert.equal(env.run(), 'submitted');
  assert.equal(env.submit.clicks, 1);
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
  assert.equal(env.run(), 'waiting-form');
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
  for (let i = 0; i < 5; i++) assert.equal(env.run(), 'waiting-form');
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
    assert.equal(env.run(), 'waiting-form');
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
    assert.equal(env.run(), 'waiting-form');
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


test('waits five seconds after requesting a code, pastes OTP and submits once', async () => {
  const env = setup();
  env.config.otp = '012345';
  const send = env.add('button', 'Send code', 'BUTTON');
  await fill(env);
  assert.equal(env.run(), 'verification-requested');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  env.advance(4999);
  assert.equal(env.run(), 'waiting-otp');
  assert.equal(otp.value, '');
  assert.equal(env.requests.length, 2);
  env.advance(1);
  assert.equal(env.run(), 'waiting-paste');
  const state = env.window.__flutterAutoSignup;
  assert.equal(state.canPasteFromClipboard(1, 'otp', env.config.otp), true);
  assert.equal(state.canPasteFromClipboard(1, 'email', env.config.otp), false);
  assert.equal(send.clicks, 1);
  await env.resolvePaste();
  assert.equal(otp.value, '012345');
  env.submit.disabled = true;
  assert.equal(env.run(), 'waiting-form');
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
  env.advance(3000);
  assert.equal(env.run(), 'waiting-otp');
  env.advance(2000);
  assert.equal(env.run(), 'waiting-paste');
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
  env.advance(5000);
  env.document.hidden = true;
  assert.equal(env.run(), 'waiting-form');
  assert.equal(env.requests.length, 2);
  env.document.hidden = false;
  assert.equal(env.run(), 'waiting-paste');
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
  assert.equal(env.run(), 'waiting-otp');
  assert.equal(otp.value, '');
  assert.equal(env.requests.length, 2);
});

test('supports a delayed OTP challenge after initial signup submission', async () => {
  const env = setup();
  env.config.otp = '123456';
  await fill(env);
  assert.equal(env.run(), 'submitted');
  const otp = env.add('input[name="code"]', '', 'INPUT');
  assert.equal(env.run(false), 'waiting-otp');
  env.advance(5000);
  assert.equal(env.run(false), 'waiting-paste');
  await env.resolvePaste();
  assert.equal(otp.value, env.config.otp);
  env.submit.disabled = true;
  assert.equal(env.run(false), 'waiting-form');
  assert.equal(env.run(false), 'waiting-form');
  env.submit.disabled = false;
  assert.equal(env.run(false), 'otp-submitted');
  assert.equal(env.run(false), 'submitted');
  assert.equal(env.submit.clicks, 2);
});
