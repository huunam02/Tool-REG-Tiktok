import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

import 'nurture_coordinate_profile.dart';
import 'nurture_data.dart';
import 'signup_accessibility.dart';

/// `detail` is the search-result player: a modal with its own comment box.
enum NurtureVideoOrientation { portrait, landscape, detail }

/// Geometry comes from the playing video's accessible container, not the phone.
class NurtureVideo {
  NurtureVideo({
    required this.key,
    required this.position,
    required this.duration,
    required this.bounds,
    required this.comments,
    this.like,
    this.next,
    this.root = '',
    this.detail = false,
  });
  final String key;
  final int position, duration;
  final Rect bounds;

  /// The feed's "Read or add comments" button; null in the detail player,
  /// whose comment box is always open.
  final SignupNode? comments;

  /// The post's "Like video" toggle; null when it is not exposed.
  final SignupNode? like;
  final SignupNode? next;

  /// Accessibility id of the post's container; its text is content, never a
  /// system prompt.
  final String root;
  final bool detail;
  NurtureVideoOrientation get orientation => detail
      ? NurtureVideoOrientation.detail
      : bounds.width > bounds.height
      ? NurtureVideoOrientation.landscape
      : NurtureVideoOrientation.portrait;

  String layout(SignupViewport viewport) {
    final a = viewport.fromScreen(bounds.topLeft);
    final b = viewport.fromScreen(bounds.bottomRight);
    // A 4:5 portrait and a 9:16 portrait can also have different button rows.
    return '${orientation.name}/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}';
  }

  /// The exact like count, or null when TikTok rounds it (1.2K, 3.4M).
  /// Android WebView exposes no pressed state for the like toggle, so an
  /// exact count is the only sign that a like was accepted.
  int? get likeCount {
    final match = _likeCount.firstMatch(like?.label.trim() ?? '');
    return match == null ? null : int.parse(match[1]!.replaceAll(',', ''));
  }

  /// "Like video 35 likes" in the feed, "35 Likes" in the search player.
  static final _likeLabel = RegExp(
    r'^(Like video\b|[\d.,]+[KMB]? likes?$)',
    caseSensitive: false,
  );
  static final _likeCount = RegExp(
    r'^(?:Like video )?([\d,]+) likes?$',
    caseSensitive: false,
  );

  /// The single like toggle among [nodes]; ambiguous rows expose none.
  static SignupNode? _likeIn(Iterable<SignupNode> nodes) {
    final likes = nodes
        .where(
          (n) =>
              n.clickable &&
              n.enabled &&
              n.className.endsWith('ToggleButton') &&
              (_likeLabel.hasMatch(n.text.trim()) ||
                  _likeLabel.hasMatch(n.description.trim())),
        )
        .toList();
    return likes.length == 1 ? likes.single : null;
  }

  String likeKey(SignupViewport viewport) {
    final a = viewport.fromScreen(like!.bounds.topLeft);
    final b = viewport.fromScreen(like!.bounds.bottomRight);
    return '${layout(viewport)}/like/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}';
  }

  /// The action column shifts with optional rows (music disc, CapCut label)
  /// even when the media frame is identical, so the button's own geometry is
  /// part of the key.
  String commentsKey(SignupViewport viewport) {
    final a = viewport.fromScreen(comments!.bounds.topLeft);
    final b = viewport.fromScreen(comments!.bounds.bottomRight);
    return '${layout(viewport)}/open-comments/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}';
  }

  static final _time = RegExp(
    r'^(\d{1,2}:\d{2}(?::\d{2})?)\s*/\s*(\d{1,2}:\d{2}(?::\d{2})?)$',
  );
  static int _seconds(String value) =>
      value.split(':').fold(0, (sum, part) => sum * 60 + int.parse(part));

  static NurtureVideo? read(SignupSnapshot snapshot) {
    if (!snapshot.ready || !snapshot.viewport.valid) return null;
    final nodes = {for (final n in snapshot.nodes) n.id: n};
    final candidates = <NurtureVideo>[];
    for (final button in snapshot.nodes.where(
      (n) =>
          n.clickable &&
          n.enabled &&
          RegExp(
            r'^Read or add comments\b',
            caseSensitive: false,
          ).hasMatch(n.name),
    )) {
      final actionRoot = button.id.substring(0, button.id.lastIndexOf('.'));
      final card = actionRoot.substring(0, actionRoot.lastIndexOf('.'));
      final children = snapshot.nodes
          .where((n) => n.id.startsWith('$card.'))
          .toList();
      final times = children
          .where((n) => _time.hasMatch(n.text.trim()))
          .toList();
      if (times.length != 1) continue;
      final match = _time.firstMatch(times.single.text.trim())!;
      final duration = _seconds(match[2]!);
      final position = _seconds(match[1]!);
      if (duration <= 0 || position > duration) continue;
      Rect? media;
      var ancestor = times.single.id;
      while (ancestor.contains('.') && ancestor != card) {
        ancestor = ancestor.substring(0, ancestor.lastIndexOf('.'));
        final rect = nodes[ancestor]?.bounds;
        if (rect != null &&
            rect.width > snapshot.viewport.bounds.width * .15 &&
            rect.height > snapshot.viewport.bounds.height * .08 &&
            rect.right <= button.bounds.left + 3) {
          media = rect;
          break;
        }
      }
      if (media == null) continue; // Never guess orientation from a button Y.
      final author = nodes['$actionRoot.0.0']?.label.trim() ?? '';
      if (author.isEmpty) continue;
      final feed = card.substring(0, card.lastIndexOf('.'));
      final page = feed.contains('.')
          ? feed.substring(0, feed.lastIndexOf('.'))
          : '';
      final down = _pairedDown(nodes, page, media.right);
      candidates.add(
        NurtureVideo(
          // Music labels can disappear/reappear when the comment panel opens.
          // They describe the layout, not a change of the playing post.
          key: '$card|$author|$duration',
          position: position,
          duration: duration,
          bounds: media,
          comments: button,
          like: _likeIn(
            snapshot.nodes.where((n) => n.id.startsWith('$actionRoot.')),
          ),
          next: down,
          root: card,
        ),
      );
    }
    // The search-result player is a modal over the page; it wins when open.
    final detail = _readDetail(snapshot, nodes);
    if (detail != null) return detail;
    // Multiple exposed posts are ambiguous; don't comment on a guessed card.
    return candidates.length == 1 ? candidates.single : null;
  }

