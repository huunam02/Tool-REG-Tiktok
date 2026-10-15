// Used only before an account form opens. Submission and OTP keep their own
// one-shot guards; opening a dialog can be retried if Home was not ready.
const String openHomeAccountModalScript = r'''
(state, visible, enabled, find) => {
  const now = Date.now();
  const retryDelay = 15000;
  const home = state.homeInteraction ||= {
    video: null, startedAt: now,
    likeAttempts: 0, lastLikeAt: null,
    accountAttempts: 0, lastAccountAt: null,
  };
  const canClick = control => {
    if (!enabled(control)) return false;
    if (!document.elementFromPoint || !control.getBoundingClientRect) return true;
    const rect = control.getBoundingClientRect();
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    if (rect.width <= 0 || rect.height <= 0 ||
        x < 0 || y < 0 || x >= innerWidth || y >= innerHeight) return false;
    const hit = document.elementFromPoint(x, y);
    return !!hit && (hit === control || control.contains?.(hit));
  };

  // A new video or React node must not reset the wait after a click.
  if (home.lastLikeAt != null && now - home.lastLikeAt < retryDelay ||
      home.lastAccountAt != null && now - home.lastAccountAt < retryDelay) {
    return home.accountAttempts ? 'waiting-form' : 'waiting-login-modal';
  }

  if (!home.accountAttempts) {
    const videos = Array.from(document.querySelectorAll('video'))
      .filter(video => visible(video) && video.getBoundingClientRect().bottom > 0 &&
        video.getBoundingClientRect().top < innerHeight)
      .sort((a, b) => {
        const area = video => {
          const rect = video.getBoundingClientRect();
          return Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0)) *
            Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));
        };
        return area(b) - area(a);
      });
    const video = videos[0];
    if (video && home.likeAttempts < 3) {
      if (home.video !== video && !home.likeAttempts) {
        home.video = video;
        home.startedAt = now;
      }
      if (!home.likeAttempts) {
        if (video.paused) video.play?.().catch?.(() => {});
        const duration = Number(video.duration);
        const watched = video.ended ||
          Number.isFinite(duration) && duration > 0 &&
            video.currentTime >= Math.min(duration - 0.2, 8) ||
          now - home.startedAt >= 10000;
        if (!watched) return 'waiting-home-video';
      }
      const root = video.closest('article') || document;
      const candidates = Array.from(root.querySelectorAll(
        'button, [role="button"], [data-e2e*="like" i]'
      ));
      const label = control => ['aria-label', 'title', 'data-e2e']
        .map(name => control.getAttribute(name) || '').concat(control.textContent || '').join(' ');
      const isLike = control => /\blike\b|thích/i.test(label(control));
      const isLiked = control => control.getAttribute('aria-pressed') === 'true' ||
        /unlike|dislike|bỏ thích|đã thích/i.test(label(control));
      // Never toggle an already liked video while recovering the dialog.
      const alreadyLiked = candidates.some(control => visible(control) && isLike(control) && isLiked(control));
      const like = candidates.map(source => ({
        source, control: source.closest?.('button, [role="button"]') || source,
      })).find(({source, control}) => (isLike(source) || isLike(control)) &&
        !isLiked(source) && !isLiked(control) && canClick(control))?.control;
      if (!alreadyLiked && like) {
        home.likeAttempts++;
        home.lastLikeAt = now;
        like.click();
        return 'home-video-liked';
      }
      // Give a slow feed time to render its Like control before using Account.
      if (!home.likeAttempts && !alreadyLiked && now - home.startedAt < 15000) {
        return 'waiting-home-like';
      }
    }
  }

  // Account opens the same Login dialog without toggling the heart again.
  if (home.accountAttempts >= 3) return 'home-modal-failed';
  const account = find('[data-e2e="nav-profile"], [data-e2e="nav-account"], ' +
    '[data-e2e="account-icon"], a[href^="/profile"], ' +
    '[aria-label="Account"], [aria-label="Profile"], [aria-label="Tài khoản"], [aria-label="Hồ sơ"]') ||
    Array.from(document.querySelectorAll('a, button, [role="button"], [role="link"]'))
      .find(control => enabled(control) &&
        /^(account|profile|tài khoản|hồ sơ)$/i.test(control.textContent.trim()));
  if (account && canClick(account)) {
    home.accountAttempts++;
    home.lastAccountAt = now;
    account.click();
  }
  return 'waiting-form';
}
''';
