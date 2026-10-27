// Run with: node --test test/rotate_captcha_script_test.js
// Uses a real DOM/CSS engine to verify transformed desktop modal geometry.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync} = require('node:fs');
const {tmpdir} = require('node:os');
const {join} = require('node:path');
const {execFileSync} = require('node:child_process');
const {runInNewContext} = require('node:vm');
const source = readFileSync(join(__dirname, '../lib/core/scripts/rotate_captcha_script.dart'), 'utf8');
const read = source.match(/readRotateCaptchaScript = r'''([\s\S]*?)''';/)[1];
const present = source.match(/rotateCaptchaPresentScript = r'''([\s\S]*?)''';/)[1];
const refresh = source.match(/rotateCaptchaRefreshScript = r'''([\s\S]*?)''';/)[1];
const chrome = [process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
].find(path => path && existsSync(path));
let directory, results;
before(() => {
  if (!chrome) return;
  directory = mkdtempSync(join(tmpdir(), 'tiktok-captcha-dom-'));
  const html = `<!doctype html><html><body><pre id="result"></pre><script>
  (async () => {
    // The production script requires the TikTok origin. All fixture content and
    // images stay local; only replace the origin expression for this DOM test.
    const read = () => ${read.replace("location.origin !== 'https://www.tiktok.com'", 'false')};
    const present = () => ${present.replace("location.origin !== 'https://www.tiktok.com'", 'false')};
    const refresh = () => ${refresh.replace("location.origin !== 'https://www.tiktok.com'", 'false')};
    const image = color => 'data:image/svg+xml;base64,' + btoa(
      '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="240"><circle cx="120" cy="120" r="120" fill="' + color + '"/></svg>');
    const box = document.createElement('section');
    document.body.append(box);
    const results = {};
    const sample = () => ({present: present(), challenge: JSON.parse(read())});
    const load = async html => {
      box.innerHTML = html;
      await Promise.all([...box.querySelectorAll('img')].map(img => img.decode()));
    };
    const legacy = (testIds = false) => '<div class="captcha-disable-scroll" style="position:fixed;left:300px;top:700px;width:360px;height:360px;transform:scale(.35);transform-origin:top left">' +
      '<img ' + (testIds ? 'data-testid="whirl-outer-img"' : 'class="captcha_verify_img_outer"') + ' src="' + image('white') + '">' +
      '<img ' + (testIds ? 'data-testid="whirl-inner-img"' : 'class="captcha_verify_img_inner"') + ' src="' + image('gray') + '" style="position:absolute;left:45px;top:45px;width:150px;height:150px">' +
      '<div class="captcha_verify_slide--slidebar" style="position:absolute;left:20px;top:300px;width:320px;height:36px">' +
      '<div class="secsdk-captcha-drag-icon" style="width:36px;height:36px"></div></div></div>';
    const v2 = '<div class="captcha-verify-container" style="position:fixed;left:300px;top:700px;width:360px;height:360px;transform:scale(.35);transform-origin:top left"><div><div style="position:relative">' +
      '<span>Drag the slider to fit the puzzle</span>' +
      '<div style="position:absolute;left:60px;top:40px;width:240px;height:240px">' +
      '<img src="' + image('white') + '" width="240" height="240">' +
      '<img class="cap-absolute" src="' + image('gray') + '" style="position:absolute;left:45px;top:45px;width:150px;height:150px"></div>' +
      '<div class="cap-w-full" style="position:absolute;left:20px;top:300px;width:320px">' +
      '<div class="cap-rounded-full" style="width:320px;height:36px">' +
      '<div draggable="true" style="width:36px;height:36px;border-radius:50%"></div></div></div>' +
      '<button title="Refresh" style="position:absolute;left:320px;top:340px;width:24px;height:24px" onclick="document.body.dataset.clicked=1">Refresh</button></div></div></div>';
    results.absent = sample();
    await load('<div class="captcha-disable-scroll" style="width:100px;height:100px">Video feed</div>');
    results.scrollLock = sample();
    await load('<div class="captcha-verify-container" style="width:100px;height:100px"></div>');
    results.emptyContainer = sample();
    await load(legacy()); results.legacy = sample();
    await load(legacy(true)); results.v1 = sample();
    await load(v2.replace('transform:scale(.35);', '').replace('top:700px', 'top:820px'));
    results.desktop = sample();
    // Current app: a whole 1920x955 desktop document in a centered phone frame.
    await load(v2.replace('transform:scale(.35);', '').replace('left:300px', 'left:770px').replace('top:700px', 'top:291px'));
    const viewport = window.visualViewport;
    Object.defineProperty(window, 'visualViewport', {configurable:true,
      value:{width:1920, height:955, offsetLeft:0, offsetTop:0}});
    results.currentDesktop = {...sample(), refresh:JSON.parse(refresh())};
    // A panned/zoomed visual viewport uses the same offset in all readers.
    Object.defineProperty(window, 'visualViewport', {configurable:true,
      value:{width:1600, height:800, offsetLeft:100, offsetTop:50}});
    results.offsetDesktop = {...sample(), refresh:JSON.parse(refresh())};
    Object.defineProperty(window, 'visualViewport', {configurable:true, value:viewport});
    await load(v2); results.v2 = sample();
    // A draggable video/player control is not a CAPTCHA handle.
    const unrelated = document.createElement('div'); unrelated.draggable = true;
    document.body.prepend(unrelated); results.unrelated = sample();
    // Hidden stale challenges must not be mixed with the visible modal.
    const stale = document.createElement('section'); stale.style.display = 'none';
    stale.innerHTML = legacy(); document.body.prepend(stale);
    results.stale = sample();
    const modal = box.querySelector('.captcha-verify-container');
    modal.style.left = '1200px'; results.offscreen = sample();
    modal.style.left = '300px';
    box.style.opacity = '0'; results.transparentParent = sample();
    box.style.opacity = '';
    box.style.visibility = 'hidden'; results.hiddenParent = sample();
    box.style.visibility = '';
    box.querySelector('div[draggable]').style.marginLeft = '100px'; results.moved = sample();
    box.querySelector('div[draggable]').style.marginLeft = '';
    box.querySelector('img.cap-absolute').remove(); results.incomplete = sample();
    modal.style.display = 'none'; results.hidden = sample();
    results.clicked = document.body.dataset.clicked || null;
    document.getElementById('result').textContent = JSON.stringify(results);
  })().catch(error => document.getElementById('result').textContent = JSON.stringify({error:String(error)}));
  </script></body></html>`;
  const path = join(directory, 'fixture.html');
  writeFileSync(path, html);
  const output = execFileSync(chrome, [
    '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--disable-extensions',
    '--window-size=1000,2000', '--hide-scrollbars',
    '--user-data-dir=' + join(directory, 'profile'),
    '--timeout=10000', '--dump-dom', 'file://' + path,
  ], {encoding:'utf8', timeout:20000, stdio:['ignore','pipe','pipe']});
  const raw = output.match(/<pre id="result">([^<]*)<\/pre>/)?.[1];
  assert.ok(raw, 'Chrome must return fixture results');
  results = JSON.parse(raw.replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&gt;', '>').replaceAll('&lt;', '<'));
  assert.equal(results.error, undefined);
});
after(() => { if (directory) rmSync(directory, {recursive:true, force:true}); });
const options = {skip: !chrome && 'Set CHROME_BIN to run real DOM geometry checks'};
for (const version of ['legacy', 'v1', 'v2']) {
  test('reads a small, scaled desktop modal: ' + version, options, () => {
    const {present, challenge} = results[version];
    assert.equal(present, true);
    assert.notEqual(challenge.inner, challenge.outer);
    assert.ok(Math.abs(challenge.x - 313.3) < .02);
    assert.ok(Math.abs(challenge.y - 811.3) < .02);
    assert.ok(Math.abs(challenge.travel - 99.4) < .02);
    assert.ok(challenge.viewportWidth >= 980);
  });
}
test('scopes image and handle selection to the visible CAPTCHA', options, () => {
  assert.deepEqual(results.unrelated, results.v2);
  assert.deepEqual(results.stale, results.v2);
  assert.equal(results.clicked, null);
});
test('does not solve an offscreen, moved, incomplete or hidden challenge', options, () => {
  for (const kind of ['moved', 'incomplete']) {
    assert.equal(results[kind].present, true);
    assert.equal(results[kind].challenge, null);
  }
  assert.deepEqual(results.hidden, {present:false, challenge:null});
  assert.deepEqual(results.absent, {present:false, challenge:null});
  for (const kind of ['offscreen', 'scrollLock', 'emptyContainer', 'transparentParent', 'hiddenParent']) {
    assert.deepEqual(results[kind], {present:false, challenge:null}, kind);
  }
});

test('hidden or unrelated documents report unknown CAPTCHA presence', () => {
  for (const [origin, hidden] of [
    ['https://www.tiktok.com', true], ['https://example.com', false],
  ]) {
    assert.equal(runInNewContext(present, {location: {origin}, document: {hidden}}), null);
  }
});

test('reads a desktop CSS viewport before WebView scales it to phone size', options, () => {
  const c = results.desktop.challenge;
  assert.equal(results.desktop.present, true);
  assert.ok(Math.abs(c.x - 338) < .02);
  assert.ok(Math.abs(c.y - 1138) < .02);
  assert.ok(Math.abs(c.travel - 284) < .02);
});

test('reads rotation and refresh geometry in the current 1920x955 desktop frame', options, () => {
  const {present, challenge, refresh} = results.currentDesktop;
  assert.equal(present, true);
  assert.equal(challenge.viewportWidth, 1920);
  assert.equal(challenge.viewportHeight, 955);
  assert.equal(challenge.x, 808);
  assert.equal(challenge.y, 609);
  assert.equal(challenge.travel, 284);
  assert.deepEqual(refresh, {viewportWidth:1920, viewportHeight:955, x:1102, y:643});
  assert.equal(results.clicked, null);
});

test('subtracts visual viewport offsets for both the slider and refresh', options, () => {
  const {challenge, refresh} = results.offsetDesktop;
  assert.equal(challenge.x, 708);
  assert.equal(challenge.y, 559);
  assert.equal(challenge.travel, 284);
  assert.deepEqual(refresh, {viewportWidth:1600, viewportHeight:800, x:1002, y:593});
});
