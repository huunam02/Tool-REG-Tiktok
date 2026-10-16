const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const source = readFileSync(new URL('../lib/core/scripts/manual_viewing_script.dart', `file://${__filename}`), 'utf8');
const script = source.match(/manualViewingScript = r'''([\s\S]*?)''';/)[1];

function setup(host = 'www.tiktok.com') {
  let now = 0;
  const intervals = new Set(), videos = [], messages = [], responses = [];
  const listeners = new Map();
  const location = { protocol: 'https:', hostname: host, origin: `https://${host}`,
    href: `https://${host}/`, pathname: '/' };
  class XHR {
    listeners = new Map();
    open(method, url) { this.url = url; }
    addEventListener(name, fn) { this.listeners.set(name, fn); }
    removeEventListener(name) { this.listeners.delete(name); }
    respond(body) { this.responseText = JSON.stringify(body); this.listeners.get('load')?.call(this); }
  }
  const originalFetch = () => new Promise(resolve => responses.push(resolve));
  const originalOpen = XHR.prototype.open;
  const window = { __manualViewingConfig: {session: 's', segment: '1'}, fetch: originalFetch, XMLHttpRequest: XHR,
    flutter_inappwebview: { callHandler(name, value) { messages.push({name, value}); return Promise.resolve(); } },
    scrollBy() { assert.fail('Must not automate viewing'); },
  };
  window.top = window;
  const document = {visibilityState: 'visible', querySelectorAll: () => videos,
    addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name)};
  const context = {window, document, location, URL, innerWidth: 400, innerHeight: 800,
    getComputedStyle: video => ({display: video.hidden ? 'none' : 'block', visibility: 'visible', opacity: '1'}),
    Date: {now: () => now}, setInterval(fn) { intervals.add(fn); return fn; }, clearInterval(fn) { intervals.delete(fn); }};
  function addVideo() {
    const video = {currentTime: 0, duration: 10, currentSrc: `v${videos.length}`, paused: false, ended: false,
      seeking: false, hidden: false, top: 0,
      getBoundingClientRect() { return {left: 0, right: 400, top: this.top, bottom: this.top + 800}; },
      play() { assert.fail('Must not start playback'); }, click() { assert.fail('Must not click'); },
      scrollIntoView() { assert.fail('Must not scroll'); }};
    videos.push(video); return video;
  }
  const start = () => runInNewContext(script, context);
  const tick = (seconds = .25) => { now += seconds * 1000; for (const fn of intervals) fn(); };
  const play = (video, seconds) => { for (let i = 0; i < seconds * 4; i++) { video.currentTime += .25; tick(); } };
  const snapshot = () => messages.at(-1).value;
  return {window, document, listeners, videos, messages, responses, intervals, addVideo, start, tick, play, snapshot, originalFetch, originalOpen, XHR};
}

test('passively counts real playback and flushes final video once', () => {
  const h = setup(), video = h.addVideo();
  assert.equal(h.start(), true);
  h.play(video, 3);
  const value = h.window.__manualViewing.stop();
  assert.equal(value.watch_ms, 3000);
  assert.equal(value.videos, 1);
  assert.equal(value.skipped_videos, 1);
  assert.equal(value.comments, 0);
  assert.equal(h.intervals.size, 0);
  assert.equal(h.window.fetch, h.originalFetch);
  assert.equal(h.XHR.prototype.open, h.originalOpen);
});

test('pause, hidden page, buffering and seeks do not inflate time', () => {
  const h = setup(), video = h.addVideo(); h.start();
  h.play(video, 2);
  video.paused = true; h.play(video, 2);
  video.paused = false; h.tick(); h.play(video, 1);
  video.seeking = true; video.currentTime = 90; h.tick();
  video.seeking = false; h.tick(); h.play(video, 1);
  h.document.visibilityState = 'hidden'; h.play(video, 2);
  h.document.visibilityState = 'visible'; h.tick(); h.play(video, 1);
  for (let i = 0; i < 12; i++) h.tick();
  assert.equal(h.window.__manualViewing.stop().watch_ms, 5000);
});

test('app background retains segment without counting background time', () => {
  const h = setup(), video = h.addVideo(); h.start(); h.play(video, 2);
  h.window.__manualViewing.setActive(false); h.play(video, 5);
  h.window.__manualViewing.setActive(true); h.tick(); h.play(video, 2);
  const value = h.window.__manualViewing.stop();
  assert.equal(value.watch_ms, 4000); assert.equal(value.videos, 1);
});

test('ended video is counted once and changing video accounts for the previous view', () => {
  const h = setup(), first = h.addVideo(); first.duration = 2; h.start(); h.play(first, 2);
  first.ended = true; h.tick(); h.tick();
  assert.equal(h.snapshot().full_videos, 1);
  first.hidden = true; const second = h.addVideo(); h.tick(); h.play(second, 2);
  const value = h.window.__manualViewing.stop();
  assert.equal(value.videos, 2); assert.equal(value.full_videos, 1); assert.equal(value.skipped_videos, 1);
});

test('hidden video and idle form produce no views', () => {
  const h = setup(), video = h.addVideo(); video.hidden = true; h.start(); h.play(video, 3);
  const value = h.window.__manualViewing.stop();
  assert.equal(value.watch_ms, 0); assert.equal(value.videos, 0);
});

test('successful manual XHR comments count once while failed and unrelated replies do not', () => {
  const h = setup(); h.start(); const xhr = new h.XHR();
  xhr.open('POST', '/api/comment/publish/');
  xhr.respond({status_code: 1, comment: {cid: 'failure'}});
  xhr.respond({status_code: 0, comment: {cid: 'a'}});
  xhr.respond({status_code: 0, comment: {cid: 'a'}});
  xhr.open('GET', '/api/comment/list/'); xhr.respond({status_code: 0, comment: {cid: 'other'}});
  xhr.open('POST', 'https://example.com/api/comment/publish/'); xhr.respond({status_code: 0, comment: {cid: 'foreign'}});
  assert.equal(h.window.__manualViewing.stop().comments, 1);
});

test('fetch observes a clone and preserves the original response and request behavior', async () => {
  const h = setup(); h.start();
  const pending = h.window.fetch('/api/comment/publish/');
  const response = {url: 'https://www.tiktok.com/api/comment/publish/', clone: () => ({json: async () => ({status_code: 0, comment: {cid: 'fetch-comment'}})})};
  h.responses.shift()(response);
  assert.equal(await pending, response);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.window.__manualViewing.stop().comments, 1);
});

test('same segment reinjection is idempotent and other origins and frames are ignored', () => {
  const h = setup(); h.start(); h.start(); assert.equal(h.intervals.size, 1);
  h.window.__manualViewing.stop();
  const foreign = setup('example.com'); assert.equal(foreign.start(), false); assert.equal(foreign.intervals.size, 0);
  const frame = setup(); frame.window.top = {}; assert.equal(frame.start(), false);
});
