// Run with: node --test test/auto_watch_script_test.js
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(
  new URL('../lib/core/scripts/auto_watch_script.dart', `file://${__filename}`), 'utf8',
);
const start = source.match(/autoWatchStartScript = r'''([\s\S]*?)''';/)[1];
const stop = source.match(/autoWatchStopScript = r'''([\s\S]*?)''';/)[1];

function setup() {
  const intervals = new Set();
  const videos = [];
  const scrolls = [];
  const buttons = [];
  const cards = [];
  const dialogs = [];
  const messages = [];
  const editors = [];
  const responses = [];
  let focusedEditor;
  let randomValue = 0;
  let pasteBehavior = text => { focusedEditor.textContent = text; return true; };
  const fetch = () => new Promise((resolve) => responses.push(resolve));
  let now = 0;
  const document = {
    hidden: false,
    createRange: () => ({ selectNodeContents: () => {} }),
    execCommand: () => assert.fail('Comments must use native clipboard paste'),
    querySelectorAll: (selector) => selector === 'video' ? videos
      : selector.startsWith('article') ? cards
      : selector.startsWith('[role="dialog"]') ? dialogs
      : selector.includes('contenteditable') ? editors : buttons,
    querySelector: (selector) => buttons.find(b =>
      b.getAttribute('data-e2e') === 'feed-navigation-next') || null,
    elementFromPoint: () => videos.find((video) =>
      video.top === 0 && !video.hidden) || null,
  };
  const window = {
    fetch,
    getSelection: () => ({ removeAllRanges: () => {}, addRange: () => {} }),
    scrollBy: (options) => scrolls.push(options),
    flutter_inappwebview: {
      callHandler: (handler, message, nextIndex) => {
        messages.push({handler, message, nextIndex});
        return Promise.resolve(handler === 'FlutterCommentPaste' ? pasteBehavior(message) : undefined);
      },
    },
  };
  const context = {
    KeyboardEvent: class { constructor(type, options) { this.type = type; Object.assign(this, options); } },
    Math: { random: () => randomValue, floor: Math.floor, min: Math.min, max: Math.max },
    document, window, URL, location: {href: 'https://www.tiktok.com/'}, innerWidth: 400, innerHeight: 800,
    Date: { now: () => now },
    getComputedStyle: (element) => ({
      display: element.hidden ? 'none' : 'block',
      visibility: 'visible', opacity: element.opacity ?? '1', overflowY: 'auto',
    }),
    setInterval: (callback) => { intervals.add(callback); return callback; },
    clearInterval: (callback) => intervals.delete(callback),
  };
  function addVideo(top = 0) {
    const listeners = new Map();
    const video = {
      tagName: 'VIDEO', top, hidden: false, currentSrc: `video-${videos.length}`,
      src: '', currentTime: 0, duration: 10, loop: true,
      paused: true, ended: false, parentElement: null, plays: 0,
      getBoundingClientRect() {
        return { top: this.top, bottom: this.top + 800,
          left: 0, right: 400, width: 400, height: 800 };
      },
      closest: () => null,
      querySelector: () => null,
      setAttribute: () => {},
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: (name) => listeners.delete(name),
      pause() { this.paused = true; },
      play() { this.plays++; this.paused = false; return Promise.resolve(); },
      scrollIntoView(options) {
        scrolls.push(options);
        const offset = this.top;
        for (const item of videos) item.top -= offset;
      },
      finish() {
        this.ended = true;
        this.currentTime = this.duration;
        listeners.get('ended')?.();
      },
      listeners,
    };
    videos.push(video);
    return video;
  }
  return {
    addVideo, videos, scrolls, buttons, cards, dialogs, messages, document, window, intervals,
    editors, responses, fetch,
    focus: (editor) => { focusedEditor = editor; document.activeElement = editor; },
    paste: (callback) => { pasteBehavior = callback; },
    random: (value) => { randomValue = value; },
    configure: (comments) => {
      window.__flutterAutoWatchConfig = {comments};
    },
    respond: async (body) => {
      assert.ok(responses.length, 'expected a submitted comment request');
      responses.shift()({ clone: () => ({json: () => Promise.resolve(body)}) });
      await new Promise(resolve => setImmediate(resolve));
    },
    elapse: (milliseconds) => { now += milliseconds; },
    start: () => runInNewContext(start, context),
    stop: () => runInNewContext(stop, context),
    tick: () => [...intervals].forEach((callback) => callback()),
  };
}