  /// The panel shows the post link; the snapshot masks its `@handle` part
  /// like an email, so only the numeric video id identifies the post.
  static final _videoUrl = RegExp(r'^https:\S*/video/(\d{6,})');

  /// The player opened from search results. Accessibility ids under the
  /// modal shift when focus enters it, so the post is keyed by its URL.
  static NurtureVideo? _readDetail(
    SignupSnapshot snapshot,
    Map<String, SignupNode> nodes,
  ) {
    for (final dialog in snapshot.nodes.where(
      (n) => n.className.endsWith('Dialog'),
    )) {
      final inside = snapshot.nodes
          .where((n) => n.id.startsWith('${dialog.id}.'))
          .toList();
      final times = inside.where((n) => _time.hasMatch(n.text.trim()));
      if (times.length != 1) continue;
      final url = inside
          .map((n) => _videoUrl.firstMatch(n.text.trim())?.group(1))
          .nonNulls
          .toSet();
      if (url.length != 1) continue;
      final match = _time.firstMatch(times.single.text.trim())!;
      final duration = _seconds(match[2]!);
      final position = _seconds(match[1]!);
      if (duration <= 0 || position > duration) continue;
      final pane = times.single.id
          .substring(dialog.id.length + 1)
          .split('.')
          .first;
      final media = nodes['${dialog.id}.$pane']?.bounds;
      if (media == null) continue;
      final next = inside
          .where(
            (n) => n.clickable && n.enabled && n.name == 'Go to next video',
          )
          .firstOrNull;
      return NurtureVideo(
        key: 'detail|${url.single}|$duration',
        position: position,
        duration: duration,
        bounds: media,
        comments: null,
        like: _likeIn(inside),
        next: next,
        root: dialog.id,
        detail: true,
      );
    }
    return null;
  }

  /// The search-result player's "Go to next video" button, read without the
  /// clock so a post that never starts can still be skipped.
  static SignupNode? playerNext(SignupSnapshot snapshot) {
    for (final dialog in snapshot.nodes.where(
      (n) => n.className.endsWith('Dialog'),
    )) {
      final next = snapshot.nodes
          .where(
            (n) =>
                n.id.startsWith('${dialog.id}.') &&
                n.clickable &&
                n.enabled &&
                n.name == 'Go to next video',
          )
          .firstOrNull;
      if (next != null) return next;
    }
    return null;
  }

  /// The feed's unlabeled up/down pair beside the cards.
  static SignupNode? _pairedDown(
    Map<String, SignupNode> nodes,
    String page,
    double right,
  ) {
    final up = nodes['$page.1.0.0.0'];
    final down = nodes['$page.1.0.1.0'];
    final paired =
        up != null &&
        down != null &&
        up.className.endsWith('Button') &&
        down.className.endsWith('Button') &&
        up.clickable &&
        down.clickable &&
        down.enabled &&
        up.label.isEmpty &&
        down.label.isEmpty &&
        (up.bounds.width - down.bounds.width).abs() <= 2 &&
        (up.bounds.center.dx - down.bounds.center.dx).abs() <= 2 &&
        up.bounds.bottom < down.bounds.top &&
        down.bounds.left > right;
    return paired ? down : null;
  }

  /// A LIVE post in the feed has no playback clock or comment button, so it
  /// is never watched; this returns the feed's next button to skip it.
  static SignupNode? liveNext(SignupSnapshot snapshot) {
    if (!snapshot.ready || !snapshot.viewport.valid) return null;
    final nodes = {for (final n in snapshot.nodes) n.id: n};
    // Badge, preview and the "Join my LIVE" overlay all name the post LIVE.
    final live = RegExp(
      r'^(LIVE\b|Watch LIVE|Click to watch LIVE|Join my LIVE)',
    );
    final badges = snapshot.nodes.where(
      (n) => !n.editable && live.hasMatch(n.text.trim()),
    );
    for (final badge in badges) {
      var page = badge.id;
      while (page.contains('.')) {
        page = page.substring(0, page.lastIndexOf('.'));
        final down = _pairedDown(nodes, page, badge.bounds.right);
        if (down != null) return down;
      }
    }
    return null;
  }
}

class NurtureCancelled implements Exception {}

class _CommentNotReady implements Exception {
  const _CommentNotReady(this.message);
  final String message;
}

class _LikeSkipped implements Exception {
  const _LikeSkipped(this.message);
  final String message;
}

class _WatchPlan {
  _WatchPlan(this.full, this.skipAt, this.commentAt, this.cap, this.likeAt);
  final bool full;
  final int skipAt, commentAt;

  /// Playback second at which the post is liked; -1 never likes it.
  final int likeAt;

  /// Seconds a full watch lasts on a long video; null watches to the end.
  final int? cap;
  int watched = 0;
  bool completed = false, commentAttempted = false, likeAttempted = false;
}

