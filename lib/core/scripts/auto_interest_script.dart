/// Select three random interests in TikTok's onboarding dialog and continue.
const String autoSelectInterestScript = r'''
(() => {
  if (location.origin !== 'https://www.tiktok.com') return false;
  if (window.__flutterInterestSelection) {
    window.__flutterInterestSelection.check();
    return true;
  }

  const normalize = text => (text || '').replace(/\s+/g, ' ').trim();
  const visible = element => {
    const style = getComputedStyle(element);
    return element.isConnected && element.getClientRects().length > 0 &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      style.visibility !== 'collapse' && style.opacity !== '0';
  };
  const enabled = element => !element.disabled &&
    element.getAttribute('aria-disabled') !== 'true';
  const selected = element => element.classList.contains('selected') ||
    element.getAttribute('aria-checked') === 'true' ||
    element.getAttribute('aria-pressed') === 'true' ||
    element.getAttribute('data-selected') === 'true';
  const states = new WeakMap();
  let pending = null;
  const schedule = () => {
    if (pending !== null) return;
    pending = setTimeout(() => {
      pending = null;
      check();
    }, 300);
  };
  function check() {
    if (document.hidden) return;
    const modal = Array.from(document.querySelectorAll(
      '[class*="DivInterestSelectorContainer"], [role="dialog"], [aria-modal="true"]'
    )).find(root => visible(root) && Array.from(root.querySelectorAll(
      'h1, h2, h3, h4, span, div'
    )).some(heading => visible(heading) &&
      /^(what would you like to watch on tiktok\??|bạn muốn xem gì trên tiktok\??)$/i.test(
        normalize(heading.innerText || heading.textContent))));
    if (!modal) return;
    const button = Array.from(modal.querySelectorAll('button, [role="button"]'))
      .find(control => visible(control) &&
        /^(continue|tiếp tục)(\s*\(\s*\d+\s*\/\s*3\s*\))?$/i.test(
          normalize(control.innerText || control.textContent)));
    if (!button) return;
    let state = states.get(modal);
    if (!state) {
      state = { clicked: new WeakSet(), awaitingCount: null, submitted: false };
      states.set(modal, state);
    }
    if (state.submitted) return;
    const choices = Array.from(modal.querySelectorAll(
      '[class*="DivInterestItemContainer"], [data-e2e="interest-item"], ' +
      '[data-testid="interest-item"], [role="checkbox"], button[aria-pressed]'
    ));
    const countLabel = normalize(button.innerText || button.textContent)
      .match(/\(\s*(\d+)\s*\/\s*3\s*\)/);
    const count = Math.max(choices.filter(selected).length,
      countLabel ? Number(countLabel[1]) : 0);
    // React may update the selection and the counter in separate renders.
    // Wait for confirmation before clicking a different choice.
    if (state.awaitingCount !== null) {
      if (count <= state.awaitingCount) return;
      state.awaitingCount = null;
    }
    if (count === 3) {
      if (!enabled(button) || countLabel && Number(countLabel[1]) !== 3) return;
      state.submitted = true;
      button.click();
      return;
    }
    if (count > 3) return;
    const available = choices.filter(choice => visible(choice) && enabled(choice) &&
      !selected(choice) && !state.clicked.has(choice));
    if (available.length < 3 - count) return;
    const choice = available[Math.floor(Math.random() * available.length)];
    state.clicked.add(choice);
    state.awaitingCount = count;
    choice.click();
    schedule();
  }
  const observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {
    childList: true, subtree: true, characterData: true, attributes: true,
    attributeFilter: ['class', 'style', 'hidden', 'disabled', 'aria-disabled',
      'aria-checked', 'aria-pressed', 'data-selected'],
  });
  window.__flutterInterestSelection = { check };
  check();
  setInterval(check, 1000);
  return true;
})();
''';
