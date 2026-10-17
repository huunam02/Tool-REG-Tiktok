const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {test} = require('node:test');
const {runInNewContext} = require('node:vm');

const source = readFileSync('lib/core/scripts/auto_logout_script.dart', 'utf8');
const step = source.match(/autoLogoutStepScript = r'''([\s\S]*?)''';/)[1];

function setup() {
  const elements = [];
  let now = 0;
  let signedIn = true;
  const location = {origin: 'https://www.tiktok.com', pathname: '/'};
  const matches = (el, selector) => selector.split(/,\s*/).some(s =>
    s === el.selector || (s === 'button' && el.tagName === 'BUTTON'));
  const document = {hidden: false, querySelectorAll: s => elements.filter(el => matches(el, s))};
  const window = {};
  const execute = runInNewContext(`(${step})`, {
    document, location, window,
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
    MouseEvent: class { constructor(type) { this.type = type; } },
    Date: class extends Date { static now() { return now; } },
  });
  const add = (selector, text = '', tagName = 'BUTTON') => {
    const el = {selector, textContent: text, tagName, hidden: false, disabled: false,
      clicks: 0, events: [], getAttribute: () => null,
      getClientRects() { return this.hidden ? [] : [{}]; },
      querySelectorAll: () => [], closest: () => null,
      click() { this.clicks++; this.onClick?.(); },
      dispatchEvent(event) { this.events.push(event.type); },
    };
    elements.push(el);
    return el;
  };
  return {add, window, document, location,
    run: () => execute(1, () => signedIn),
    signOut: () => { signedIn = false; },
    advance: ms => { now += ms; },
  };
}

for (const vietnamese of [false, true]) {
  test(`opens menu, logs out and confirms once (${vietnamese ? 'vi' : 'en'})`, () => {
    const env = setup();
    const menu = env.add('[data-e2e="nav-more"]', 'More');
    assert.equal(env.run(), 'opening-menu');
    assert.equal(menu.clicks, 1);
    assert.deepEqual(menu.events, ['mouseover', 'mouseenter', 'mousemove']);
    assert.equal(env.run(), 'waiting-menu');
    const logout = env.add('button', vietnamese ? 'Đăng xuất' : 'Log out');
    assert.equal(env.run(), 'logout-requested');
    assert.equal(logout.clicks, 1);
    assert.equal(env.run(), 'waiting-logout');
    const confirm = env.add('button', vietnamese ? 'Đăng xuất' : 'Log out');
    const dialog = env.add('[role="dialog"]');
    dialog.querySelectorAll = () => [confirm];
    assert.equal(env.run(), 'confirming-logout');
    assert.equal(confirm.clicks, 1);
    assert.equal(env.run(), 'waiting-logout');
    assert.equal(logout.clicks, 1);
    assert.equal(confirm.clicks, 1);
    env.add('[data-e2e="nav-login-button"]', 'Log in');
    env.signOut();
    assert.equal(env.run(), 'logged-out');
  });
}

test('current top bar: id-only Log in button confirms logout, not the hidden legacy one', () => {
  const env = setup();
  env.signOut();
  env.add('[data-e2e="top-login-button"]', 'Log in').hidden = true;
  const menu = env.add('[data-e2e="nav-more-menu"]', 'More');
  env.add('#top-right-action-bar-login-button', 'Log in');
  assert.equal(env.run(), 'logged-out');
  assert.equal(menu.clicks, 0); // Never reopens the menu after logging out.
});

test('a visible "Log in" button counts, but not one inside the login dialog', () => {
  const env = setup();
  env.signOut();
  const inDialog = env.add('button', 'Log in');
  inDialog.closest = () => ({});
  env.add('[data-e2e="nav-more"]', 'More');
  assert.equal(env.run(), 'opening-menu');
  env.add('button', 'Đăng nhập');
  assert.equal(env.run(), 'logged-out');
});

test('requires positive logged-out UI and ignores hidden controls', () => {
  const env = setup();
  env.signOut();
  const login = env.add('[data-e2e="top-login-button"]', 'Log in');
  login.hidden = true;
  const logout = env.add('button', 'Log out');
  logout.hidden = true;
  assert.equal(env.run(), 'waiting-menu');
  assert.equal(logout.clicks, 0);
  login.hidden = false;
  assert.equal(env.run(), 'logged-out');
});

test('does not act off-origin, in background or while CAPTCHA is visible', () => {
  const env = setup();
  const logout = env.add('button', 'Log out');
  env.location.origin = 'https://example.com';
  assert.equal(env.run(), 'wrong-origin');
  env.location.origin = 'https://www.tiktok.com';
  env.document.hidden = true;
  assert.equal(env.run(), 'paused');
  env.document.hidden = false;
  env.add('#captcha-verify-container');
  assert.equal(env.run(), 'verification-required');
  assert.equal(logout.clicks, 0);
});

test('tries an avatar menu if the More menu has no logout item', () => {
  const env = setup();
  const more = env.add('[data-e2e="nav-more"]', 'More');
  const avatar = env.add('[data-e2e="top-avatar"]');
  assert.equal(env.run(), 'opening-menu');
  env.advance(2000);
  assert.equal(env.run(), 'opening-menu');
  assert.equal(more.clicks, 1);
  assert.equal(avatar.clicks, 1);
  env.advance(2000);
  assert.equal(env.run(), 'waiting-menu');
  assert.equal(more.clicks, 1);
});

test('current collapsed desktop navigation opens nav-more-menu and logout-entrance', () => {
  const env = setup();
  const videoMenu = env.add('[data-e2e="more-menu-icon"]');
  const more = env.add('[data-e2e="nav-more-menu"]');
  assert.equal(env.run(), 'opening-menu');
  assert.equal(more.clicks, 1);
  assert.equal(videoMenu.clicks, 0);
  const logout = env.add('[data-e2e="logout-entrance"]', 'Log out');
  assert.equal(env.run(), 'logout-requested');
  assert.equal(logout.clicks, 1);
});

test('does not send a second logout confirmation when the dialog rerenders', () => {
  const env = setup();
  const dialog = env.add('[role="dialog"]');
  let confirm = env.add('button', 'Log out');
  dialog.querySelectorAll = () => [confirm];
  assert.equal(env.run(), 'confirming-logout');
  confirm = env.add('button', 'Log out');
  assert.equal(env.run(), 'waiting-logout');
  assert.equal(confirm.clicks, 0);
});