test('watches the full video, then advances once and plays the next video', () => {
  const env = setup();
  const first = env.addVideo();
  const next = env.addVideo(800);
  assert.equal(env.start(), true);
  assert.equal(first.loop, false);
  assert.equal(first.plays, 1);
  assert.equal(first.playsInline, true);
  first.currentTime = 9.9;
  env.tick();
  assert.equal(env.scrolls.length, 0);
  first.finish();
  first.finish();
  assert.equal(env.scrolls.length, 1);
  env.tick();
  assert.equal(first.loop, true);
  assert.equal(next.plays, 1);
  next.finish();
  assert.equal(env.scrolls.length, 2);
});

test('ignores hidden videos and stops cleanly, restoring the loop setting', () => {
  const env = setup();
  const preview = env.addVideo();
  preview.hidden = true;
  const active = env.addVideo();
  env.start();
  preview.finish();
  assert.equal(env.scrolls.length, 0);
  assert.equal(preview.loop, true);
  assert.equal(active.loop, false);
  env.stop();
  assert.equal(active.loop, true);
  assert.equal(active.listeners.size, 0);
  assert.equal(env.intervals.size, 0);
  active.finish();
  assert.equal(env.scrolls.length, 0);
});

test('detects players that loop by resetting time without an ended event', () => {
  const env = setup();
  const video = env.addVideo();
  env.start();
  video.currentTime = 9.8;
  env.tick();
  video.currentTime = 0.1;
  env.tick();
  assert.equal(env.scrolls.length, 1);
  env.tick();
  assert.equal(env.scrolls.length, 1);
});

test('handles source changes on a reused video element and repeated starts', () => {
  const env = setup();
  const video = env.addVideo();
  env.start();
  env.start();
  assert.equal(env.intervals.size, 1);
  video.finish();
  assert.equal(env.scrolls.length, 1);
  video.currentSrc = 'new-source';
  video.ended = false;
  video.currentTime = 0;
  video.paused = true;
  env.tick();
  video.finish();
  assert.equal(env.scrolls.length, 2);
});

test('scrolls the inner feed container when the next video is not mounted', () => {
  const env = setup();
  const video = env.addVideo();
  video.parentElement = {
    scrollHeight: 2400, clientHeight: 800, scrollTop: 0, parentElement: null,
    scrollBy: (options) => env.scrolls.push({ inner: true, ...options }),
  };
  env.start();
  video.finish();
  assert.equal(env.scrolls.length, 1);
  assert.equal(env.scrolls[0].inner, true);
  assert.equal(env.scrolls[0].top, 800);
});

test('does not advance while the document is hidden', () => {
  const env = setup();
  const video = env.addVideo();
  env.start();
  env.document.hidden = true;
  video.finish();
  env.tick();
  assert.equal(env.scrolls.length, 0);
  env.document.hidden = false;
  env.tick();
  assert.equal(env.scrolls.length, 1);
});

test('waits for SPA-mounted videos and respects a manual pause', () => {
  const env = setup();
  env.start();
  env.tick();
  assert.equal(env.scrolls.length, 0);
  const video = env.addVideo();
  env.tick();
  assert.equal(video.plays, 1);
  video.paused = true;
  env.tick();
  assert.equal(video.plays, 1);
  assert.equal(env.scrolls.length, 0);
});

test('uses an available next-video button before falling back to scrolling', () => {
  const env = setup();
  const video = env.addVideo();
  let clicks = 0;
  env.buttons.push({
    disabled: false,
    getAttribute: (name) => name === 'aria-label' ? 'Next video' : null,
    getBoundingClientRect: () => ({ top: 100, bottom: 150, left: 0, right: 50 }),
    click: () => clicks++,
  });
  env.start();
  video.finish();
  assert.equal(clicks, 1);
  assert.equal(env.scrolls.length, 0);
});

test('uses TikTok feed next control even when responsive layout hides its label', () => {
  const env = setup();
  const video = env.addVideo();
  let clicks = 0;
  env.buttons.push({
    disabled: false,
    getAttribute: (name) => name === 'data-e2e' ? 'feed-navigation-next' : null,
    click: () => clicks++,
  });
  env.start();
  video.finish();
  assert.equal(clicks, 1);
  assert.equal(env.scrolls.length, 0);
});