/// No DOM, JS, keyboard channel or ADB input. All UI uses Accessibility.
class NurtureAccessibilityRunner {
  NurtureAccessibilityRunner({
    required this.accessibility,
    required this.profile,
    required this.comments,
    required this.isActive,
    required this.isTikTok,
    required this.onProgress,
    this.onComment,
    this.onCommentSkipped,
    this.onLike,
    this.onLikeSkipped,
    this.likeRate = defaultLikeRate,
    this.commentRate = defaultCommentRate,
    this.longWatchRate = defaultLongWatchRate,
    this.searchKeyword,
    Random? random,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now,
       _delay = delay;

  final SignupAccessibility accessibility;
  final NurtureCoordinateProfile profile;
  final List<String> comments;
  final bool Function() isActive;
  final Future<bool> Function() isTikTok;
  final Future<void> Function(NurtureTotals, int) onProgress;
  final void Function()? onComment;
  final void Function(String)? onCommentSkipped;
  final void Function()? onLike;
  final void Function(String)? onLikeSkipped;

  /// Share of posts that are liked (0–1). A liked post is watched in full.
  final double likeRate;
  static const defaultLikeRate = .3;

  /// Share of posts that get a comment (0–1). A commented post is watched in
  /// full.
  final double commentRate;
  static const defaultCommentRate = .2;

  /// Share of the other posts watched in full (up to a minute) instead of
  /// being swiped after a few seconds (0–1).
  final double longWatchRate;
  static const defaultLongWatchRate = .5;

  /// Search-mode nurture: the keyword is entered and submitted through
  /// Accessibility, then a result from the Videos tab is watched. Null or
  /// empty watches the For You feed.
  final String? searchKeyword;
  final Random _random;
  final DateTime Function() _now;
  final Future<void> Function(Duration)? _delay;
  Timer? _sleepTimer;
  Completer<void>? _sleepCompleter;
  final _plans = <String, _WatchPlan>{};
  int _sequence = 0, _watchMs = 0, _full = 0, _skipped = 0, _comments = 0;
  int _likes = 0;
  int _lastComment = -1;
  bool _cancelled = false, _running = false;
  NurtureVideo? _previous;
  DateTime? _sampledAt;
  Future<void>? _done;
  NurtureTotals get totals => NurtureTotals(
    watchMilliseconds: _watchMs,
    videos: _full + _skipped,
    fullVideos: _full,
    skippedVideos: _skipped,
    comments: _comments,
    likes: _likes,
  );

  /// Seconds a full watch lasts on a long video.
  static const _maxWatchSeconds = 60;

  /// Latest playback second at which a comment starts.
  static const _latestCommentSeconds = 20;

  /// How long a CAPTCHA may stay open while the monitor solves it.
  static const _captchaWait = Duration(seconds: 60);

  /// Latest playback second at which a like is given.
  static const _latestLikeSeconds = 10;

  static bool authenticated(SignupSnapshot s) =>
      s.ready &&
      s.contains(RegExp(r'^(Messages|Tin nhắn)$', caseSensitive: false)) &&
      s.contains(RegExp(r'^(Profile|Hồ sơ)$', caseSensitive: false)) &&
      !s.contains(
        RegExp(
          r'^(Log in( to TikTok)?|Login|Đăng nhập( TikTok)?)$',
          caseSensitive: false,
        ),
      );

  Future<void> start() {
    if (_running) return _done!;
    _running = true;
    _cancelled = false;
    _previous = null;
    _sampledAt = null; // A background gap is never playback time.
    return _done = _run().whenComplete(() => _running = false);
  }

  void cancel() {
    _cancelled = true;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final sleeper = _sleepCompleter;
    _sleepCompleter = null;
    if (sleeper != null && !sleeper.isCompleted) sleeper.complete();
  }

  Future<void> stop() async {
    cancel();
    await accessibility.cancelPaste();
    try {
      await _done;
    } catch (_) {
      /* Reported by start's owner. */
    }
  }

  void _check() {
    if (_cancelled || !isActive()) throw NurtureCancelled();
  }

  Future<void> _sleep([int milliseconds = 400]) async {
    for (var left = milliseconds; left > 0; left -= 200) {
      _check();
      final duration = Duration(milliseconds: min(left, 200));
      if (_delay != null) {
        await _delay(duration);
      } else {
        final sleeper = _sleepCompleter = Completer<void>();
        _sleepTimer = Timer(duration, () {
          _sleepTimer = null;
          _sleepCompleter = null;
          if (!sleeper.isCompleted) sleeper.complete();
        });
        await sleeper.future;
      }
    }
    _check();
  }

  _WatchPlan _plan(NurtureVideo video) => _plans.putIfAbsent(video.key, () {
    // Videos longer than a minute are watched for one minute only.
    final cap = video.duration > _maxWatchSeconds ? _maxWatchSeconds : null;
    final watch = min(video.duration, cap ?? video.duration);
    final like =
        video.like != null && watch >= 4 && _random.nextDouble() < likeRate;
    // Comment early in the (short) watch: from 3s to half of it, at most 20s.
    final latest = min((watch * .5).floor(), _latestCommentSeconds);
    final comment =
        latest >= 3 &&
        comments.isNotEmpty &&
        _random.nextDouble() < commentRate;
    // A liked or commented post is watched in full.
    final full = like || comment || _random.nextDouble() < longWatchRate;
    final likeLatest = min(watch ~/ 2, _latestLikeSeconds);
    final likeAt = like ? 2 + _random.nextInt(likeLatest - 1) : -1;
    final commentAt = comment ? 3 + _random.nextInt(latest - 2) : -1;
    return _WatchPlan(
      full,
      min(2 + _random.nextInt(4), max(1, video.duration ~/ 2)),
      commentAt,
      cap,
      likeAt,
    );
  });

  Future<void> _emit() => onProgress(totals, ++_sequence);

  Future<SignupSnapshot> _snapshot() async {
    _check();
    if (!await isTikTok()) {
      throw StateError('Đã rời TikTok; dừng nuôi tài khoản.');
    }
    _check();
    var s = await accessibility.snapshot();
    // The WebView node is briefly missing while Flutter rebuilds semantics
    // (button state, snackbar). Only a persistent absence stops nurture.
    final until = _now().add(const Duration(seconds: 3));
    while ((!s.ready || !s.viewport.valid) && _now().isBefore(until)) {
      await _sleep(200);
      s = await accessibility.snapshot();
    }
    _check();
    if (!s.ready || !s.viewport.valid) {
      throw StateError('Khung nuôi cần cố định 400×800.');
    }
    // Hover cards and popovers can expose a Dialog briefly and close by
    // themselves. Nothing is tapped while one is open; only a dialog that
    // persists stops nurture.
    final dialogUntil = _now().add(const Duration(seconds: 10));
    final captchaUntil = _now().add(_captchaWait);
    while (true) {
      final prompts = _prompts(s);
      bool hasPrompt(RegExp pattern) => prompts.any(
        (n) => [n.text, n.description, n.hint].any(pattern.hasMatch),
      );
      // Verification and sign-out stop immediately, even inside a dialog.
      if (hasPrompt(
        RegExp(
          r'captcha|drag.*slider|verify to continue|kéo.*thanh trượt',
          caseSensitive: false,
        ),
      )) {
        // The CAPTCHA monitor solves it through the API meanwhile; nothing
        // is tapped until it closes.
        if (!_now().isBefore(captchaUntil)) {
          throw StateError(
            'TikTok yêu cầu xác minh; đã dừng nuôi để bạn xử lý.',
          );
        }
        await _sleep(1000);
        final next = await accessibility.snapshot();
        _check();
        if (next.ready && next.viewport.valid) s = next;
        continue;
      }
      if (hasPrompt(RegExp(r'^Log in to TikTok$', caseSensitive: false))) {
        throw StateError('TikTok yêu cầu đăng nhập lại; đã dừng nuôi.');
      }
      final dialogs = prompts
          .where((n) => n.className.endsWith('Dialog'))
          .toList();
      if (dialogs.isEmpty) break;
      if (!_now().isBefore(dialogUntil)) {
        final root = dialogs.first.id;
        final text = s.nodes
            .where((n) => n.id == root || n.id.startsWith('$root.'))
            .map((n) => n.label.trim())
            .where((label) => label.isNotEmpty)
            .join(' · ');
        final detail = text.isEmpty
            ? ''
            : ' (${text.length > 80 ? '${text.substring(0, 80)}…' : text})';
        throw StateError('TikTok đang mở hộp thoại$detail; đã dừng nuôi.');
      }
      await _sleep(500);
      final next = await accessibility.snapshot();
      _check();
      if (next.ready && next.viewport.valid) s = next;
    }
    final current = NurtureVideo.read(s);
    final previous = _previous;
    final sampledAt = _sampledAt;
    final now = _now();
    if (current != null &&
        previous != null &&
        previous.key == current.key &&
        sampledAt != null) {
      final wrapped =
          previous.position >= current.duration - 2 &&
          current.position <= 2 &&
          previous.position > current.position;
      final delta = wrapped
          ? current.duration - previous.position + current.position
          : current.position - previous.position;
      final elapsed = now.difference(sampledAt).inMilliseconds;
      // Whole-second accessibility clock: ignore seeks and stalled playback.
      if (delta > 0 && delta * 1000 <= elapsed + 1250 && elapsed <= 3000) {
        _watchMs += delta * 1000;
        final plan = _plan(current)..watched += delta;
        if (plan.full &&
            !plan.completed &&
            (wrapped || current.position == current.duration) &&
            plan.watched >= current.duration - 1) {
          plan.completed = true;
          _full++;
        }
        await _emit();
      }
    }
    _previous = current;
    _sampledAt = now;
    return s;
  }

  /// Nodes outside the playing card and the comment panel. Video captions
  /// and public comments are content, never system prompts.
  List<SignupNode> _prompts(SignupSnapshot s) {
    final current = NurtureVideo.read(s);
    final editor = _editor(s);
    final close = _close(s);
    String? panelRoot;
    if (editor != null && close != null) {
      final a = editor.id.split('.'), b = close.id.split('.');
      var common = 0;
      while (common < min(a.length, b.length) && a[common] == b[common]) {
        common++;
      }
      if (common > 0) panelRoot = a.take(common).join('.');
    }
    final cardRoot = current?.root;
    bool within(String id, String? root) =>
        root != null && (id == root || id.startsWith('$root.'));
    // The search-result player is itself a Dialog; while its clock is hidden
    // it is still recognised by its next button or post URL.
    final players = s.nodes
        .where((n) => n.className.endsWith('Dialog'))
        .where(
          (dialog) => s.nodes.any(
            (n) =>
                within(n.id, dialog.id) &&
                (n.name == 'Go to next video' ||
                    NurtureVideo._videoUrl.hasMatch(n.text.trim())),
          ),
        )
        .map((dialog) => dialog.id)
        .toList();
    return s.nodes
        .where(
          (n) =>
              !within(n.id, cardRoot) &&
              !within(n.id, panelRoot) &&
              !players.any((root) => within(n.id, root)),
        )
        .toList();
  }

  Future<void> _tap(
    String key,
    SignupSnapshot s,
    SignupNode n, {
    Future<void> Function(Offset)? beforeDispatch,
  }) async {
    _check();
    if (!n.enabled || !n.clickable) {
      throw StateError('Control nuôi chưa sẵn sàng: $key.');
    }
    final point = await profile.target(key, s.viewport, n);
    _check();
    await beforeDispatch?.call(point);
    _check();
    await accessibility.tap(s.viewport, point);
    _check();
  }

  SignupNode? _close(SignupSnapshot s) {
    final editors = s.editors.where(
      (n) =>
          RegExp(r'comment|bình luận', caseSensitive: false).hasMatch(n.hint),
    );
    if (editors.length != 1) return null;
    return s.find(RegExp(r'^exit$', caseSensitive: false));
  }

  Future<void> _run() async {
    DateTime? missingSince;
    var unplayable = 0;
    try {
      final keyword = searchKeyword?.trim() ?? '';
      if (keyword.isNotEmpty) await _search(keyword);
      while (true) {
        final s = await _snapshot();
        final video = NurtureVideo.read(s);
        final live = video == null ? NurtureVideo.liveNext(s) : null;
        if (live != null) {
          missingSince = null;
          await _skipLive(s, live);
          continue;
        }
        final stuck = video == null ? NurtureVideo.playerNext(s) : null;
        if (stuck != null &&
            missingSince != null &&
            _now().difference(missingSince) > const Duration(seconds: 10)) {
          // The search-result player opened a post that never starts (no
          // clock): move on rather than wait for it.
          if (++unplayable > 3) {
            throw StateError(
              'Nhiều video tìm kiếm liên tiếp không phát được; đã dừng nuôi.',
            );
          }
          final a = s.viewport.fromScreen(stuck.bounds.topLeft);
          await _tap(
            'detail/feed/skip-unplayable/${a.dx.round()}-${a.dy.round()}',
            s,
            stuck,
          );
          missingSince = null;
          await _sleep(1500);
          continue;
        }
        if (video == null) {
          missingSince ??= _now();
          if (_now().difference(missingSince) > const Duration(seconds: 20)) {
            throw StateError(
              'Không đọc được tiến độ video qua Accessibility; đã dừng nuôi.',
            );
          }
          await _sleep();
          continue;
        }
        missingSince = null;
        unplayable = 0;
        final plan = _plan(video);
        // An empty panel left by a cancelled attempt is safe to close. A real
        // draft must be retained; opening comments alone must not stop nurture.
        if (_close(s) != null) {
          if (!await _closeEmptyComments()) {
            throw StateError(
              'Có bình luận đang soạn; đã dừng và giữ bản nháp.',
            );
          }
          continue;
        }
        if (plan.completed ||
            (!plan.full && plan.watched >= plan.skipAt) ||
            (plan.full && plan.cap != null && plan.watched >= plan.cap!)) {
          await _advance(s, video, plan);
        } else if (!plan.likeAttempted &&
            plan.likeAt >= 0 &&
            video.position >= plan.likeAt) {
          plan.likeAttempted = true; // One tap per post; never retried.
          await _likeSafely(s, video);
        } else if (plan.full &&
            !plan.commentAttempted &&
            plan.commentAt >= 0 &&
            video.position >= plan.commentAt) {
          plan.commentAttempted =
              true; // Retained across pause/resume and errors.
          if (video.position + 3 < video.duration * .7) {
            await _comment(s, video);
          }
        }
        await _sleep();
      }
    } on NurtureCancelled {
      // A timer, navigation or app lifecycle stopped this session.
    } finally {
      await _emit();
    }
  }

  /// Each step reads the current screen, so a restarted runner resumes where
  /// the previous one stopped. A step fires at most twice, 6s apart.
  Future<void> _search(String keyword) async {
    final fired = <String, int>{};
    final last = <String, DateTime>{};
    final deadline = _now().add(const Duration(seconds: 60));
    try {
      await accessibility.setKeyboardSuppressed(true);
      _check();
      while (_now().isBefore(deadline)) {
        final s = await _snapshot();
        // Done once the player is open; an unplayable post is skipped by
        // the watch loop with the player's next button.
        if (NurtureVideo.read(s)?.detail == true ||
            NurtureVideo.playerNext(s) != null) {
          return;
        }
        final step = _searchStep(s, keyword, fired);
        final previous = step == null ? null : last[step.$1];
        if (step == null ||
            (previous != null &&
                _now().difference(previous) < const Duration(seconds: 6))) {
          await _sleep();
          continue;
        }
        final (name, node) = step;
        final count = fired[name] = (fired[name] ?? 0) + 1;
        if (count > 2) {
          throw StateError(
            'Không tìm kiếm được "$keyword" (bước $name); đã dừng nuôi.',
          );
        }
        last[name] = _now();
        if (name == 'paste') {
          final result = await accessibility.paste(keyword, 'search');
          _check();
          if (result['ok'] != true) {
            throw StateError(
              'Không nhập được từ khóa tìm kiếm (${result['reason']}); '
              'đã dừng nuôi.',
            );
          }
        } else {
          final a = s.viewport.fromScreen(node.bounds.topLeft);
          final b = s.viewport.fromScreen(node.bounds.bottomRight);
          // Result rows are plain views; the gesture target is their box.
          await _tap(
            'search/$name/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}',
            s,
            SignupNode({
              'id': node.id,
              'enabled': true,
              'clickable': true,
              'bounds': [
                node.bounds.left,
                node.bounds.top,
                node.bounds.right,
                node.bounds.bottom,
              ],
            }),
          );
        }
        await _sleep(1500);
      }
      throw StateError(
        'Không mở được video từ kết quả tìm kiếm "$keyword"; đã dừng nuôi.',
      );
    } finally {
      await accessibility.setKeyboardSuppressed(false);
    }
  }

  (String, SignupNode)? _searchStep(
    SignupSnapshot s,
    String keyword,
    Map<String, int> fired,
  ) {
    final v = s.viewport.bounds;
    // The player opens as a Dialog over the grid, whose tiles stay in the
    // tree. Never tap the grid through it (that lands on the player's
    // Like/Favorite buttons); wait for its clock instead.
    if (s.nodes.any((n) => n.className.endsWith('Dialog'))) return null;
    final videosTab = s.nodes
        .where(
          (n) =>
              n.clickable &&
              n.className.endsWith('Button') &&
              n.text.trim() == 'Videos',
        )
        .firstOrNull;
    if (videosTab != null) {
      // The Top tab mixes in users and LIVE rooms; Videos holds only posts.
      if ((fired['videos-tab'] ?? 0) == 0) return ('videos-tab', videosTab);
      final tiles = s.nodes
          .where(
            (n) =>
                n.clickable &&
                n.enabled &&
                n.name == 'Watch in full screen' &&
                v.contains(n.bounds.topLeft) &&
                n.bounds.bottom <= v.bottom,
          )
          .toList();
      if (tiles.isNotEmpty) {
        return ('result', tiles[_random.nextInt(min(tiles.length, 8))]);
      }
      return null;
    }
    final query = keyword.toLowerCase();
    final viewAll = s.nodes
        .where(
          (n) =>
              n.text.trim().startsWith('View all results for') &&
              n.text.toLowerCase().contains(query),
        )
        .firstOrNull;
    if (viewAll != null) return ('view-all', viewAll);
    final drawer = s.nodes
        .where(
          (n) =>
              n.editable &&
              n.focused &&
              n.bounds.width > v.width * .2 &&
              n.bounds.center.dx < v.left + v.width * .5 &&
              !RegExp('comment', caseSensitive: false).hasMatch(n.hint),
        )
        .firstOrNull;
    if (drawer != null) return ('paste', drawer);
    final sidebar = s.nodes
        .where((n) => n.editable && n.bounds.center.dx < v.left + v.width * .1)
        .firstOrNull;
    if (sidebar != null) return ('open', sidebar);
    return null;
  }

  Future<void> _skipLive(SignupSnapshot s, SignupNode next) async {
    await _tap('live/feed/next-video', s, next);
    // One tap only; never repeated if the feed did not move.
    final deadline = _now().add(const Duration(seconds: 8));
    while (_now().isBefore(deadline)) {
      await _sleep();
      final fresh = await _snapshot();
      if (NurtureVideo.read(fresh) != null ||
          NurtureVideo.liveNext(fresh) == null) {
        return;
      }
    }
    throw StateError('Chưa bỏ qua được bài LIVE; đã dừng để kiểm tra tọa độ.');
  }

  Future<void> _advance(
    SignupSnapshot s,
    NurtureVideo video,
    _WatchPlan plan,
  ) async {
    if (video.next != null) {
      await _tap('${video.orientation.name}/feed/next-video', s, video.next!);
    } else {
      // Persist both gesture endpoints before dispatch. The video container is the
      // target region, so gestures cannot land in the navigation/comment sidebar.
      final region = SignupNode({
        'id': 'video',
        'enabled': true,
        'clickable': true,
        'bounds': [
          video.bounds.left,
          video.bounds.top,
          video.bounds.right,
          video.bounds.bottom,
        ],
      });
      final layout = video.layout(s.viewport);
      final a = await profile.target(
        '$layout/swipe-from',
        s.viewport,
        SignupNode({
          'id': 'from',
          'bounds': [
            region.bounds.left,
            region.bounds.top + region.bounds.height * .7,
            region.bounds.right,
            region.bounds.top + region.bounds.height * .9,
          ],
        }),
      );
      final b = await profile.target(
        '$layout/swipe-to',
        s.viewport,
        SignupNode({
          'id': 'to',
          'bounds': [
            region.bounds.left,
            region.bounds.top + region.bounds.height * .1,
            region.bounds.right,
            region.bounds.top + region.bounds.height * .3,
          ],
        }),
      );
      _check();
      await accessibility.swipe(s.viewport, a, b);
    }
    // One advance only. No repeat if the UI failed to move. The next post is
    // unreadable until its clock reports a duration, which slow loads (large
    // screens, landscape posts) can push well past a few seconds.
    final deadline = _now().add(const Duration(seconds: 20));
    while (_now().isBefore(deadline)) {
      await _sleep();
      final current = NurtureVideo.read(await _snapshot());
      if (current != null && current.key != video.key) {
        if (!plan.completed) {
          plan.completed = true;
          // A capped long video counts as watched, not skipped.
          if (plan.full) {
            _full++;
          } else {
            _skipped++;
          }
          await _emit();
        }
        _previous = current;
        return;
      }
    }
    throw StateError('Chưa chuyển được video; đã dừng để kiểm tra tọa độ.');
  }

  /// One tap on the like toggle; never repeated, since a second tap unlikes.
  /// TikTok shows a like at once and rolls a rejected one back within a few
  /// seconds, so an exact count is watched until the rollback window passes.
  Future<void> _like(SignupSnapshot s, NurtureVideo video) async {
    final like = video.like;
    if (like == null) return;
    final before = video.likeCount;
    await _tap(
      video.likeKey(s.viewport),
      s,
      like,
      beforeDispatch: (point) async {
        final fresh = await _snapshot();
        final current = NurtureVideo.read(fresh);
        if (current?.key != video.key ||
            current!.like == null ||
            !current.like!.bounds.contains(fresh.viewport.toScreen(point))) {
          throw const _LikeSkipped('Nút thả tim đã thay đổi.');
        }
      },
    );
    if (before != null) {
      var raised = false;
      final until = _now().add(const Duration(seconds: 8));
      do {
        await _sleep();
        final current = NurtureVideo.read(await _snapshot());
        if (current == null) continue;
        if (current.key != video.key) break;
        final count = current.likeCount;
        if (count == before + 1) {
          raised = true;
        } else if (raised && count == before) {
          throw const _LikeSkipped(
            'TikTok đã hoàn lại lượt thả tim (tài khoản có thể bị hạn chế).',
          );
        }
      } while (_now().isBefore(until));
      if (!raised) throw const _LikeSkipped('Chưa xác nhận được thả tim.');
    }
    // A rounded count cannot confirm the like; the tap itself is counted.
    _likes++;
    await _emit();
    onLike?.call();
  }

  Future<void> _likeSafely(SignupSnapshot s, NurtureVideo video) async {
    try {
      await _like(s, video);
    } on _LikeSkipped catch (error) {
      onLikeSkipped?.call('${error.message} Không bấm lại; tiếp tục nuôi.');
    }
  }

  Future<SignupSnapshot> _sameVideo(String key) async {
    final s = await _snapshot();
    if (NurtureVideo.read(s)?.key != key) {
      throw StateError(
        'Video thay đổi hoặc mất tiến độ khi bình luận; đã dừng.',
      );
    }
    return s;
  }

  Future<SignupSnapshot> _waitFor(
    String key,
    bool Function(SignupSnapshot) ready,
  ) async {
    final until = _now().add(const Duration(seconds: 8));
    var seen = 'chưa đọc được video';
    do {
      await _sleep(200);
      final s = await _snapshot();
      final current = NurtureVideo.read(s);
      // Reflow and accessibility-tree refresh can hide the clock briefly.
      // Wait without entering text; a confirmed different post still stops.
      if (current == null) continue;
      if (current.key != key) {
        throw StateError('Video đã thay đổi khi bình luận; đã dừng.');
      }
      if (ready(s)) return s;
      // Last observed state, so a timeout says what was missing.
      seen =
          'bàn phím ${s.keyboardVisible ? 'hiện' : 'ẩn'}, ô nhập '
          '${s.editors.map((n) => '${n.length}${n.focused ? '*' : ''}').join('/')}';
    } while (_now().isBefore(until));
    debugPrint('Nurture comment wait timed out: $seen');
    throw _CommentNotReady('Bình luận chưa sẵn sàng ($seen).');
  }

  Future<bool> _closeEmptyComments() async {
    var s = await _snapshot();
    final editor = _editor(s);
    final close = _close(s);
    if (editor == null || editor.length != 0 || close == null) return false;
    final kind = NurtureVideo.read(s)?.orientation.name ?? 'shared';
    await _tap(
      NurtureCoordinateProfile.panelKey(
        kind,
        'close-comments',
        s.viewport,
        close,
      ),
      s,
      close,
      beforeDispatch: (point) async {
        final fresh = await _snapshot();
        final button = _close(fresh);
        if (_editor(fresh)?.length != 0 ||
            button == null ||
            !button.bounds.contains(fresh.viewport.toScreen(point))) {
          throw StateError('Có thay đổi trong ô bình luận; đã giữ bản nháp.');
        }
      },
    );
    final until = _now().add(const Duration(seconds: 8));
    do {
      await _sleep(200);
      s = await _snapshot();
      if (_editor(s) == null && _close(s) == null) return true;
    } while (_now().isBefore(until));
    return false;
  }

  SignupNode? _editor(SignupSnapshot s) {
    final list = s.editors
        .where(
          (n) => RegExp(
            r'comment|bình luận',
            caseSensitive: false,
          ).hasMatch(n.hint),
        )
        .toList();
    return list.length == 1 ? list.single : null;
  }

  int _matches(SignupSnapshot s, String text) =>
      s.nodes.where((n) => !n.editable && n.text.trim() == text.trim()).length;

  Future<void> _comment(SignupSnapshot s, NurtureVideo video) async {
    var pasteAttempted = false, keepSuppressed = false;
    try {
      final kind = video.orientation.name;
      if (video.detail) {
        // The search-result player keeps its comment box open beside it.
        s = await _waitFor(video.key, (s) => _editor(s) != null);
      } else {
        await _tap(video.commentsKey(s.viewport), s, video.comments!);
        s = await _waitFor(
          video.key,
          (s) => _editor(s) != null && _close(s) != null,
        );
      }
      if (NurtureVideo.read(s)!.position + 4 >= video.duration * .7) {
        throw const _CommentNotReady(
          'Không còn đủ thời gian để nhập bình luận.',
        );
      }
      final editor = _editor(s)!;
      if (editor.length != 0) {
        throw StateError('Có bình luận đang soạn; đã dừng và giữ bản nháp.');
      }
      var index = _random.nextInt(
        comments.length - (comments.length > 1 && _lastComment >= 0 ? 1 : 0),
      );
      if (comments.length > 1 && _lastComment >= 0 && index >= _lastComment) {
        index++;
      }
      _lastComment = index;
      final text = comments[index];
      final baseline = _matches(s, text);
      try {
        await accessibility.setKeyboardSuppressed(true);
        _check();
        await _tap(
          NurtureCoordinateProfile.panelKey(
            kind,
            'focus-comment',
            s.viewport,
            editor,
          ),
          s,
          editor,
        );
        s = await _waitFor(video.key, (s) => _editor(s)?.focused == true);
        _check();
        pasteAttempted = true;
        final result = await accessibility.paste(text, 'comment');
        _check();
        if (result['ok'] != true) {
          final reason = '${result['reason']}';
          if (reason.startsWith('editor-unavailable') ||
              reason == 'paste-rejected' ||
              reason == 'paste-not-inserted') {
            // Nothing reached the editor (verified empty): no draft to keep.
            pasteAttempted = false;
            throw _CommentNotReady('Ô bình luận chưa sẵn sàng ($reason).');
          }
          throw StateError(
            'Không nhập được bình luận qua Accessibility '
            '(${result['reason']}); đã giữ bản nháp.',
          );
        }
        // The search-result player keeps the keyboard suppressed through
        // submit: dismissKeyboard restores the normal policy after 300ms,
        // which would reopen it on the still-focused editor.
        if (!video.detail) await accessibility.dismissKeyboard();
        keepSuppressed = video.detail;
      } finally {
        if (!keepSuppressed) await accessibility.setKeyboardSuppressed(false);
      }
      if (video.detail) {
        // In the search-result player the editor keeps focus after the
        // keyboard is dismissed, so the keyboard stays suppressed until the
        // comment is confirmed and the editor is blurred.
        try {
          await accessibility.setKeyboardSuppressed(true);
          _check();
          // A filled editor drops its "Add comment" hint: it is the filled
          // editor in the lower half of the frame.
          s = await _waitFor(
            video.key,
            (s) =>
                !s.keyboardVisible &&
                s.editors.any(
                  (n) =>
                      n.length > 0 &&
                      n.bounds.center.dy > s.viewport.bounds.center.dy,
                ),
          );
          if (NurtureVideo.read(s)!.position + 1 >= video.duration * .7) {
            throw StateError(
              'Đã quá thời điểm bình luận; đã dừng và giữ bản nháp.',
            );
          }
          // The Post button is clipped off-screen by the side panel, so it
          // is pressed with ACTION_CLICK. Exactly one submit; never retried.
          if (!await accessibility.submitComment()) {
            throw StateError(
              'Không gửi được bình luận; đã dừng và giữ bản nháp.',
            );
          }
          _check();
          s = await _waitFor(
            video.key,
            (s) => _editor(s)?.length == 0 && _matches(s, text) > baseline,
          );
          _comments++;
          await _emit();
          onComment?.call();
          // Blur the editor by tapping the already-selected Comments tab.
          final tab = s.nodes
              .where((n) => RegExp(r'^Comments \(').hasMatch(n.text.trim()))
              .firstOrNull;
          if (tab != null) {
            final a = s.viewport.fromScreen(tab.bounds.topLeft);
            await _tap(
              'detail/panel/blur-comment/${a.dx.round()}-${a.dy.round()}',
              s,
              SignupNode({
                'id': tab.id,
                'enabled': true,
                'clickable': true,
                'bounds': [
                  tab.bounds.left,
                  tab.bounds.top,
                  tab.bounds.right,
                  tab.bounds.bottom,
                ],
              }),
            );
            await _sleep(500);
          }
        } finally {
          await accessibility.setKeyboardSuppressed(false);
        }
        return;
      } else {
        s = await _waitFor(
          video.key,
          (s) =>
              !s.keyboardVisible &&
              s.find(RegExp(r'^Post$', caseSensitive: false)) != null,
        );
        if (NurtureVideo.read(s)!.position + 1 >= video.duration * .7) {
          throw StateError(
            'Đã quá thời điểm bình luận; đã dừng và giữ bản nháp.',
          );
        }
        // Exact one Post dispatch; never retry an uncertain publication.
        final post = s.find(RegExp(r'^Post$', caseSensitive: false))!;
        await _tap(
          NurtureCoordinateProfile.panelKey(
            kind,
            'post-comment',
            s.viewport,
            post,
          ),
          s,
          post,
          beforeDispatch: (point) async {
            final fresh = await _sameVideo(video.key);
            final current = NurtureVideo.read(fresh)!;
            final button = fresh.find(RegExp(r'^Post$', caseSensitive: false));
            if (fresh.viewport.bounds != s.viewport.bounds ||
                button == null ||
                !button.bounds.contains(fresh.viewport.toScreen(point)) ||
                current.position < NurtureVideo.read(s)!.position ||
                current.position + 1 >= current.duration * .7) {
              throw StateError(
                'Video hoặc thời điểm gửi đã đổi; đã dừng và giữ bản nháp.',
              );
            }
          },
        );
      }
      s = await _waitFor(
        video.key,
        (s) => _editor(s)?.length == 0 && _matches(s, text) > baseline,
      );
      _comments++;
      await _emit();
      onComment?.call();
      final close = _close(s);
      if (close == null) throw StateError('Không tìm thấy nút đóng bình luận.');
      await _tap(
        NurtureCoordinateProfile.panelKey(
          kind,
          'close-comments',
          s.viewport,
          close,
        ),
        s,
        close,
      );
      await _waitFor(video.key, (s) => _close(s) == null);
    } on _CommentNotReady catch (error) {
      final empty = video.detail && _editor(await _snapshot())?.length == 0;
      if (!pasteAttempted && (empty || await _closeEmptyComments())) {
        onCommentSkipped?.call(
          '${error.message} Bỏ qua bình luận này và tiếp tục nuôi.',
        );
        return;
      }
      throw StateError(
        '${error.message} Đã dừng và giữ bản nháp; không gửi lại.',
      );
    }
  }
}
