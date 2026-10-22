import 'dart:convert';

// Set inline playback before TikTok calls play(), including before automation
// is enabled.
const String inlineVideoScript = r'''
(() => {
  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function(...args) {
    if (this.tagName === 'VIDEO') {
      this.playsInline = true;
      this.setAttribute('playsinline', '');
      this.setAttribute('webkit-playsinline', '');
    }
    return originalPlay.apply(this, args);
  };
})();
''';
String buildAutoWatchScript(List<String> comments) =>
    'window.__flutterAutoWatchConfig = ${jsonEncode({'comments': comments})};\n'
    '$autoWatchStartScript';

/// Runs inside GeckoView. Calling it again replaces the previous watcher.
const String autoWatchStartScript = r'''
(() => {
  window.__flutterAutoWatch?.stop();
  let activeVideo = null;
  let activeSource = '';
  let originalLoop = false;
  let lastTime = 0;
  let completed = false;
  let photoCard = null;
  let photoStartedAt = 0;
  let pendingAdvance = null;
  let watchPlan = null;
  let playbackWrapped = false;
  let comment = null;
  let commentAttemptCount = 0;
  let running = true;
  let liveInvite = null;
  // One choice per post, retained when this document's watcher is restarted.
  const watchPlans = window.__flutterWatchPlans ||= new Map();
  // One random delay per actual UI action; do not redraw it every 250ms tick.
  // Most actions use 3-6s; absolute limits are 2-10s.
  const actionDelayMs = () => {
    const bucket = Math.random();
    if (bucket < 0.70) return 3000 + Math.floor(Math.random() * 3001);
    if (bucket < 0.85) return 2000 + Math.floor(Math.random() * 1001);
    return 6001 + Math.floor(Math.random() * 4000);
  };
  const config = window.__flutterAutoWatchConfig || { comments: [] };
  const comments = config.comments.filter((text) => typeof text === 'string' && text.trim());
  const signature = JSON.stringify(comments);
  const selectionState = window.__flutterCommentSelection?.signature === signature
    ? window.__flutterCommentSelection
    : (window.__flutterCommentSelection = { signature, lastIndex: -1 });
  const randomComment = () => {
    const previous = selectionState.lastIndex;
    // Choose uniformly from the remaining entries to avoid consecutive repeats.
    const excludePrevious = comments.length > 1 && previous >= 0;
    let index = Math.floor(Math.random() * (comments.length - (excludePrevious ? 1 : 0)));
    if (excludePrevious && index >= previous) index++;
    selectionState.lastIndex = index;
    return comments[index];
  };
  // Keep the ledger when the toggle or app lifecycle restarts this script.
  const attemptedPosts = window.__flutterCommentedPosts ||= new Set();
  const reportedMessages = new Set();
  const notifyFlutter = (message) => {
    if (reportedMessages.has(message)) return;
    reportedMessages.add(message);
    const result = window.gecko_bridge?.callHandler('FlutterAutoWatch', message);
    result?.catch(() => {});
  };
  const visibleArea = (element, allowTransparent = false) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden' ||
        (!allowTransparent && Number(style.opacity) === 0)) return 0;
    return Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0)) *
      Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));
  };
  const captchaVisible = () => Array.from(document.querySelectorAll(
    '#captcha-verify-container, .captcha-verify-container, .captcha-disable-scroll, .captcha_verify_slide--slidebar, iframe[src*="captcha"]'
  )).some(element => visibleArea(element) > 0);
  const dismissLiveInvite = () => {
    const selector = 'button, [role="button"], a, div, span';
    const label = element => (element.textContent ||
      element.getAttribute?.('aria-label') || '').trim();
    const enabled = element => !element.disabled &&
      element.getAttribute?.('aria-disabled') !== 'true' && visibleArea(element) > 0;
    const controls = Array.from(document.querySelectorAll(selector));
    for (const button of controls.reverse()) {
      if (!/^not now$/i.test(label(button)) || !enabled(button)) continue;
      // Only dismiss a LIVE invitation containing both controls. Other dialogs
      // can also say Not now (notifications, account settings, etc.).
      let parent = button.parentElement;
      let invitation = false;
      for (let depth = 0; parent && depth < 5; depth++, parent = parent.parentElement) {
        if (['BODY', 'HTML', 'ARTICLE'].includes(parent.tagName)) break;
        if (Array.from(parent.querySelectorAll(selector)).some(candidate =>
            /^watch live$/i.test(label(candidate)) && enabled(candidate))) {
          invitation = true;
          break;
        }
      }
      if (!invitation) continue;
      const rect = button.getBoundingClientRect();
      const hit = document.elementFromPoint(
        (Math.max(0, rect.left) + Math.min(innerWidth, rect.right)) / 2,
        (Math.max(0, rect.top) + Math.min(innerHeight, rect.bottom)) / 2);
      if (!hit || !(hit === button || button.contains?.(hit))) continue;
      if (liveInvite?.button !== button) {
        liveInvite = { button, readyAt: Date.now() + actionDelayMs(), clicked: false };
      }
      if (!liveInvite.clicked && Date.now() >= liveInvite.readyAt) {
        liveInvite.clicked = true;
        button.click();
      }
      return true;
    }
    liveInvite = null;
    return false;
  };
  const findActiveCard = () => Array.from(document.querySelectorAll(
    'article[data-e2e="recommend-list-item-container"]'
  )).filter((card) => visibleArea(card) > 0).sort(
    (a, b) => visibleArea(b) - visibleArea(a)
  )[0] || null;
  const findActiveVideo = () => {
    let best = null;
    let bestArea = 0;
    for (const video of document.querySelectorAll('video')) {
      // TikTok can render through a canvas/cover while its decoder video has
      // opacity: 0. Its geometry and player hit target still identify the item.
      const area = visibleArea(video, true);
      if (area <= bestArea) continue;
      const rect = video.getBoundingClientRect();
      const x = (Math.max(0, rect.left) + Math.min(innerWidth, rect.right)) / 2;
      const y = (Math.max(0, rect.top) + Math.min(innerHeight, rect.bottom)) / 2;
      const top = document.elementFromPoint(x, y);
      // Player overlays are allowed; dialogs covering the player are not.
      const player = video.closest('article') ||
        video.closest('[data-e2e="feed-video"], [role="dialog"]') ||
        video.parentElement;
      if (top && (top === video || player?.contains(top))) {
        best = video;
        bestArea = area;
      }
    }
    return best;
  };
  const goToNextVideo = (video, attempt = 0) => {
    const card = video.closest('article') || video;
    const root = video.closest('[role="dialog"]') || document;
    // TikTok's responsive layout hides this control and leaves its label empty,
    // but the feed's click handler still advances to the next item.
    const feedNext = root.querySelector('[data-e2e="feed-navigation-next"]');
    if (attempt === 0 && feedNext && !feedNext.disabled &&
        feedNext.getAttribute('aria-disabled') !== 'true') {
      feedNext.click();
      return;
    }
    // Prefer an explicit player navigation control when one is present.
    for (const button of attempt === 0
        ? root.querySelectorAll('button, [role="button"]') : []) {
      const label = (button.getAttribute('aria-label') ||
        button.getAttribute('title') || button.textContent || '').trim();
      if (/^(?:(?:go|scroll) to )?(next video|next|video tiếp theo|tiếp theo)$/i.test(label) &&
          visibleArea(button) > 0 && !button.disabled &&
          button.getAttribute('aria-disabled') !== 'true') {
        button.click();
        return;
      }
    }
    const cardRect = card.getBoundingClientRect();
    const nextCard = Array.from(document.querySelectorAll(
      'article[data-e2e="recommend-list-item-container"]'
    )).filter((candidate) => candidate !== card &&
      candidate.getBoundingClientRect().width > 0 &&
      candidate.getBoundingClientRect().top >= cardRect.bottom - 1)
      .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[0];
    if (attempt < 2 && nextCard) {
      nextCard.scrollIntoView({ behavior: 'smooth', block: 'start' });
      return;
    }
    const currentRect = video.getBoundingClientRect();
    const nextVideo = Array.from(document.querySelectorAll('video'))
      .filter((candidate) => candidate !== video &&
        candidate.getBoundingClientRect().width > 0 &&
        candidate.getBoundingClientRect().top >= currentRect.bottom - 1)
      .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[0];
    if (attempt < 2 && nextVideo) {
      (nextVideo.closest('article') || nextVideo)
        .scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    // Virtualized feeds may only mount the current video. Scroll its container
    // so TikTok can mount the next item, including feeds using CSS scroll snap.
    for (let parent = video.parentElement; parent; parent = parent.parentElement) {
      if (/(auto|scroll)/.test(getComputedStyle(parent).overflowY) &&
          parent.scrollHeight > parent.clientHeight &&
          parent.scrollTop + parent.clientHeight < parent.scrollHeight - 1) {
        parent.scrollBy({ top: parent.clientHeight, behavior: 'smooth' });
        return;
      }
    }
    window.scrollBy({ top: innerHeight, behavior: 'smooth' });
  };
  const loginRequired = () => Array.from(document.querySelectorAll(
    '[role="dialog"], [aria-modal="true"], [class*="ModalContainer"]'
  )).some((dialog) => visibleArea(dialog) > 0 &&
    /log\s*in|đăng nhập/i.test(dialog.innerText || dialog.textContent || ''));
  const failComment = (message = 'comment-failed') => {
    notifyFlutter(message);
    window.__flutterAutoWatch?.stop();
  };
  const editorSelector = '[data-e2e="comment-text"] [contenteditable="true"], ' +
    '[data-e2e="comment-input"] textarea';
  const panelSelector = '[class*="DivVideoListTabBarWrapper"], ' +
    '[class*="SectionCommentSidebarContainer"], section, [role="dialog"]';
  const findEditor = () => {
    const editors = Array.from(document.querySelectorAll(editorSelector));
    return editors.find((editor) => visibleArea(editor) > 0) ||
      editors.find((editor) => {
        const rect = editor.getBoundingClientRect();
        const style = getComputedStyle(editor);
        return rect.width > 0 && rect.height > 0 &&
          style.display !== 'none' && style.visibility !== 'hidden';
      });
  };
  const exposePanel = (editor) => {
    if (visibleArea(editor) > 0 || comment.panelLayout) return;
    // The desktop site can mount its right panel at x=440 on a 440px phone.
    // Temporarily bring that existing panel into the viewport while editing.
    const panel = editor.closest(panelSelector);
    if (!panel?.style) return;
    comment.panelLayout = { panel, cssText: panel.style.cssText };
    const rect = panel.getBoundingClientRect();
    const offset = Math.min(0, innerWidth - rect.right);
    const transform = getComputedStyle(panel).transform;
    // Move visually without changing the feed layout or triggering its resize
    // logic, which can unmount the editor while the keyboard opens.
    panel.style.cssText += ';transform:translateX(' + offset + 'px) ' +
      (transform && transform !== 'none' ? transform : '') +
      '!important;z-index:9999!important;';
  };
  const restorePanel = (attempt) => {
    if (attempt?.panelLayout) {
      attempt.panelLayout.panel.style.cssText = attempt.panelLayout.cssText;
    }
  };
  const editorText = (editor) => (editor.value ?? editor.textContent ?? '').trim();
  const postRoot = (element) => element.closest('article') ||
    element.closest('[role="dialog"]') || element;
  const postKey = (element) => {
    const root = postRoot(element);
    const link = root.querySelector('a[href*="/video/"], a[href*="/photo/"]');
    return link?.getAttribute('href') || element.currentSrc || element.src ||
      root.querySelector('.swiper-slide img')?.src || root;
  };
  const planFor = (video) => {
    const key = postKey(video);
    let plan = watchPlans.get(key);
    if (!plan) {
      plan = { key, watchFull: Math.random() < 0.5, watchedSeconds: 0,
        skipAfterSeconds: null, commentAtSeconds: undefined,
        commentStarted: false, commentWindowClosed: false, finished: false };
      if (!plan.watchFull) plan.skipAfterSeconds = 2 + Math.random() * 3;
      if (watchPlans.size >= 256) watchPlans.delete(watchPlans.keys().next().value);
      watchPlans.set(key, plan);
    }
    if (Number.isFinite(video.duration) && video.duration > 0) {
      if (!plan.watchFull) {
        plan.skipAfterSeconds = Math.min(plan.skipAfterSeconds, video.duration * 0.5);
      } else if (plan.commentAtSeconds === undefined) {
        const boundary = video.duration * 0.7;
        const upper = Math.min(boundary, boundary - video.currentTime + plan.watchedSeconds);
        // A short/unknown clip has no valid 5s–70% comment window.
        // Leave one polling tick for scheduling jitter; publishing still
        // checks the actual 70% boundary before clicking the post button.
        plan.commentAtSeconds = upper >= 5.25 ? 5 + Math.random() * (upper - 5.25) : null;
      }
    }
    return plan;
  };
  const samplePlayback = () => {
    playbackWrapped = false;
    if (!activeVideo || !watchPlan ||
        (activeVideo.currentSrc || activeVideo.src) !== activeSource) return;
    const position = activeVideo.currentTime;
    const duration = activeVideo.duration;
    playbackWrapped = !activeVideo.seeking && Number.isFinite(duration) && duration > 0 &&
      lastTime >= Math.max(0, duration - 0.5) &&
      lastTime > position + 0.5 && position < 0.5;
    if (playbackWrapped || activeVideo.ended) watchPlan.finished = true;
    // Buffering/pausing does not consume the viewing or commenting delay.
    if (!activeVideo.seeking && (!activeVideo.paused || activeVideo.ended) && position > lastTime) {
      watchPlan.watchedSeconds += position - lastTime;
    }
    lastTime = position;
  };
  const commentWindowExpired = (attempt) => {
    const upper = attempt.element.duration * 0.7;
    return !Number.isFinite(upper) || upper < 5 ||
      attempt.plan.watchedSeconds > upper || attempt.element.currentTime > upper;
  };
  // Prepare the editor shortly before the sampled send time. Publishing is
  // gated separately so native input latency cannot cause an early comment.
  const startComment = (element) => {
    if (!comments.length || comment || !watchPlan?.watchFull ||
        watchPlan.commentStarted || watchPlan.commentWindowClosed ||
        !Number.isFinite(watchPlan.commentAtSeconds)) return !!comment;
    const key = postKey(element);
    if (attemptedPosts.has(key)) return false;
    if (commentWindowExpired({element, plan: watchPlan})) {
      watchPlan.commentWindowClosed = true;
      return false;
    }
    if (watchPlan.watchedSeconds < Math.max(0, watchPlan.commentAtSeconds - 2)) return false;
    watchPlan.commentStarted = true;
    const root = postRoot(element);
    const control = root.querySelector('[data-e2e="comment-icon"]');
    const action = control?.querySelector('button') || control;
    if (!action || action.disabled || action.getAttribute('aria-disabled') === 'true') {
      failComment('comments-unavailable');
      return;
    }
    if (loginRequired()) { failComment('login-required'); return; }
    const existingEditor = findEditor();
    if (existingEditor && editorText(existingEditor)) {
      failComment('comment-draft-exists');
      return;
    }
    comment = {
      element, root, source: element.currentSrc || element.src || '', key, plan: watchPlan,
      text: randomComment(), stage: 'opening',
      at: Date.now(), deadlineAt: Date.now() + 60000,
      openRetryReadyAt: Date.now() + 500,
      editor: null, panel: null, openedPanel: !existingEditor,
      panelLayout: null, pasteAttempted: false, openRetried: false, control,
      loopHeld: element.tagName === 'VIDEO'
    };
    // Keep playback active while editing the comment.
    // Hold this item through a short-video wrap while its request is pending.
    if (comment.loopHeld) element.loop = true;
    if (!existingEditor) {
      action.click();
    }
    return true;
  };
  const handleCommentResponse = (url, body) => {
    if (!running || !comment || comment.stage !== 'submitted') return;
    let path;
    try { path = new URL(url, location.href).pathname; } catch (_) { return; }
    if (!/\/comment\/(?:publish|post|create)\/?$/.test(path)) return;
    if (body?.status_code === 0 && body.comment?.text === comment.text &&
        body.comment?.cid) {
      comment.stage = 'confirmed';
    } else {
      // Never repeat a submission whose outcome is uncertain.
      failComment();
    }
  };
  // Observe the normal page request; use TikTok's editor and submit handler.
  // A cleared input alone is not proof that the server saved the comment.
  const originalFetch = window.fetch;
  const observedFetch = function(...args) {
    const response = originalFetch.apply(this, args);
    const url = args[0]?.url || args[0];
    if (String(url).includes('/comment/')) {
      response.then((result) => result.clone().json().then(
        (body) => handleCommentResponse(url, body)
      )).catch(() => {});
    }
    return response;
  };
  if (originalFetch) window.fetch = observedFetch;
  const xhrPrototype = window.XMLHttpRequest?.prototype;
  const originalOpen = xhrPrototype?.open;
  const observedOpen = function(method, url, ...args) {
    if (String(url).includes('/comment/')) {
      this.addEventListener('load', () => {
        try {
          handleCommentResponse(url, this.responseType === 'json'
            ? this.response : JSON.parse(this.responseText));
        } catch (_) {}
      }, { once: true });
    }
    return originalOpen.call(this, method, url, ...args);
  };
  if (xhrPrototype) xhrPrototype.open = observedOpen;
  const pasteComment = (editor) => {
    if (comment.pasteAttempted) { failComment('comment-paste-failed'); return; }
    const attempt = comment;
    attempt.pasteAttempted = true;
    attempt.stage = 'pasting';
    exposePanel(editor);
    editor.focus();
    if (editor.getAttribute('contenteditable') === 'true') {
      const range = document.createRange();
      range.selectNodeContents(editor);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    } else {
      editor.select();
    }
    const request = window.gecko_bridge?.callHandler(
      'FlutterCommentPaste', attempt.text
    );
    if (!request?.then) { failComment('comment-paste-failed'); return; }
    request.then((pasted) => {
      if (!running || comment !== attempt) return;
      if (pasted !== true) { failComment('comment-paste-failed'); return; }
      attempt.stage = 'paste-verify';
      attempt.at = Date.now();
    }).catch(() => {
      if (running && comment === attempt) failComment('comment-paste-failed');
    });
  };
  const processComment = () => {
    if (loginRequired()) { failComment('login-required'); return; }
    if (findActiveCard() && findActiveCard() !== comment.root ||
        (comment.element.currentSrc || comment.element.src || '') !== comment.source) {
      failComment('comment-post-changed');
      return;
    }
    if (comment.stage !== 'submitted' && comment.stage !== 'confirmed' &&
        commentWindowExpired(comment)) {
      comment.plan.commentWindowClosed = true;
      if (comment.pasteAttempted) {
        // Preserve an unfinished native draft; never publish it outside the window.
        failComment('comment-window-expired');
      } else {
        restorePanel(comment);
        comment = null;
        if (activeVideo) activeVideo.loop = false;
      }
      return;
    }
    // Delayed actions require a larger end-to-end budget than the old 15s.
    if (Date.now() >= comment.deadlineAt) { failComment(); return; }
    if (comment.stage === 'opening') {
      const editor = findEditor();
      if (!editor) {
        if (!comment.openRetried && Date.now() >= comment.openRetryReadyAt &&
            comment.control.getAttribute('role') === 'button') {
          comment.openRetried = true;
          comment.control.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Enter', code: 'Enter', bubbles: true, cancelable: true
          }));
        }
        return;
      }
      if (editorText(editor)) { failComment('comment-draft-exists'); return; }
      comment.editor = editor;
      comment.panel = editor.closest(panelSelector) || editor.parentElement;
      pasteComment(editor);
      return;
    }
    if (comment.stage === 'paste-verify') {
      const editor = findEditor();
      // React can replace the editor while handling an input/viewport update.
      if (!editor) return;
      if (editorText(editor) !== comment.text) {
        if (Date.now() - comment.at >= 2000) failComment('comment-paste-failed');
        return;
      }
      comment.editor = editor;
      comment.panel = editor.closest(panelSelector) || editor.parentElement;
      const submit = comment.panel.querySelector('[data-e2e="comment-post"]');
      if (!submit || submit.disabled || submit.getAttribute('aria-disabled') === 'true') {
        return;
      }
      if (comment.plan.watchedSeconds < comment.plan.commentAtSeconds) return;
      attemptedPosts.add(comment.key);
      commentAttemptCount++;
      comment.stage = 'submitted';
      comment.at = Date.now();
      comment.deadlineAt = Date.now() + 15000;
      submit.click();
      return;
    }
    if (comment.stage === 'confirmed') {
      const finished = comment;
      comment = null;
      window.gecko_bridge?.callHandler(
        'FlutterAutoWatch', 'comment-sent'
      )?.catch(() => {});
      finished.editor.blur();
      if (finished.openedPanel) {
        finished.panel.querySelector('button[aria-label="exit"], ' +
          '[data-e2e="comment-close"], button[aria-label="Close"]')?.click();
      }
      restorePanel(finished);
      if (finished.loopHeld) finished.element.loop = false;
    }
  };
  const advance = (element) => {
    if (pendingAdvance) return;
    if (!running) return;
    pendingAdvance = {
      element, card: element.closest('article') || element,
      video: activeVideo, source: activeSource,
      at: Date.now(), attempt: 0, navigationStarted: false,
      retryReadyAt: null
    };
    if (!comment) beginNavigation();
  };
  const beginNavigation = () => {
    pendingAdvance.navigationStarted = true;
    pendingAdvance.at = Date.now();
    pendingAdvance.retryReadyAt = Date.now() + actionDelayMs();
    goToNextVideo(pendingAdvance.element);
  };
  const finishVideo = () => {
    if (captchaVisible()) {
      resetPlaybackSample();
      return;
    }
    if (running && !document.hidden && dismissLiveInvite()) {
      resetPlaybackSample();
      return;
    }
    if (!activeVideo || completed || document.hidden ||
        findActiveVideo() !== activeVideo ||
        (activeVideo.currentSrc || activeVideo.src) !== activeSource) return;
    samplePlayback();
    completed = true;
    advance(activeVideo);
  };
  const detach = () => {
    if (!activeVideo) return;
    activeVideo.removeEventListener('ended', finishVideo);
    activeVideo.removeEventListener('seeking', resetPlaybackSample);
    activeVideo.removeEventListener('seeked', resetPlaybackSample);
    activeVideo.loop = originalLoop;
    activeVideo = null;
    watchPlan = null;
  };
  const resetPlaybackSample = () => {
    if (activeVideo) lastTime = activeVideo.currentTime;
  };
  const tick = () => {
    if (!running || document.hidden) return;
    if (captchaVisible()) {
      resetPlaybackSample();
      return;
    }
    if (dismissLiveInvite()) {
      resetPlaybackSample();
      return;
    }
    samplePlayback();
    if (comment) {
      processComment();
      if (!running || comment) return;
    }
    // Keep inline playback on the actual video element; the
    // Flutter allowsInlineMediaPlayback setting alone is insufficient.
    for (const candidate of document.querySelectorAll('video')) {
      candidate.playsInline = true;
      candidate.setAttribute('playsinline', '');
      candidate.setAttribute('webkit-playsinline', '');
    }
    const video = findActiveVideo();
    const source = video ? (video.currentSrc || video.src) : '';
    const card = findActiveCard();
    if (pendingAdvance) {
      const changedCard = card && card !== pendingAdvance.card;
      const changedVideo = video && (video !== pendingAdvance.video ||
        source !== pendingAdvance.source);
      if (changedCard || changedVideo) {
        pendingAdvance = null;
      } else {
        if (!pendingAdvance.navigationStarted) {
          beginNavigation();
          return;
        }
        // A click or smooth scroll can be ignored. Confirm a new item before
        // declaring success, then retry using a different navigation method.
        if (pendingAdvance.retryReadyAt != null &&
            Date.now() >= pendingAdvance.retryReadyAt && pendingAdvance.attempt < 3) {
          pendingAdvance.at = Date.now();
          pendingAdvance.retryReadyAt = Date.now() + actionDelayMs();
          goToNextVideo(pendingAdvance.element, ++pendingAdvance.attempt);
        }
        return;
      }
    }
    if (!video && card?.querySelector('.swiper-slide img, [class*="PhotoPlayerContainer"]')) {
      if (photoCard !== card) {
        photoCard = card;
        photoStartedAt = Date.now();
      } else if (Date.now() - photoStartedAt >= 5000) {
        advance(card);
      }
    } else {
      photoCard = null;
    }
    if (video !== activeVideo || source !== activeSource) {
      detach();
      activeVideo = video;
      activeSource = source;
      completed = false;
      if (!video) return;
      originalLoop = video.loop;
      watchPlan = planFor(video);
      lastTime = video.currentTime;
      video.loop = false;
      video.addEventListener('ended', finishVideo);
      video.addEventListener('seeking', resetPlaybackSample);
      video.addEventListener('seeked', resetPlaybackSample);
      if (video.paused && !video.ended) {
        // Autoplay restrictions must not produce unhandled promise errors.
        const playback = video.play();
        playback?.catch(() => {});
      }
    }
    if (!video || completed) return;
    video.loop = false;
    watchPlan = planFor(video);
    if (!watchPlan.watchFull && watchPlan.watchedSeconds >= watchPlan.skipAfterSeconds) {
      completed = true;
      advance(video);
      return;
    }
    if (!video.paused && video.currentTime > 0) {
      startComment(video);
      if (!running || comment) return;
    }
    // Some players restart playback themselves rather than emitting ended.
    // Only count a wrap after observing the end of a finite video.
    if (video.ended || playbackWrapped || watchPlan.finished) finishVideo();
    lastTime = video.currentTime;
  };
  const timer = setInterval(tick, 250);
  window.__flutterAutoWatch = {
    canPasteComment(text) {
      return running && !document.hidden && !captchaVisible() && comment?.stage === 'pasting' &&
        comment.text === text && document.activeElement === findEditor() &&
        (comment.element.currentSrc || comment.element.src || '') === comment.source &&
        (!findActiveCard() || findActiveCard() === comment.root);
    },
    getStatus() {
      return {
        completed,
        commentAttemptCount,
        commentStage: comment?.stage || null,
        watchMode: watchPlan ? (watchPlan.watchFull ? 'full' : 'skip') : null,
        watchedSeconds: watchPlan?.watchedSeconds || 0,
        skipAfterSeconds: watchPlan?.skipAfterSeconds ?? null,
        commentAtSeconds: watchPlan?.commentAtSeconds ?? null,
        messages: Array.from(reportedMessages)
      };
    },
    stop() {
      window.__flutterAutoWatchLastStatus = this.getStatus();
      running = false;
      clearInterval(timer);
      if (window.fetch === observedFetch) window.fetch = originalFetch;
      if (xhrPrototype?.open === observedOpen) xhrPrototype.open = originalOpen;
      restorePanel(comment);
      // Cancel any pending paste or submission.
      comment = null;
      pendingAdvance = null;
      detach();
      delete window.__flutterAutoWatch;
    }
  };
  tick();
  return true;
})();
''';
const String autoWatchStopScript = r'''
(() => {
  window.__flutterAutoWatch?.stop();
})();
''';