test('retries a next button that did not change the video using scrolling', () => {
  const env = setup();
  const video = env.addVideo();
  env.buttons.push({
    disabled: false,
    getAttribute: (name) => name === 'data-e2e' ? 'feed-navigation-next' : null,
    click: () => {},
  });
  env.start();
  video.finish();
  assert.equal(env.scrolls.length, 0);
  env.elapse(1500);
  env.tick();
  assert.equal(env.scrolls.length, 1);
  // Do not immediately skip another item or spin forever at the end of a feed.
  env.tick();
  assert.equal(env.scrolls.length, 1);
  for (let i = 0; i < 10; i++) { env.elapse(1500); env.tick(); }
  assert.equal(env.scrolls.length, 3);
});

test('advances a photo post after five seconds even if the next video is offscreen', () => {
  const env = setup();
  const photo = {
    getBoundingClientRect: () => ({top:0,bottom:800,left:72,right:440,width:368}),
    querySelector: (selector) => selector.startsWith('.swiper') ? ({}) : null,
    closest: () => null,
  };
  let nextScrolls = 0;
  const next = {
    getBoundingClientRect: () => ({top:800,bottom:1600,left:72,right:440,width:368}),
    querySelector: () => null,
    scrollIntoView: () => nextScrolls++,
  };
  env.cards.push(photo, next);
  env.addVideo(1100);
  env.start();
  env.elapse(4999);
  env.tick();
  assert.equal(nextScrolls, 0);
  env.elapse(1);
  env.tick();
  assert.equal(nextScrolls, 1);
  env.tick();
  assert.equal(nextScrolls, 1);
});

test('accepts caption overlays outside the media section but inside the article', () => {
  const env = setup();
  const video = env.addVideo();
  const overlay = {};
  const article = { contains: (element) => element === overlay };
  const mediaSection = { contains: () => false };
  video.closest = (selector) => selector === 'article' ? article : mediaSection;
  env.document.elementFromPoint = () => overlay;
  env.start();
  assert.equal(video.plays, 1);
});

test('watches TikTok decoder videos with opacity zero inside a visible player', async () => {
  const env = setup();
  const video = env.addVideo();
  video.opacity = '0';
  env.start();
  assert.equal(video.plays, 1);
  video.finish();
  assert.equal(env.scrolls.length, 1);
});


function attachComments(env, video) {
  const submit = {
    clicks: 0, disabled: false,
    getAttribute: () => null,
    click() {
      this.clicks++;
      env.window.fetch('https://www.tiktok.com/api/comment/publish/');
    },
  };
  const close = {clicks: 0, click() { this.clicks++; env.editors.length = 0; }};
  const panel = { style: {cssText: 'original'},
    getBoundingClientRect: () => ({left:440,right:728,width:288}),
    querySelector: (selector) =>
    selector.includes('comment-post') ? submit : close };
  const editor = {
    textContent: '', hidden: false, parentElement: panel,
    getAttribute: (name) => name === 'contenteditable' ? 'true' : null,
    offscreen: false,
    getBoundingClientRect() {
      const left = this.offscreen && !panel.style.cssText.includes('translateX') ? 465 : 100;
      return {top:600,bottom:630,left,right:left+200,width:200,height:30};
    },
    closest: () => panel,
    focus() { env.focus(this); }, blur: () => {},
  };
  const action = { clicks: 0, getAttribute: () => null,
    click() { this.clicks++; env.editors.push(editor); } };
  const control = { querySelector: () => action,
    getAttribute: (name) => name === 'role' ? 'button' : null,
    dispatchEvent: (event) => {
      assert.equal(event.type, 'keydown');
      assert.equal(event.key, 'Enter');
      action.click();
    },
    click: () => assert.fail('must click the actual comment button') };
  const article = {
    contains: (element) => element === video,
    getBoundingClientRect: () => video.getBoundingClientRect(),
    scrollIntoView: (options) => video.scrollIntoView(options),
    querySelector: (selector) => selector.includes('comment-icon') ? control : null,
  };
  video.closest = (selector) => selector === 'article' ? article : null;
  return {submit, close, editor, control, article, panel};
}

async function beginComment(env, video, settlePaste = true) {
  video.currentTime = 2;
  env.elapse(2000);
  env.tick(); // Open the panel.
  env.tick(); // Request native clipboard paste.
  if (settlePaste) await new Promise(setImmediate);
  env.tick(); // Verify the pasted text and submit once.
}

const saved = (text) => ({ status_code: 0, comment: { cid: 'saved', text } });

