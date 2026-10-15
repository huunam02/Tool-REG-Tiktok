const assert = require('node:assert/strict');
const { test } = require('node:test');

module.exports = function registerHomeModalTests(flow, setup) {
  function home() {
    const env = setup({ inputs: false });
    env.location.pathname = '/';
    if (env.email) env.email.hidden = true;
    if (env.password) env.password.hidden = true;
    env.submit.hidden = true;
    const video = env.add('video', '', 'VIDEO');
    Object.assign(video, {
      currentTime: 8.1, duration: 10, paused: false, ended: false,
      getBoundingClientRect: () => ({left: 0, top: 0, right: 400, bottom: 800}),
    });
    const like = env.add('button', 'Like', 'BUTTON');
    const article = { querySelectorAll: () => [like] };
    video.closest = () => article;
    const account = env.add('[data-e2e="nav-profile"]', 'Account');
    const modal = env.add('[role="dialog"]');
    const title = env.add('h2', 'Log in to TikTok');
    modal.hidden = title.hidden = true;
    modal.querySelectorAll = selector => selector.includes('h2') ? [title] : [];
    const showModal = () => { modal.hidden = title.hidden = false; };
    return {env, video, like, account, modal, showModal};
  }

  test(`${flow}: retries an ignored Like only after waiting for the modal`, () => {
    const {env, like, showModal} = home();
    assert.equal(env.run(), 'home-video-liked');
    env.advance(14999);
    assert.equal(env.run(), 'waiting-login-modal');
    assert.equal(like.clicks, 1);
    env.advance(1);
    assert.equal(env.run(), 'home-video-liked');
    assert.equal(like.clicks, 2);
    showModal();
    env.advance(30000);
    assert.equal(env.run(), 'waiting-form');
    assert.equal(like.clicks, 2);
    assert.equal(env.requests.length, 0);
  });

  test(`${flow}: a delayed modal prevents any further Home click`, () => {
    const {env, like, account, showModal} = home();
    env.run();
    env.advance(14000);
    showModal();
    env.run();
    env.advance(30000);
    env.run();
    assert.equal(like.clicks, 1);
    assert.equal(account.clicks, 0);
  });

  test(`${flow}: falls back to Account and stops after bounded retries`, () => {
    const {env, like, account} = home();
    for (let i = 0; i < 3; i++) {
      assert.equal(env.run(), 'home-video-liked');
      env.advance(15000);
    }
    for (let i = 0; i < 3; i++) {
      assert.equal(env.run(), 'waiting-form');
      assert.equal(account.clicks, i + 1);
      env.advance(14999);
      assert.equal(env.run(), 'waiting-form');
      assert.equal(account.clicks, i + 1);
      env.advance(1);
    }
    assert.equal(env.run(), 'home-modal-failed');
    env.advance(60000);
    assert.equal(env.run(), 'home-modal-failed');
    assert.equal(like.clicks, 3);
    assert.equal(account.clicks, 3);
    assert.equal(env.requests.length, 0);
  });

  test(`${flow}: does not undo an acknowledged Like when the modal is missing`, () => {
    const {env, like, account} = home();
    env.run();
    like.getAttribute = name => name === 'aria-pressed' ? 'true' : null;
    env.advance(15000);
    env.run();
    assert.equal(like.clicks, 1);
    assert.equal(account.clicks, 1);
  });

  test(`${flow}: ignores disabled, covered and Unlike controls`, () => {
    for (const blocked of ['disabled', 'covered', 'unlike']) {
      const {env, like} = home();
      if (blocked === 'disabled') like.disabled = true;
      if (blocked === 'unlike') like.textContent = 'Unlike';
      if (blocked === 'covered') {
        like.getBoundingClientRect = () => ({left: 10, top: 10, width: 40, height: 40});
        env.document.elementFromPoint = () => ({});
      }
      env.run();
      env.advance(20000);
      env.run();
      assert.equal(like.clicks, 0, blocked);
    }
  });

  test(`${flow}: waits for a Like control rendered late by a slow feed`, () => {
    const {env, like, account} = home();
    like.hidden = true;
    assert.equal(env.run(), 'waiting-home-like');
    env.advance(12000);
    like.hidden = false;
    assert.equal(env.run(), 'home-video-liked');
    assert.equal(like.clicks, 1);
    assert.equal(account.clicks, 0);
  });

  test(`${flow}: clicks the button when only its inner icon identifies Like`, () => {
    const {env, video, like} = home();
    like.textContent = '123';
    const icon = env.add('[data-e2e*="like" i]');
    icon.getAttribute = name => name === 'data-e2e' ? 'browse-like-icon' : null;
    icon.closest = () => like;
    video.closest = () => ({querySelectorAll: () => [like, icon]});
    assert.equal(env.run(), 'home-video-liked');
    assert.equal(like.clicks, 1);
    assert.equal(icon.clicks, 0);
  });

  test(`${flow}: replacing the active video does not reset the modal timer`, () => {
    const {env, video, like, account} = home();
    env.run();
    video.hidden = true;
    env.advance(14999);
    assert.equal(env.run(), 'waiting-login-modal');
    assert.equal(account.clicks, 0);
    env.advance(1);
    env.run();
    assert.equal(account.clicks, 1);
    assert.equal(like.clicks, 1);
  });

  test(`${flow}: a fresh attempt resets Home retries`, () => {
    const {env, like} = home();
    env.run();
    env.window[flow === 'login' ? '__flutterAutoLogin' : '__flutterAutoSignup'].stop();
    env.config.attempt = 2;
    assert.equal(env.run(true, 2), 'home-video-liked');
    assert.equal(like.clicks, 2);
  });

  test(`${flow}: hidden, cancelled, navigated or CAPTCHA pages prevent retries`, () => {
    for (const blocked of ['hidden', 'cancelled', 'origin', 'captcha']) {
      const {env, like, account} = home();
      env.run();
      env.advance(15000);
      if (blocked === 'hidden') env.document.hidden = true;
      if (blocked === 'cancelled') env.window[flow === 'login' ? '__flutterAutoLogin' : '__flutterAutoSignup'].stop();
      if (blocked === 'origin') env.location.origin = 'https://example.com';
      if (blocked === 'captcha') env.add('#captcha-verify-container');
      assert.notEqual(env.run(), 'home-video-liked', blocked);
      assert.equal(like.clicks, 1, blocked);
      assert.equal(account.clicks, 0, blocked);
    }
  });
};
