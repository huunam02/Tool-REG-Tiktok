/// Reads images and CSS geometry only; Android Accessibility performs the drag.
/// V1/V2 selector references: SadCaptcha's official client selectors.py.
const readRotateCaptchaScript = r'''
(() => {
  if (location.origin !== 'https://www.tiktok.com' || document.hidden) return null;
  const visible = el => {
    if (!el) return false;
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    for (let parent = el; parent; parent = parent.parentElement) {
      const style = getComputedStyle(parent);
      if (style.display === 'none' || style.visibility === 'hidden' ||
          Number(style.opacity) === 0) return false;
    }
    return r.width > 0 && r.height > 0 && s.display !== 'none' &&
      s.visibility !== 'hidden' && Number(s.opacity) !== 0;
  };
  const first = (root, selector) => [...root.querySelectorAll(selector)].find(visible);
  const roots = '#captcha-verify-container, .captcha-verify-container, ' +
    '.captcha-disable-scroll, .captcha_verify_container, #captcha_container, [role="dialog"]';
  const layouts = [
    {
      bars: '.captcha_verify_slide--slidebar',
      inner: 'img.captcha_verify_img_inner, img[data-testid="whirl-inner-img"]',
      outer: 'img.captcha_verify_img_outer, img[data-testid="whirl-outer-img"]',
      handle: '.secsdk-captcha-drag-icon'
    },
    {
      bars: '.captcha-verify-container > div > div > div.cap-w-full > div.cap-rounded-full',
      inner: ':scope > div > div > div > img.cap-absolute',
      outer: ':scope > div > div > div > img:first-child',
      handle: 'div[draggable="true"]'
    }
  ];
  for (const layout of layouts) {
    for (const bar of [...document.querySelectorAll(layout.bars)].filter(visible)) {
      const root = bar.closest(roots) || document;
      const outer = first(root, layout.outer), inner = first(root, layout.inner);
      // The handle must belong to this track, never the video behind the modal.
      const icon = first(bar, layout.handle);
      if (outer === inner || !outer?.complete || !inner?.complete ||
          !outer.naturalWidth || !inner.naturalWidth || !icon) continue;
      const b = bar.getBoundingClientRect(), i = icon.getBoundingClientRect();
      const v = window.visualViewport;
      const width = v?.width || innerWidth, height = v?.height || innerHeight;
      const ox = v?.offsetLeft || 0, oy = v?.offsetTop || 0;
      // getBoundingClientRect includes the desktop modal's CSS transforms.
      // Require the handle to be at the beginning and the full track visible.
      if (Math.abs(i.left - b.left) > 8 || i.top < b.top || i.bottom > b.bottom ||
          i.left < b.left || i.right > b.right ||
          b.left < ox || b.right > ox + width || i.top < oy || i.bottom > oy + height ||
          b.width <= i.width) continue;
      return JSON.stringify({
        outer: outer.currentSrc || outer.src, inner: inner.currentSrc || inner.src,
        viewportWidth: width, viewportHeight: height,
        x: i.left + i.width / 2 - ox, y: i.top + i.height / 2 - oy,
        travel: b.width - i.width
      });
    }
  }
  return null;
})()
''';

const rotateCaptchaPresentScript = r'''
(() => {
  if (location.origin !== 'https://www.tiktok.com' || document.hidden) return null;
  const visible = el => {
    const r = el.getBoundingClientRect();
    const v = window.visualViewport;
    const left = v?.offsetLeft || 0, top = v?.offsetTop || 0;
    if (r.width <= 0 || r.height <= 0 || r.right <= left || r.bottom <= top ||
        r.left >= left + (v?.width || innerWidth) ||
        r.top >= top + (v?.height || innerHeight)) return false;
    for (let parent = el; parent; parent = parent.parentElement) {
      const s = getComputedStyle(parent);
      if (s.display === 'none' || s.visibility === 'hidden' ||
          Number(s.opacity) === 0) return false;
    }
    return true;
  };
  // Scroll locking classes and empty/stale modal containers are not puzzles.
  const controls = '.captcha_verify_slide--slidebar, iframe[src*="captcha"]';
  if ([...document.querySelectorAll(controls)].some(visible)) return true;
  return [...document.querySelectorAll('#captcha-verify-container, .captcha-verify-container, .captcha_verify_container, #captcha_container')]
    .some(root => visible(root) && [...root.querySelectorAll(
      'img, canvas, [role="slider"], [draggable="true"]'
    )].some(visible));
})()
''';

/// Geometry of the puzzle's refresh control (CSS pixels); Android
/// Accessibility performs the tap.
const rotateCaptchaRefreshScript = r'''
(() => {
  if (location.origin !== 'https://www.tiktok.com' || document.hidden) return null;
  const visible = el => {
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.display !== 'none' &&
      s.visibility !== 'hidden' && Number(s.opacity) !== 0;
  };
  const root = [...document.querySelectorAll('#captcha-verify-container, ' +
    '.captcha-verify-container, .captcha_verify_container, #captcha_container')]
    .find(visible);
  if (!root) return null;
  const el = [...root.querySelectorAll('.secsdk_captcha_refresh, ' +
    '#captcha_refresh_button, [aria-label*="refresh" i], [title*="refresh" i], ' +
    '[aria-label*="reload" i], [title*="reload" i]')].find(visible);
  if (!el) return null;
  const r = el.getBoundingClientRect(), v = window.visualViewport;
  return JSON.stringify({
    viewportWidth: v?.width || innerWidth,
    viewportHeight: v?.height || innerHeight,
    x: r.left + r.width / 2 - (v?.offsetLeft || 0),
    y: r.top + r.height / 2 - (v?.offsetTop || 0)
  });
})()
''';