test('randomly selects user comments, confirms saving and watches to the end', async () => {
  const env = setup();
  env.configure(['Bình luận một', 'Bình luận hai']);
  const videos = [env.addVideo(), env.addVideo(800), env.addVideo(1600)];
  const controls = videos.map(video => attachComments(env, video));
  env.start();
  for (let i = 0; i < videos.length; i++) {
    const video = videos[i];
    const controlsForPost = controls[i];
    await beginComment(env, video);
    const expected = i % 2 ? 'Bình luận hai' : 'Bình luận một';
    assert.equal(controlsForPost.editor.textContent, expected);
    assert.equal(controlsForPost.submit.clicks, 1);
    assert.equal(video.paused, false);
    assert.equal(video.loop, true);
    assert.equal(controls[(i + 1) % 3].submit.clicks, i === 2 ? 1 : 0);
    env.tick();
    assert.equal(controlsForPost.submit.clicks, 1);
    assert.equal(env.scrolls.length, i);
    await env.respond(saved(expected));
    env.tick();
    assert.equal(video.paused, false);
    assert.equal(controlsForPost.close.clicks, 1);
    video.currentTime = 9;
    env.tick();
    assert.equal(env.scrolls.length, i);
    video.finish();
    env.tick();
    assert.equal(env.scrolls.length, i + 1);
    assert.equal(controlsForPost.submit.clicks, 1);
  }
  assert.equal(env.messages.filter(m=>m.message === 'comment-sent').length, 3);
});

test('waits for a comment on a short video before advancing', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  video.finish();
  env.tick();
  await new Promise(setImmediate);
  env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.scrolls.length, 0);
  await env.respond(saved('Hello'));
  env.tick();
  assert.equal(env.scrolls.length, 1);
});

test('stops on an unconfirmed submission and does not submit again after restart', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  ui.editor.textContent = ''; // Clearing alone cannot prove saving.
  env.elapse(15000);
  env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.intervals.size, 0);
  assert.equal(env.messages.at(-1).message, 'comment-failed');
  assert.equal(env.window.fetch, env.fetch);
  env.start();
  video.currentTime = 3;
  env.elapse(2000);
  env.tick();
  assert.equal(ui.submit.clicks, 1);
});

test('does not overwrite a comment draft', () => {
  const env = setup();
  env.configure(['Automatic']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  ui.editor.textContent = 'My unfinished draft';
  env.editors.push(ui.editor);
  env.start();
  video.currentTime = 2;
  env.elapse(2000);
  env.tick();
  assert.equal(ui.editor.textContent, 'My unfinished draft');
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.messages[0].message, 'comment-draft-exists');
  assert.equal(env.intervals.size, 0);
});

test('waits for the submit button to become enabled', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  ui.submit.disabled = true;
  env.start();
  await beginComment(env, video);
  assert.equal(ui.submit.clicks, 0);
  ui.submit.disabled = false;
  env.tick(); env.tick();
  assert.equal(ui.submit.clicks, 1);
});

test('server rejection stops automation without repeating the comment', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  await env.respond({status_code: 1});
  env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.intervals.size, 0);
  assert.equal(env.scrolls.length, 0);
  assert.equal(env.messages.at(-1).message, 'comment-failed');
});

test('stopping before submission cancels it and restores the page fetch', () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  video.currentTime = 2;
  env.elapse(2000);
  env.tick(); env.tick();
  env.stop();
  env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.window.fetch, env.fetch);
  assert.equal(video.paused, false);
});

test('does not fill or submit a comment while the page is hidden', () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  video.currentTime = 2;
  env.elapse(2000);
  env.tick();
  env.document.hidden = true;
  env.tick(); env.tick();
  assert.equal(ui.editor.textContent, '');
  assert.equal(ui.submit.clicks, 0);
});

test('stops if the video source changes before submitting', () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  video.currentTime = 2;
  env.elapse(2000);
  env.tick();
  video.currentSrc = 'another-post';
  env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.messages[0].message, 'comment-post-changed');
});

test('stops for the TikTok login dialog before typing or submitting', () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  video.currentTime = 2;
  env.elapse(2000);
  env.tick();
  env.dialogs.push({
    innerText: 'Log in to TikTok',
    getBoundingClientRect: () => ({top:100,bottom:600,left:50,right:350}),
  });
  env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.intervals.size, 0);
  assert.equal(env.messages[0].message, 'login-required');
});

