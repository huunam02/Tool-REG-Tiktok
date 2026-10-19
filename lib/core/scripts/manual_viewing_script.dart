import 'dart:convert';

/// Observes playback and confirmed comments in manual or automatic viewing;
/// never clicks, scrolls,
/// starts playback, fills a form, or sends a request.
String buildManualViewingScript(
  String session,
  String segment, {
  String handlerName = 'FlutterManualViewingStats',
  bool allowTransparentVideo = false,
}) =>
    'window.__manualViewingConfig = ${jsonEncode({'session': session, 'segment': segment, 'handler': handlerName, 'allowTransparentVideo': allowTransparentVideo})};\n'
    '$manualViewingScript';

const manualViewingScript = r'''
(() => {
  if (window.top !== window || location.protocol !== 'https:' ||
      !(location.hostname === 'tiktok.com' || location.hostname.endsWith('.tiktok.com'))) return false;
  const config = window.__manualViewingConfig;
  if (!config?.session || !config?.segment) return false;
  if (window.__manualViewing?.segment === config.segment) return true;
  window.__manualViewing?.stop();
  let running = true, foreground = true, sequence = 0, current = null;
  let watched = 0, videos = 0, full = 0, skipped = 0, comments = 0;
  let lastEmit = 0;
  const commentIds = new Set();
  const snapshot = () => ({session: config.session, segment: config.segment,
    sequence: ++sequence, watch_ms: Math.floor(watched * 1000),
    videos, full_videos: full, skipped_videos: skipped, comments});
  const emit = () => {
    const value = snapshot();
    try { window.flutter_inappwebview?.callHandler(config.handler || 'FlutterManualViewingStats', value)?.catch?.(() => {}); } catch (_) {}
    lastEmit = Date.now();
    return value;
  };
  const area = (video) => {
    const rect = video.getBoundingClientRect();
    const style = getComputedStyle(video);
    if (style.display === 'none' || style.visibility === 'hidden' ||
        (!config.allowTransparentVideo && Number(style.opacity) === 0)) return 0;
    return Math.max(0, Math.min(rect.right, innerWidth) - Math.max(0, rect.left)) *
      Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(0, rect.top));
  };
  const finishVideo = () => {
    if (!current || current.counted || current.watched <= 0) return;
    current.counted = true;
    videos++;
    if (current.completed || current.video.ended) full++; else skipped++;
    emit();
  };
  const sample = () => {
    if (!running || !foreground || document.visibilityState === 'hidden') {
      if (current) current.lastTime = null;
      return;
    }
    let selected = null, largest = 0;
    for (const video of document.querySelectorAll('video')) {
      const size = area(video);
      if (size > largest) { largest = size; selected = video; }
    }
    const key = selected ? location.pathname + '|' + (selected.currentSrc || selected.src || '') : '';
    if (current && (current.video !== selected || current.key !== key)) {
      finishVideo();
      current = null;
    }
    if (!selected) return;
    if (!current) current = {video: selected, key, watched: 0, counted: false, lastTime: null, lastWall: Date.now()};
    const time = Number(selected.currentTime), now = Date.now();
    const duration = Number(selected.duration);
    const wrapped = !selected.seeking && current.lastTime !== null &&
      Number.isFinite(duration) && duration > 0 &&
      current.lastTime >= Math.max(0, duration - 0.5) &&
      current.lastTime > time + 0.5 && time < 0.5;
    const delta = current.lastTime === null ? 0 : wrapped
      ? duration - current.lastTime + time : time - current.lastTime;
    const elapsed = Math.max(0, (now - current.lastWall) / 1000);
    if (!selected.seeking && (!selected.paused || selected.ended) && Number.isFinite(delta) &&
        delta > 0 && delta <= Math.min(2, elapsed * 1.5 + 0.25)) {
      watched += delta;
      current.watched += delta;
    }
    current.lastTime = selected.seeking || (selected.paused && !selected.ended) ? null : time;
    current.lastWall = now;
    if (wrapped) current.completed = true;
    if (selected.ended || wrapped) finishVideo();
    if (now - lastEmit >= 2000) emit();
  };
  const observeComment = (url, body) => {
    if (!running) return;
    try {
      const parsed = new URL(String(url), location.href);
      if (parsed.origin !== location.origin || !/\/comment\/(?:publish|post|create)\/?$/.test(parsed.pathname) ||
          body?.status_code !== 0 || !body.comment?.cid) return;
      const id = String(body.comment.cid);
      if (commentIds.has(id)) return;
      commentIds.add(id);
      comments++;
      emit();
    } catch (_) {}
  };
  const originalFetch = window.fetch;
  const wrappedFetch = typeof originalFetch !== 'function' ? null : function(...args) {
    const pending = originalFetch.apply(this, args);
    pending.then((response) => {
      const url = response.url || args[0]?.url || args[0];
      if (String(url).includes('/comment/')) response.clone().json().then((body) => observeComment(url, body)).catch(() => {});
    }).catch(() => {});
    return pending;
  };
  if (wrappedFetch) window.fetch = wrappedFetch;
  const xhr = window.XMLHttpRequest?.prototype;
  const originalOpen = xhr?.open;
  const urls = new WeakMap();
  const onResponse = function() {
    try {
      const body = this.responseType === 'json' ? this.response : JSON.parse(this.responseText);
      observeComment(this.responseURL || urls.get(this), body);
    } catch (_) {}
  };
  const wrappedOpen = !originalOpen ? null : function(method, url, ...rest) {
    urls.set(this, url);
    this.removeEventListener('load', onResponse);
    this.addEventListener('load', onResponse);
    return originalOpen.call(this, method, url, ...rest);
  };
  if (wrappedOpen) xhr.open = wrappedOpen;
  const visibility = () => { if (current) current.lastTime = null; emit(); };
  const pagehide = () => { sample(); finishVideo(); emit(); };
  // Capture completion before the page's ended handler replaces the video.
  const ended = () => sample();
  document.addEventListener('visibilitychange', visibility);
  document.addEventListener('ended', ended, true);
  window.addEventListener?.('pagehide', pagehide);
  const interval = setInterval(sample, 250);
  window.__manualViewing = {
    segment: config.segment,
    setActive(active) { sample(); foreground = !!active; if (current) current.lastTime = null; return emit(); },
    stop() {
      if (!running) return null;
      sample(); finishVideo();
      const value = emit();
      running = false;
      clearInterval(interval);
      document.removeEventListener('visibilitychange', visibility);
      document.removeEventListener('ended', ended, true);
      window.removeEventListener?.('pagehide', pagehide);
      if (window.fetch === wrappedFetch) window.fetch = originalFetch;
      if (xhr?.open === wrappedOpen) xhr.open = originalOpen;
      delete window.__manualViewing;
      return value;
    },
  };
  sample();
  return true;
})();
''';