test('avoids consecutive repeated comments across script restarts', async () => {
  const env = setup();
  env.configure(['First', 'Second']);
  const video = env.addVideo();
  let ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  await env.respond(saved('First'));
  env.tick();
  env.stop();
  video.currentSrc = 'new-source';
  ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  assert.equal(ui.editor.textContent, 'Second');
});


test('uses the random value to choose from the array rather than sequential order', async () => {
  const env = setup();
  env.configure(['First', 'Second', 'Third', 'Fourth']);
  env.random(0.99);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  assert.equal(ui.editor.textContent, 'Fourth');
});


test('pastes once through the native bridge and verifies text before submit', async () => {
  const env = setup();
  const text = 'Cảm ơn bạn 😊';
  env.configure([text]);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.paste((clipboardText) => {
    assert.equal(clipboardText, text);
    assert.equal(env.window.__flutterAutoWatch.canPasteComment(text), true);
    ui.editor.textContent = clipboardText;
    return true;
  });
  env.start();
  await beginComment(env, video, false);
  assert.equal(ui.submit.clicks, 0);
  await new Promise(resolve => setImmediate(resolve));
  env.tick(); env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.messages.filter(m=>m.handler==='FlutterCommentPaste').length, 1);
  await env.respond(saved(text));
  env.tick();
  assert.equal(env.messages.at(-1).message, 'comment-sent');
});

test('a native paste failure stops without submitting or retrying', async () => {
  const env = setup();
  env.paste(() => false);
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  await new Promise(resolve => setImmediate(resolve));
  env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.intervals.size, 0);
  assert.equal(env.messages.at(-1).message, 'comment-paste-failed');
});

test('does not submit if paste reports success but no text appears', async () => {
  const env = setup();
  env.configure(['Hello']);
  env.paste(() => true);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  await new Promise(resolve => setImmediate(resolve));
  env.elapse(2000); env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.messages.at(-1).message, 'comment-paste-failed');
});

test('cancellation during clipboard paste cannot submit after the callback resolves', async () => {
  const env = setup();
  env.configure(['Hello']);
  let resolvePaste;
  env.paste(() => new Promise(resolve => { resolvePaste = resolve; }));
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.start();
  await beginComment(env, video);
  env.stop();
  resolvePaste(true);
  await new Promise(resolve => setImmediate(resolve));
  env.tick();
  assert.equal(ui.submit.clicks, 0);
  assert.equal(env.intervals.size, 0);
});

test('brings an offscreen desktop comment panel into view and restores its layout', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  ui.editor.offscreen = true;
  env.start();
  await beginComment(env, video);
  assert.ok(ui.panel.style.cssText.includes('translateX'));
  assert.equal(ui.submit.clicks, 1);
  await env.respond(saved('Hello'));
  env.tick();
  assert.equal(ui.panel.style.cssText, 'original');
});


test('always pastes natively even when a legacy configuration disables clipboard', async () => {
  const env = setup();
  env.configure(['Hello']);
  env.window.__flutterAutoWatchConfig.useClipboard = false;
  const video = env.addVideo();
  const ui = attachComments(env, video);
  env.document.execCommand = () => assert.fail('All platforms must use native paste');
  env.paste(text => { ui.editor.textContent = text; return true; });
  env.start();
  await beginComment(env, video);
  await new Promise(resolve => setImmediate(resolve));
  env.tick();
  assert.equal(ui.submit.clicks, 1);
});

test('uses clipboard to update controlled editor state before posting', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  ui.submit.disabled = true;
  env.paste(text => {
    ui.editor.textContent = text;
    ui.submit.disabled = false;
    return true;
  });
  env.start();
  await beginComment(env, video);
  env.elapse(1000); env.tick();
  await new Promise(resolve => setImmediate(resolve));
  env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.messages.filter(m => m.handler === 'FlutterCommentPaste').length, 1);
});

test('tries the accessible Enter action once when the comment click is ignored', async () => {
  const env = setup();
  env.configure(['Hello']);
  const video = env.addVideo();
  const ui = attachComments(env, video);
  ui.control.querySelector = () => ({getAttribute: () => null, click: () => {}});
  env.start();
  video.currentTime = 2;
  env.elapse(2000); env.tick();
  assert.equal(env.editors.length, 0);
  env.elapse(2000); env.tick();
  env.tick();
  await new Promise(setImmediate);
  env.tick();
  assert.equal(ui.submit.clicks, 1);
  assert.equal(env.editors.length, 1);
});
