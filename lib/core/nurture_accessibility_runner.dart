import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

import 'nurture_coordinate_profile.dart';
import 'nurture_data.dart';
import 'signup_accessibility.dart';

/// `detail` is the search-result player: a modal with its own comment box.
enum NurtureVideoOrientation { portrait, landscape, detail }

/// Playback metadata disappeared; the owner may retry reading the same page.
class NurturePlaybackUnavailable extends StateError {
  NurturePlaybackUnavailable(super.message);
}

/// A TikTok dialog stayed open (for example "Verifying..." after a solved
/// CAPTCHA); the owner may retry on the same page once it closes.
class NurtureDialogOpen extends StateError {
  NurtureDialogOpen(super.message);
}

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

  /// TikTok can replace playback controls with this error after Next. Only
  /// accept it inside visible media, never from captions or comment text.
  static bool playbackFailed(SignupSnapshot snapshot) {
    final media = snapshot.nodes.where(
      (n) =>
          n.clickable &&
          n.enabled &&
          n.name == 'Watch in full screen' &&
          !n.bounds.intersect(snapshot.viewport.bounds).isEmpty,
    );
    return snapshot.nodes.any(
      (n) =>
          n.text.trim() ==
              "We're having trouble playing this video. Please refresh and try again." &&
          !n.bounds.intersect(snapshot.viewport.bounds).isEmpty &&
          media.any((root) => n.id.startsWith('${root.id}.')),
    );
  }

  static NurtureVideo? read(SignupSnapshot snapshot) {
    if (!snapshot.ready || !snapshot.viewport.valid || isLiveRoom(snapshot)) {
      return null;
    }
    // Gecko retains the clock in the tree after the player controls fade out.
    // Hidden nodes supply playback metadata and ancestor geometry only; action
    // targets still come exclusively from the visible snapshot below.
    final nodes = {
      for (final n in [...snapshot.hiddenNodes, ...snapshot.nodes]) n.id: n,
    };
    final candidates = <NurtureVideo>[];
    for (final button in snapshot.nodes.where(
      (n) =>
          n.clickable &&
          n.enabled &&
          !n.bounds.intersect(snapshot.viewport.bounds).isEmpty &&
          RegExp(
            r'^Read or add comments\b',
            caseSensitive: false,
          ).hasMatch(n.name),
    )) {
      final actionRoot = button.id.substring(0, button.id.lastIndexOf('.'));
      final card = actionRoot.substring(0, actionRoot.lastIndexOf('.'));
      final children = nodes.values
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
      // Gecko can keep a mid-scroll position after Next, reporting the whole
      // feed hundreds of pixels from where it is drawn (recorded: 581px).
      // The feed snaps a viewport-tall post to the viewport top, and the stale
      // scroll offset applies to every node of the card, so a playing post's
      // targets are moved back by it. Otherwise keep its clock but expose no
      // card-relative target.
      final container = nodes[card]?.bounds;
      final viewport = snapshot.viewport.bounds;
      final stale = container == null ? 0.0 : container.top - viewport.top;
      final shift =
          stale.abs() > 3 &&
              position > 0 &&
              (container!.height - viewport.height).abs() <= 3
          ? stale
          : 0.0;
      final settled =
          container != null &&
          (container.top - shift - viewport.top).abs() <= 3 &&
          _inside(media.translate(0, -shift), viewport) &&
          _inside(button.bounds.translate(0, -shift), viewport);
      final like = settled
          ? _likeIn(
              snapshot.nodes.where((n) => n.id.startsWith('$actionRoot.')),
            )
          : null;
      candidates.add(
        NurtureVideo(
          // Music labels can disappear/reappear when the comment panel opens.
          // They describe the layout, not a change of the playing post.
          key: '$card|$author|$duration',
          position: position,
          duration: duration,
          bounds: settled ? media.translate(0, -shift) : media,
          comments: settled ? _moved(button, -shift) : null,
          like: like == null ? null : _moved(like, -shift),
          next: down,
          root: card,
        ),
      );
    }
    // The search-result player is a modal over the page; it wins when open.
    final detail = _readDetail(snapshot, nodes);
    if (detail != null) return detail;
    // Multiple exposed posts are ambiguous; don't comment on a guessed card.
    if (candidates.isNotEmpty) {
      return candidates.length == 1 ? candidates.single : null;
    }
    return _readStaleFeed(snapshot, nodes);
  }

  /// False for a feed card whose geometry is stale (see [read]); only the
  /// page-level Next beside the scroller may be tapped then.
  bool get targetsVerified => detail || comments != null;

  static SignupNode _moved(SignupNode n, double dy) => dy == 0
      ? n
      : SignupNode({
          'id': n.id,
          'text': n.text,
          'description': n.description,
          'hint': n.hint,
          'className': n.className,
          'enabled': n.enabled,
          'clickable': n.clickable,
          'editable': n.editable,
          'password': n.password,
          'focused': n.focused,
          'selected': n.selected,
          'picker': n.picker,
          'scrollable': n.scrollable,
          'length': n.length,
          'bounds': [
            n.bounds.left,
            n.bounds.top + dy,
            n.bounds.right,
            n.bounds.bottom + dy,
          ],
        });

  static bool _inside(Rect r, Rect viewport) =>
      r.left >= viewport.left - 2 &&
      r.top >= viewport.top - 2 &&
      r.right <= viewport.right + 2 &&
      r.bottom <= viewport.bottom + 2;

  static final _commentsButton = RegExp(
    r'^Read or add comments\b',
    caseSensitive: false,
  );

  /// After Next, Gecko can flag the new card visible while still reporting
  /// it and its action column a scroll step lower (seen for 30s+). Its clock
  /// and author stay readable, so playback is tracked without card targets.
  static NurtureVideo? _readStaleFeed(
    SignupSnapshot s,
    Map<String, SignupNode> nodes,
  ) {
    final card = _staleCard(s);
    if (card == null) return null;
    final times = nodes.values
        .where((n) => n.id.startsWith('${card.id}.'))
        .where((n) => _time.hasMatch(n.text.trim()))
        .toList();
    if (times.length != 1) return null;
    final match = _time.firstMatch(times.single.text.trim())!;
    final duration = _seconds(match[2]!);
    final position = _seconds(match[1]!);
    if (duration <= 0 || position > duration) return null;
    return NurtureVideo(
      key: '${card.id}|${card.author}|$duration',
      position: position,
      duration: duration,
      bounds: card.media.bounds,
      comments: null,
      next: card.next,
      root: card.id,
    );
  }

  /// The single card Gecko flags visible while its action column is not,
  /// with the page's Next control (outside the scroller) visible. Gecko can
  /// also hide that card; then it is the one post whose clock has started.
  static ({String id, String author, SignupNode media, SignupNode next})?
  _staleCard(SignupSnapshot s) {
    if (!s.ready ||
        !s.viewport.valid ||
        isLiveRoom(s) ||
        s.nodes.any((n) => n.className.endsWith('Dialog'))) {
      return null;
    }
    final all = {
      for (final n in [...s.hiddenNodes, ...s.nodes]) n.id: n,
    };
    String parent(String id) => id.substring(0, id.lastIndexOf('.'));
    bool started(String card) => all.values.any((n) {
      if (!n.id.startsWith('$card.')) return false;
      final match = _time.firstMatch(n.text.trim());
      if (match == null) return false;
      final position = _seconds(match[1]!);
      return position > 0 && position <= _seconds(match[2]!);
    });
    final shown = s.nodes
        .where(
          (n) =>
              n.clickable &&
              n.enabled &&
              n.name == 'Watch in full screen' &&
              !n.bounds.intersect(s.viewport.bounds).isEmpty,
        )
        .toList();
    final media = shown.isNotEmpty
        ? shown
        : s.hiddenNodes
              .where(
                (n) =>
                    n.name == 'Watch in full screen' &&
                    n.id.contains('.') &&
                    started(parent(n.id)),
              )
              .toList();
    if (media.length != 1 || !media.single.id.contains('.')) return null;
    final id = parent(media.single.id);
    final parts = id.split('.');
    if (parts.length < 3 ||
        s.nodes.any(
          (n) => n.id.startsWith('$id.') && _commentsButton.hasMatch(n.name),
        )) {
      return null;
    }
    final author = all['$id.1.0.0']?.label.trim() ?? '';
    if (author.isEmpty) return null;
    final next = _pairedDown(
      {for (final n in s.nodes) n.id: n},
      parts.take(parts.length - 2).join('.'),
      media.single.bounds.right,
    );
    if (next == null || next.bounds.intersect(s.viewport.bounds).isEmpty) {
      return null;
    }
    return (id: id, author: author, media: media.single, next: next);
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
      final times = nodes.values.where(
        (n) =>
            n.id.startsWith('${dialog.id}.') && _time.hasMatch(n.text.trim()),
      );
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

  static final _postUrl = RegExp(r'^https:\S*/(?:video|photo)/(\d{6,})');

  /// The search-result player's post id, read without the clock: photo
  /// posts never expose one.
  static String? playerPost(SignupSnapshot snapshot) {
    for (final dialog in snapshot.nodes.where(
      (n) => n.className.endsWith('Dialog'),
    )) {
      final ids = snapshot.nodes
          .where((n) => n.id.startsWith('${dialog.id}.'))
          .map((n) => _postUrl.firstMatch(n.text.trim())?.group(1))
          .nonNulls
          .toSet();
      if (ids.length == 1) return ids.single;
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

  /// Feed navigation does not require a playback clock. Some posts expose
  /// 00:00 / 00:00 indefinitely; they can be skipped without guessing a video
  /// duration. Require one visible post, its media and the paired next button.
  static ({String key, SignupNode next})? feedNavigation(SignupSnapshot s) {
    if (!s.ready ||
        !s.viewport.valid ||
        isLiveRoom(s) ||
        s.nodes.any((n) => n.className.endsWith('Dialog')) ||
        [...s.nodes, ...s.hiddenNodes].any(
          (n) =>
              n.editable &&
              !RegExp(
                r'^search$',
                caseSensitive: false,
              ).hasMatch(n.hint.trim()),
        )) {
      return null;
    }
    final nodes = {for (final n in s.nodes) n.id: n};
    final candidates = <({String key, SignupNode next})>[];
    for (final button in s.nodes.where(
      (n) =>
          n.clickable &&
          n.enabled &&
          !n.bounds.intersect(s.viewport.bounds).isEmpty &&
          RegExp(
            r'^Read or add comments\b',
            caseSensitive: false,
          ).hasMatch(n.name),
    )) {
      final parts = button.id.split('.');
      if (parts.length < 5) continue;
      final card = parts.take(parts.length - 2).join('.');
      final page = parts.take(parts.length - 4).join('.');
      final actionRoot = parts.take(parts.length - 1).join('.');
      final author = nodes['$actionRoot.0.0']?.label.trim() ?? '';
      final media = s.nodes
          .where(
            (n) =>
                n.id.startsWith('$card.') &&
                n.name == 'Watch in full screen' &&
                n.clickable &&
                n.enabled &&
                !n.bounds.intersect(s.viewport.bounds).isEmpty,
          )
          .toList();
      if (author.isEmpty || media.length != 1) continue;
      final next = _pairedDown(nodes, page, media.single.bounds.right);
      if (next != null && !next.bounds.intersect(s.viewport.bounds).isEmpty) {
        candidates.add((key: '$card|$author', next: next));
      }
    }
    if (candidates.isEmpty) {
      // Stale geometry (see [_staleCard]), e.g. a promoted LIVE without a
      // clock or comment button.
      final card = _staleCard(s);
      if (card != null) {
        return (key: '${card.id}|${card.author}', next: card.next);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
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

  /// A standalone LIVE room is distinct from the sidebar's generic LIVE link.
  static bool isLiveRoom(SignupSnapshot snapshot) {
    if (!snapshot.ready || !snapshot.viewport.valid) return false;
    return snapshot.nodes.any(
      (n) =>
          n.className.endsWith('WebView') &&
          RegExp(
            r'\bis LIVE\s*[-–—]\s*TikTok LIVE\b',
            caseSensitive: false,
          ).hasMatch(n.name),
    );
  }

  /// LIVE's sidebar Back expands navigation rather than leaving the room.
  /// Use TikTok's explicit For You link to resume ordinary videos instead.
  static SignupNode? liveRoomExit(SignupSnapshot snapshot) {
    if (!isLiveRoom(snapshot)) return null;
    return snapshot.nodes
        .where(
          (n) =>
              n.clickable &&
              n.enabled &&
              n.name == 'Go to TikTok For You feed' &&
              !n.bounds.intersect(snapshot.viewport.bounds).isEmpty,
        )
        .firstOrNull;
  }

  /// A LIVE preview in the feed is skipped with its ordinary Next control.
  static SignupNode? liveNext(SignupSnapshot snapshot) {
    if (!snapshot.ready || !snapshot.viewport.valid) return null;
    final nodes = {for (final n in snapshot.nodes) n.id: n};
    // Badge, preview and the "Join my LIVE" overlay all name the post LIVE.
    final live = RegExp(
      r'^(LIVE\b|Watch LIVE|Click to watch LIVE|Join my LIVE)',
      caseSensitive: false,
    );
    final badges = snapshot.nodes.where(
      (n) => !n.editable && live.hasMatch(n.name),
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

/// TikTok's error card on one post; [snapshot] shows it.
class _PlaybackFailed extends StateError {
  _PlaybackFailed(this.snapshot)
    : super(
        'TikTok không phát được video này; đã dừng nuôi. '
        'Hãy tải lại trang hoặc kiểm tra kết nối.',
      );
  final SignupSnapshot snapshot;
}

/// TikTok moved on by itself (a post ended) while Next was being prepared.
class _AdvancedBeforeTap implements Exception {
  const _AdvancedBeforeTap(this.video);

  /// Null for a post without a clock (a photo).
  final NurtureVideo? video;
}

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

  /// Skipped because playback stopped; never counts as a full watch.
  bool stalled = false;
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
    this.continueOnCommentError = false,
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
  final bool continueOnCommentError;
  bool _commentsBlocked = false, _draftReported = false;
  bool _pendingCommentDraft = false;

  /// Sticky across missing editor snapshots and runner restarts. A failed
  /// publication must not be followed by Next or a page reload.
  bool get hasPendingCommentDraft => _pendingCommentDraft;

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
  /// Accessibility, then a non-LIVE video result is watched. Null or empty
  /// watches the For You feed.
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
  bool _searchFinished = false;
  final Set<String> _advanceAttempted = {};
  int _serverRetryAttempts = 0;
  DateTime? _lastServerRetryAt;

  /// Posts skipped for TikTok's playback error since one last played; kept
  /// across resumes so a dead connection cannot skip post after post.
  int _playbackSkips = 0;
  bool _cancelled = false, _running = false;

  /// Gecko ignores ACTION_CLEAR_FOCUS, so a used editor keeps input focus and
  /// the IME returns whenever suppression ends. Nurture never types through
  /// the IME: it stays hidden for the whole session, renewed before the
  /// native 10s lease expires.
  bool _holdingKeyboard = false;
  DateTime? _keyboardRenewedAt;
  NurtureVideo? _previous;
  DateTime? _sampledAt;
  Future<void>? _done;
  int _runEpoch = 0;
  Completer<SignupSnapshot>? _snapshotWaiter;
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

  /// Publish before the midpoint, leaving time to open and fill the editor.
  static const _commentDeadlineRatio = .5;

  /// How long a CAPTCHA may stay open while the monitor solves it.
  static const _captchaWait = Duration(seconds: 60);

  /// A readable clock that stops this long is a stalled player (seen when
  /// Gecko unbinds its media service mid-video); the post is skipped.
  static const _stallWait = Duration(seconds: 15);

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
    _runEpoch++;
    _previous = null;
    _sampledAt = null; // A background gap is never playback time.
    return _done = _run().whenComplete(() => _running = false);
  }

  void cancel() {
    _cancelled = true;
    final reader = _snapshotWaiter;
    if (reader != null && !reader.isCompleted) {
      reader.completeError(NurtureCancelled());
    }
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

  /// Fire and forget; steps that type still await their own suppression.
  void _renewKeyboard({bool force = false}) {
    final at = _keyboardRenewedAt;
    if (!_holdingKeyboard ||
        (!force &&
            at != null &&
            _now().difference(at) < const Duration(seconds: 4))) {
      return;
    }
    _keyboardRenewedAt = _now();
    // Without CAPTCHA hooks: renewing must not run them every 4s.
    unawaited(
      accessibility.renewKeyboardSuppression().catchError((Object _) {
        // Best effort: no WebView root during a reload (or no service); the
        // next snapshot renews it.
        _keyboardRenewedAt = null;
      }),
    );
  }

  /// Ends a step's suppression, except while the session holds the IME.
  Future<void> _releaseKeyboard() async {
    if (!_holdingKeyboard) await accessibility.setKeyboardSuppressed(false);
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
    if (!video.targetsVerified) {
      debugPrint(
        'Nurture feed: card geometry unsettled; like/comment wait for it',
      );
    }
    // Videos longer than a minute are watched for one minute only.
    final cap = video.duration > _maxWatchSeconds ? _maxWatchSeconds : null;
    final watch = min(video.duration, cap ?? video.duration);
    // An unsettled card may expose its toggle once Gecko catches up.
    final like =
        (video.like != null || !video.targetsVerified) &&
        watch >= 4 &&
        _random.nextDouble() < likeRate;
    // Reserve at least five seconds before the midpoint for opening/pasting.
    final latest = min(
      min((watch * .5).floor(), _latestCommentSeconds),
      (video.duration * _commentDeadlineRatio).floor() - 5,
    );
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

  Future<SignupSnapshot> _snapshot({bool trackPlayback = true}) async {
    // Never wait on the lease: a read must not stall behind a platform call.
    _renewKeyboard();
    final reader = _snapshotWaiter = Completer<SignupSnapshot>();
    // A document bridge may disappear during a read. Cancelling must release
    // the runner immediately, even if the underlying platform call is pending.
    // Consume late results/errors without letting an old run change totals.
    unawaited(
      _readSnapshot(_runEpoch, trackPlayback: trackPlayback).then(
        (value) {
          if (!reader.isCompleted) reader.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!reader.isCompleted) reader.completeError(error, stack);
        },
      ),
    );
    try {
      return await reader.future;
    } finally {
      if (identical(_snapshotWaiter, reader)) _snapshotWaiter = null;
    }
  }

  Future<SignupSnapshot> _readSnapshot(
    int epoch, {
    required bool trackPlayback,
  }) async {
    void check() {
      _check();
      if (epoch != _runEpoch) throw NurtureCancelled();
    }

    check();
    if (!await isTikTok()) {
      throw StateError('Đã rời TikTok; dừng nuôi tài khoản.');
    }
    check();
    var s = await accessibility.snapshot();
    check();
    // The WebView node is briefly missing while Flutter rebuilds semantics
    // (button state, snackbar). Only a persistent absence stops nurture.
    final until = _now().add(const Duration(seconds: 3));
    while ((!s.ready || !s.viewport.valid) && _now().isBefore(until)) {
      await _sleep(200);
      s = await accessibility.snapshot();
    }
    check();
    if (!s.ready || !s.viewport.valid) {
      throw StateError('Không đọc được khung WebView chuẩn qua Accessibility.');
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
        check();
        if (next.ready && next.viewport.valid) s = next;
        continue;
      }
      if (hasPrompt(RegExp(r'^Log in to TikTok$', caseSensitive: false))) {
        throw StateError('TikTok yêu cầu đăng nhập lại; đã dừng nuôi.');
      }
      final retry = _serverRetryButton(s);
      if (retry != null) {
        // This is TikTok's own error-page button. Keep the document and the
        // session deadline; loading/retry time is never playback time.
        _previous = null;
        _sampledAt = null;
        final last = _lastServerRetryAt;
        if (_serverRetryAttempts < 3 &&
            (last == null ||
                _now().difference(last) >= const Duration(seconds: 10))) {
          final a = s.viewport.fromScreen(retry.bounds.topLeft);
          await _tap(
            'server-error/try-again/${a.dx.round()}-${a.dy.round()}',
            s,
            retry,
            beforeDispatch: (point) async {
              check();
              final fresh = await accessibility.snapshot();
              check();
              final button = _serverRetryButton(fresh);
              if (button == null ||
                  fresh.viewport.bounds != s.viewport.bounds ||
                  !button.bounds.contains(fresh.viewport.toScreen(point))) {
                throw StateError(
                  'Màn lỗi đã thay đổi; chờ đọc lại trạng thái.',
                );
              }
              _serverRetryAttempts++;
              _lastServerRetryAt = _now();
            },
          );
          debugPrint(
            'Nurture server error: Try again ($_serverRetryAttempts/3)',
          );
          await _sleep(1500);
        } else {
          await _sleep(500);
        }
        final fresh = await accessibility.snapshot();
        check();
        if (fresh.ready && fresh.viewport.valid) s = fresh;
        continue;
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
        throw NurtureDialogOpen(
          'TikTok đang mở hộp thoại$detail; tạm dừng nuôi.',
        );
      }
      await _sleep(500);
      final next = await accessibility.snapshot();
      check();
      if (next.ready && next.viewport.valid) s = next;
    }
    if (trackPlayback && NurtureVideo.playbackFailed(s)) {
      throw _PlaybackFailed(s);
    }
    if (NurtureVideo.read(s) != null) {
      _serverRetryAttempts = 0;
      _lastServerRetryAt = null;
      _playbackSkips = 0;
    }
    if (!trackPlayback) {
      // Opening search is not watching its results. Do not count the old feed
      // behind the drawer, or carry its sample into the result player.
      _previous = null;
      _sampledAt = null;
      return s;
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
    final editor = _editorMetadata(s);
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

  /// Match the full server-error screen, never text inside a video/comment.
  SignupNode? _serverRetryButton(SignupSnapshot s) {
    if (!s.ready ||
        !s.viewport.valid ||
        s.keyboardVisible ||
        _pendingCommentDraft ||
        NurtureVideo.read(s) != null ||
        NurtureVideo.playerNext(s) != null ||
        [...s.nodes, ...s.hiddenNodes].any(
          (n) =>
              n.editable &&
              (n.password ||
                  n.length > 0 &&
                      !RegExp(
                        r'^search$',
                        caseSensitive: false,
                      ).hasMatch(n.hint.trim())),
        )) {
      return null;
    }
    final viewport = s.viewport.bounds;
    final prompts = _prompts(s);
    if (prompts.any(
      (n) => RegExp(
        r'captcha|drag.*slider|verify to continue|^Log in to TikTok$',
        caseSensitive: false,
      ).hasMatch(n.label),
    )) {
      return null;
    }
    final visible = prompts.where(
      (n) =>
          !n.bounds.isEmpty &&
          viewport.contains(n.bounds.topLeft) &&
          n.bounds.right <= viewport.right &&
          n.bounds.bottom <= viewport.bottom,
    );
    bool named(SignupNode n, String value) =>
        n.text.trim().toLowerCase() == value ||
        n.description.trim().toLowerCase() == value;
    final titles = visible.where((n) => named(n, 'something went wrong'));
    final details = visible.where(
      (n) =>
          named(n, 'sorry, something wrong with the server, please try again.'),
    );
    final buttons = visible
        .where((n) => n.enabled && n.clickable && named(n, 'try again'))
        .toList();
    if (titles.isEmpty || details.isEmpty || buttons.length != 1) return null;
    final button = buttons.single;
    // The title, explanation and button must form the same central error block.
    if (!titles.any(
      (title) => details.any(
        (detail) =>
            title.bounds.center.dy < detail.bounds.center.dy &&
            detail.bounds.center.dy < button.bounds.center.dy &&
            (title.bounds.center.dx - button.bounds.center.dx).abs() <
                viewport.width * .2 &&
            (detail.bounds.center.dx - button.bounds.center.dx).abs() <
                viewport.width * .2,
      ),
    )) {
      return null;
    }
    return button;
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
    if (key.endsWith('/next-video')) {
      debugPrint(
        'Nurture next tap: layout=$key control=${n.bounds} '
        'screen=${s.viewport.toScreen(point)}',
      );
    }
    await accessibility.tap(s.viewport, point);
    _check();
  }

  SignupNode? _close(SignupSnapshot s) {
    if (_editorMetadata(s) == null) return null;
    return s.find(RegExp(r'^exit$', caseSensitive: false));
  }

  Future<void> _run() async {
    DateTime? missingSince;
    var unplayable = 0, stalls = 0;
    String? frozenKey;
    int? frozenAt;
    var frozenSince = _now();
    _holdingKeyboard = true;
    try {
      _renewKeyboard(force: true);
      final keyword = searchKeyword?.trim() ?? '';
      if (keyword.isNotEmpty && !_searchFinished) {
        await _search(keyword);
        _searchFinished = true;
      }
      while (true) {
        final SignupSnapshot s;
        try {
          s = await _snapshot();
        } on _PlaybackFailed catch (failure) {
          // The error card belongs to one feed post: skip it through the
          // verified page Next, at most three posts in a row.
          final feed = NurtureVideo.feedNavigation(failure.snapshot);
          if (feed == null || ++_playbackSkips > 3) rethrow;
          debugPrint('Nurture feed: skipping a post TikTok cannot play');
          await _tap(
            'feed/skip-unreadable/next-video',
            failure.snapshot,
            feed.next,
          );
          await _waitForFeedChange(feed.key);
          missingSince = null;
          await _sleep(1500);
          continue;
        }
        if (continueOnCommentError &&
            (_pendingCommentDraft ||
                [...s.nodes, ...s.hiddenNodes].any(
                  (n) =>
                      n.editable &&
                      n.length > 0 &&
                      n.bounds.center.dy > s.viewport.bounds.center.dy,
                ))) {
          _pendingCommentDraft = true;
          _commentsBlocked = true;
          if (!_draftReported) {
            _draftReported = true;
            onCommentSkipped?.call(
              'Giữ bản nháp bình luận; tiếp tục xem đến hết thời gian nuôi.',
            );
          }
          await _sleep();
          continue;
        }
        if (NurtureVideo.isLiveRoom(s)) {
          missingSince = null;
          await _skipLiveRoom(s);
          continue;
        }
        final video = NurtureVideo.read(s);
        final live = video == null ? NurtureVideo.liveNext(s) : null;
        if (live != null) {
          missingSince = null;
          await _skipLive(s, live);
          continue;
        }
        final feed = video == null ? NurtureVideo.feedNavigation(s) : null;
        final stuck = video == null ? NurtureVideo.playerNext(s) : null;
        if ((stuck != null || feed != null) &&
            missingSince != null &&
            _now().difference(missingSince) > const Duration(seconds: 10)) {
          // Feed and search posts can omit a usable clock indefinitely.
          // Skip only through a verified next control, without counting them.
          if (++unplayable > 3) {
            throw NurturePlaybackUnavailable(
              'Nhiều bài liên tiếp không đọc được tiến độ; đã dừng nuôi.',
            );
          }
          if (feed != null) {
            debugPrint('Nurture feed: skipping post without playback progress');
            await _tap('feed/skip-unreadable/next-video', s, feed.next);
            await _waitForFeedChange(feed.key);
          } else {
            final a = s.viewport.fromScreen(stuck!.bounds.topLeft);
            await _tap(
              'detail/feed/skip-unplayable/${a.dx.round()}-${a.dy.round()}',
              s,
              stuck,
            );
          }
          missingSince = null;
          await _sleep(1500);
          continue;
        }
        if (video == null) {
          missingSince ??= _now();
          if (_now().difference(missingSince) > const Duration(seconds: 20)) {
            throw NurturePlaybackUnavailable(
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
        if (video.key != frozenKey || video.position != frozenAt) {
          if (video.key == frozenKey) stalls = 0;
          frozenKey = video.key;
          frozenAt = video.position;
          frozenSince = _now();
        } else if (!plan.completed &&
            _now().difference(frozenSince) > _stallWait) {
          // Playback stopped while the clock stays readable. Skip the post
          // through the verified Next; a page that keeps stalling recovers.
          if (++stalls > 3) {
            throw NurturePlaybackUnavailable(
              'Video đứng hình nhiều bài liên tiếp; cần phục hồi.',
            );
          }
          debugPrint(
            'Nurture playback stalled at '
            '${video.position}/${video.duration}; skipping post',
          );
          frozenKey = null;
          plan.stalled = true;
          await _advance(s, video, plan);
          continue;
        }
        if (plan.completed ||
            (!plan.full && plan.watched >= plan.skipAt) ||
            (plan.full && plan.cap != null && plan.watched >= plan.cap!)) {
          await _advance(s, video, plan);
        } else if (!plan.likeAttempted &&
            plan.likeAt >= 0 &&
            video.position >= plan.likeAt &&
            video.like != null) {
          plan.likeAttempted = true; // One tap per post; never retried.
          await _likeSafely(s, video);
        } else if (plan.full &&
            video.targetsVerified &&
            !_commentsBlocked &&
            !plan.commentAttempted &&
            plan.commentAt >= 0 &&
            video.position >= plan.commentAt) {
          plan.commentAttempted =
              true; // Retained across pause/resume and errors.
          if (video.position + 3 < video.duration * _commentDeadlineRatio) {
            try {
              await _comment(s, video);
            } on StateError catch (error) {
              if (!continueOnCommentError) rethrow;
              _check();
              _commentsBlocked = true;
              onCommentSkipped?.call(
                '${error.message} Tiếp tục xem, không gửi lại bình luận.',
              );
            }
          }
        }
        await _sleep();
      }
    } on NurtureCancelled {
      // A timer, navigation or app lifecycle stopped this session.
    } finally {
      _holdingKeyboard = false;
      _keyboardRenewedAt = null;
      unawaited(
        accessibility.releaseKeyboardSuppression().catchError((Object _) {
          // The native lease restores the IME by itself.
        }),
      );
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
        final s = await _snapshot(trackPlayback: false);
        if (NurtureVideo.isLiveRoom(s)) {
          await _skipLiveRoom(s);
          return;
        }
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
        debugPrint('Nurture search step: $name');
        if (name == 'scroll-results') {
          final region = node.bounds.intersect(s.viewport.bounds);
          Future<Offset> endpoint(String key, double fraction) =>
              profile.target(
                'search/scroll-results/$key',
                s.viewport,
                SignupNode({
                  'id': node.id,
                  'bounds': [
                    region.right - region.width * .08,
                    region.top + region.height * fraction - 2,
                    region.right - region.width * .04,
                    region.top + region.height * fraction + 2,
                  ],
                }),
              );
          final from = await endpoint('from', .8);
          final to = await endpoint('to', .2);
          _check();
          await accessibility.swipe(s.viewport, from, to);
        } else if (name == 'paste') {
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
      await _releaseKeyboard();
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
        .where((n) => n.clickable && n.enabled && n.name == 'Videos')
        .firstOrNull;
    final query = keyword.toLowerCase();
    final viewAll = s.nodes
        .where(
          (n) =>
              n.text.trim().startsWith('View all results for') &&
              n.text.toLowerCase().contains(query),
        )
        .firstOrNull;
    final drawer = s.nodes
        .where(
          (n) =>
              n.editable &&
              // The desktop drawer's box is narrower (about 15% of the
              // page) but sits right of the sidebar column the open step uses.
              (n.bounds.width > v.width * .2 ||
                  (n.bounds.width > v.width * .1 &&
                      n.bounds.center.dx >= v.left + v.width * .1)) &&
              n.bounds.center.dx < v.left + v.width * .5 &&
              !n.bounds.intersect(v).isEmpty &&
              !RegExp('comment', caseSensitive: false).hasMatch(n.hint),
        )
        .firstOrNull;
    if (drawer != null) {
      // Gecko can keep the search drawer open after submitting. The results
      // behind it are still accessible, but their tap targets are covered.
      // Some search layouts have no Videos tab at all. Once submitted, close
      // the drawer independently of the tabs so it cannot cover the grid.
      if ((fired['view-all'] ?? 0) > 0) {
        final close = s.nodes
            .where(
              (n) =>
                  n.clickable &&
                  n.enabled &&
                  n.name == 'Close' &&
                  n.bounds.center.dx < v.left + v.width * .5,
            )
            .firstOrNull;
        return close == null ? null : ('close-search', close);
      }
      if (viewAll != null) {
        // Let a slow navigation use the full search deadline after two taps.
        return (fired['view-all'] ?? 0) < 2 ? ('view-all', viewAll) : null;
      }
      if (!drawer.focused) return ('focus-search', drawer);
      return (fired['paste'] ?? 0) == 0 ? ('paste', drawer) : null;
    }
    if ((fired['view-all'] ?? 0) == 0) {
      // The For You feed exposes "Watch in full screen" too. Open and submit
      // search first, even if a feed video or an old results grid is visible.
      if (viewAll != null) return ('view-all', viewAll);
      final sidebar = s.nodes
          .where(
            (n) => n.editable && n.bounds.center.dx < v.left + v.width * .1,
          )
          .firstOrNull;
      return sidebar == null ? null : ('open', sidebar);
    }
    if (videosTab != null) {
      // The Top tab mixes in users and LIVE rooms; Videos holds only posts.
      if ((fired['videos-tab'] ?? 0) == 0) return ('videos-tab', videosTab);
    }
    // Gecko also exposes a combined results page without tab controls. Its
    // video tiles have the same accessible button as the Videos grid, but
    // LIVE previews reuse it too: exclude any tile containing a LIVE badge.
    final feedRoots = s.nodes
        .where(
          (n) => RegExp(
            r'^Read or add comments\b',
            caseSensitive: false,
          ).hasMatch(n.name),
        )
        .where((n) => n.id.split('.').length >= 3)
        .map((n) => n.id.split('.').take(n.id.split('.').length - 2).join('.'))
        .toSet();
    final tiles = s.nodes
        .where(
          (n) =>
              n.clickable &&
              n.enabled &&
              n.name == 'Watch in full screen' &&
              // A slow search navigation can leave the old feed visible after
              // submission. Never click its media while waiting for the grid.
              !feedRoots.any(
                (root) => n.id == root || n.id.startsWith('$root.'),
              ) &&
              v.contains(n.bounds.topLeft) &&
              n.bounds.bottom <= v.bottom &&
              !s.nodes.any(
                (child) =>
                    (child.id.startsWith('${n.id}.') ||
                        n.bounds.contains(child.bounds.center)) &&
                    RegExp(
                      r'^(LIVE|LIVE now|Watch LIVE|Click to watch LIVE|Join my LIVE)$',
                      caseSensitive: false,
                    ).hasMatch(child.name),
              ),
        )
        .toList();
    if (tiles.isNotEmpty) {
      return ('result', tiles[_random.nextInt(min(tiles.length, 8))]);
    }
    // Desktop combined results can show two rows of LIVE before any post,
    // with no Videos tab. Scroll only a verified results container holding
    // an offscreen post; never guess a tile or enter a LIVE preview.
    if (videosTab == null && (fired['scroll-results'] ?? 0) < 2) {
      final below = s.hiddenNodes.where(
        (n) => n.name == 'Watch in full screen' && n.bounds.top >= v.bottom,
      );
      final scroll = s.nodes
          .where(
            (n) =>
                n.scrollable &&
                n.enabled &&
                n.bounds.intersect(v).width >= v.width * .5 &&
                n.bounds.intersect(v).height >= v.height * .7 &&
                below.any((tile) => tile.id.startsWith('${n.id}.')),
          )
          .firstOrNull;
      if (scroll != null) return ('scroll-results', scroll);
    }
    return null;
  }

  Future<void> _skipLiveRoom(SignupSnapshot s) async {
    final exit = NurtureVideo.liveRoomExit(s);
    if (exit == null) {
      throw StateError('Không tìm thấy nút rời phòng LIVE; đã dừng nuôi.');
    }
    debugPrint('Nurture LIVE room: returning to For You');
    await _tap('live/room/for-you', s, exit);
    final deadline = _now().add(const Duration(seconds: 10));
    while (_now().isBefore(deadline)) {
      await _sleep();
      final current = await _snapshot(trackPlayback: false);
      if (!NurtureVideo.isLiveRoom(current)) return;
    }
    throw StateError('Chưa rời được phòng LIVE; đã dừng nuôi.');
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
    debugPrint(
      'Nurture advance: layout=${video.orientation.name} '
      'position=${video.position}/${video.duration} '
      'action=${video.next != null ? 'tap' : 'swipe'}',
    );
    // A timeout cannot prove the first gesture failed. A resumed runner reads
    // the same document without dispatching Next twice for the same post.
    if (_advanceAttempted.contains(video.key)) {
      debugPrint('Nurture advance: waiting for the previously requested post');
    } else if (video.next != null) {
      try {
        await _tap(
          '${video.orientation.name}/feed/next-video',
          s,
          video.next!,
          beforeDispatch: (point) async {
            var fresh = await _snapshot();
            var current = NurtureVideo.read(fresh);
            // Between posts the player briefly exposes no clock.
            for (var i = 0; current == null && i < 10; i++) {
              await _sleep(200);
              fresh = await _snapshot();
              current = NurtureVideo.read(fresh);
            }
            // A post that ends autoplays the next one; tapping now would
            // skip that one unwatched. A photo post is known by its URL.
            final post = current == null && video.detail
                ? NurtureVideo.playerPost(fresh)
                : null;
            if ((current != null &&
                    current.key != video.key &&
                    current.detail == video.detail) ||
                (post != null && !video.key.startsWith('detail|$post|'))) {
              throw _AdvancedBeforeTap(current);
            }
            final next = current?.next;
            if (current == null ||
                _pendingCommentDraft ||
                fresh.keyboardVisible ||
                next == null ||
                fresh.viewport.bounds != s.viewport.bounds ||
                !next.bounds.contains(fresh.viewport.toScreen(point))) {
              throw StateError(
                'Nút Next hoặc ô nhập đã thay đổi; chờ phục hồi.',
              );
            }
            _advanceAttempted.add(video.key);
          },
        );
      } on _AdvancedBeforeTap catch (moved) {
        debugPrint('Nurture advance: TikTok already moved on; no Next tap');
        await _finish(plan);
        _previous = moved.video;
        return;
      }
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
      _advanceAttempted.add(video.key);
      await accessibility.swipe(s.viewport, a, b);
    }
    // One advance only. No repeat if the UI failed to move. The next post is
    // unreadable until its clock reports a duration, which slow loads (large
    // screens, landscape posts) can push well past a few seconds.
    await _sleep(1200); // Let scrolling and Gecko's accessibility tree settle.
    final deadline = _now().add(const Duration(seconds: 30));
    String? lastState;
    String? candidate;
    DateTime? candidateAt;
    int? candidatePosition;
    while (_now().isBefore(deadline)) {
      await _sleep();
      final snapshot = await _snapshot();
      if (NurtureVideo.isLiveRoom(snapshot)) {
        await _skipLiveRoom(snapshot);
        continue;
      }
      final current = NurtureVideo.read(snapshot);
      final feed = current == null && !video.detail
          ? NurtureVideo.feedNavigation(snapshot)
          : null;
      final previousFeedKey = video.key.substring(
        0,
        video.key.lastIndexOf('|'),
      );
      // A photo post in the search player has no clock; its URL changes.
      final post = current == null && video.detail
          ? NurtureVideo.playerPost(snapshot)
          : null;
      final unreadableNext =
          (feed != null && feed.key != previousFeedKey) ||
          (post != null && 'detail|$post' != previousFeedKey);
      final state = current == null
          ? 'unreadable'
          : current.key == video.key
          ? 'same-video'
          : 'changed-video';
      if (state != lastState) {
        lastState = state;
        final clocks = [...snapshot.nodes, ...snapshot.hiddenNodes]
            .where((n) => NurtureVideo._time.hasMatch(n.text.trim()))
            .map((n) => n.text.trim())
            .join(', ');
        debugPrint('Nurture advance check: $state clocks=[$clocks]');
      }
      if ((current != null && current.key != video.key) || unreadableNext) {
        final key = current?.key ?? feed?.key ?? 'detail|$post';
        if (candidate != key) {
          candidate = key;
          candidateAt = _now();
          candidatePosition = current?.position;
          continue;
        }
        // Do not act on a single prefetched frame while the page is scrolling.
        if (_now().difference(candidateAt!) <
                const Duration(milliseconds: 800) ||
            (current != null && current.position == candidatePosition)) {
          continue;
        }
        await _finish(plan);
        _previous = current;
        return;
      }
      candidate = null;
    }
    throw NurturePlaybackUnavailable(
      lastState == 'unreadable'
          ? 'Chưa đọc được tiến độ video sau Next (30 giây); cần phục hồi.'
          : 'Chưa xác nhận được video mới sau Next (30 giây); cần phục hồi.',
    );
  }

  /// Counts a post once when the feed has moved past it.
  Future<void> _finish(_WatchPlan plan) async {
    if (plan.completed) return;
    plan.completed = true;
    // A capped long video counts as watched, not skipped.
    if (plan.full && !plan.stalled) {
      _full++;
    } else {
      _skipped++;
    }
    await _emit();
  }

  Future<void> _waitForFeedChange(String previousKey) async {
    await _sleep(1200);
    final deadline = _now().add(const Duration(seconds: 30));
    while (_now().isBefore(deadline)) {
      await _sleep();
      // The skipped post's error card can linger while the feed scrolls; it
      // must not abort the wait and lead to a second Next.
      final s = await _snapshot(trackPlayback: false);
      if (NurtureVideo.isLiveRoom(s)) return;
      final video = NurtureVideo.read(s);
      if (video != null &&
          !video.detail &&
          video.key.substring(0, video.key.lastIndexOf('|')) != previousKey) {
        return;
      }
      final next = NurtureVideo.feedNavigation(s);
      if (next != null && next.key != previousKey) return;
    }
    throw NurturePlaybackUnavailable(
      'Chưa xác nhận được bài mới sau khi bỏ qua bài không có tiến độ; đã dừng nuôi.',
    );
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
          // Continue quietly without counting or retrying a rolled-back like.
          return;
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
    bool Function(SignupSnapshot) ready, {
    required String stage,
  }) async {
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
      final editors = s.editors
          .map((n) => '${n.length}${n.focused ? '*' : ''}')
          .join('/');
      seen =
          'bàn phím ${s.keyboardVisible ? 'hiện' : 'ẩn'}, ô nhập '
          '${editors.isEmpty ? 'không có' : editors}';
    } while (_now().isBefore(until));
    debugPrint('Nurture comment wait timed out [$stage]: $seen');
    throw _CommentNotReady('Bình luận chưa sẵn sàng ở bước $stage ($seen).');
  }

  /// A missed opening tap leaves only the feed's search field exposed. Check
  /// hidden and disabled fields too: an unrecognized editor may hold a draft.
  bool _commentPanelAbsent(SignupSnapshot s) =>
      !s.keyboardVisible &&
      s.find(RegExp(r'^exit$', caseSensitive: false), enabled: false) == null &&
      ![...s.nodes, ...s.hiddenNodes].any(
        (n) =>
            n.editable &&
            !RegExp(r'^search$', caseSensitive: false).hasMatch(n.hint.trim()),
      );

  Future<bool> _closeEmptyComments() async {
    var s = await _snapshot();
    final editor = _editorMetadata(s);
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
        if (_editorMetadata(fresh)?.length != 0 ||
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

  /// Hidden fields supply draft metadata only. All input gestures still use
  /// [_editor], which requires a visible, enabled control.
  SignupNode? _editorMetadata(SignupSnapshot s) {
    final fields = {
      for (final n in [...s.hiddenNodes, ...s.nodes])
        if (n.editable &&
            RegExp('comment|bình luận', caseSensitive: false).hasMatch(n.hint))
          n.id: n,
    }.values;
    return fields.length == 1 ? fields.single : null;
  }

  int _matches(SignupSnapshot s, String text) =>
      s.nodes.where((n) => !n.editable && n.text.trim() == text.trim()).length;

  SignupNode? _visiblePost(SignupSnapshot s, {bool enabled = true}) {
    final post = s.find(
      RegExp(r'^Post$', caseSensitive: false),
      enabled: enabled,
    );
    if (post == null || post.bounds.isEmpty) return null;
    final viewport = s.viewport.bounds;
    return viewport.contains(post.bounds.topLeft) &&
            post.bounds.right <= viewport.right &&
            post.bounds.bottom <= viewport.bottom
        ? post
        : null;
  }

  /// One accepted ACTION_CLICK on the clipped Post beside the filled editor.
  /// A refused attempt (Post not yet enabled) clicked nothing and is retried;
  /// an accepted one is never repeated. The text is already in the editor,
  /// so a short post crossing its midpoint meanwhile still gets it published
  /// rather than leaving a draft that blocks Next for the rest of the session.
  Future<void> _clickClippedPost(NurtureVideo video) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      // A returning keyboard drops the filled editor from Gecko's tree. The
      // snapshot afterwards also refreshes the node cache submit reads.
      await accessibility.setKeyboardSuppressed(true);
      _check();
      await _sameVideo(video.key);
      if (await accessibility.submitComment()) return;
      _check();
      await _sleep(1000);
    }
    throw StateError('Chưa bấm được nút Post bị khuất; đã giữ bản nháp.');
  }

  Future<void> _comment(SignupSnapshot s, NurtureVideo video) async {
    var pasteAttempted = false, keepSuppressed = false;
    // Gecko lays the search player's comment column past the WebView's right
    // edge. Its Post cannot be tapped, but Accessibility ACTION_CLICK
    // activates it without coordinates while the filled editor stays in the
    // tree (keyboard suppressed). Verified on the emulator 2026-10-24.
    var clippedPost = false;
    try {
      final kind = video.orientation.name;
      if (video.detail) {
        // The search-result player keeps its comment box open beside it.
        s = await _waitFor(
          video.key,
          (s) => _editor(s) != null,
          stage: 'tìm ô bình luận',
        );
        final reveal = await accessibility.revealCommentPost(_editor(s)!);
        _check();
        clippedPost = reveal['reason'] == 'post-offscreen';
        if (reveal['ok'] != true && !clippedPost) {
          if (reveal['reason'] == 'draft-exists') {
            _pendingCommentDraft = true;
            throw StateError('Có bình luận đang soạn; đã giữ bản nháp.');
          }
          throw _CommentNotReady(
            'Chưa đưa được nút Post vào khung (${reveal['reason']}).',
          );
        }
        if (!clippedPost) {
          await _sleep(500);
          s = await _waitFor(
            video.key,
            (s) =>
                _editor(s) != null && _visiblePost(s, enabled: false) != null,
            stage: 'đưa nút Post vào khung',
          );
        }
      } else {
        await _tap(
          video.commentsKey(s.viewport),
          s,
          video.comments!,
          beforeDispatch: (point) async {
            final fresh = await _sameVideo(video.key);
            final button = NurtureVideo.read(fresh)?.comments;
            if (button == null ||
                fresh.viewport.bounds != s.viewport.bounds ||
                !button.bounds.contains(fresh.viewport.toScreen(point))) {
              throw const _CommentNotReady(
                'Nút bình luận đang thay đổi vị trí.',
              );
            }
          },
        );
        s = await _waitFor(
          video.key,
          (s) => _editor(s) != null && _close(s) != null,
          stage: 'mở khung bình luận',
        );
      }
      if (NurtureVideo.read(s)!.position + 4 >=
          video.duration * _commentDeadlineRatio) {
        throw const _CommentNotReady(
          'Không còn đủ thời gian để nhập bình luận.',
        );
      }
      final editor = _editor(s)!;
      if (editor.length != 0) {
        _pendingCommentDraft = true;
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
        s = await _waitFor(
          video.key,
          (s) => _editor(s)?.focused == true,
          stage: 'đặt con trỏ vào ô bình luận',
        );
        _check();
        pasteAttempted = true;
        _pendingCommentDraft = true;
        final result = await accessibility.paste(text, 'comment');
        _check();
        if (result['ok'] != true) {
          final reason = '${result['reason']}';
          if (reason.startsWith('editor-unavailable') ||
              reason == 'paste-rejected' ||
              reason == 'paste-not-inserted') {
            // Nothing reached the editor (verified empty): no draft to keep.
            pasteAttempted = false;
            _pendingCommentDraft = false;
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
        if (!keepSuppressed) await _releaseKeyboard();
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
            stage: 'xác nhận nội dung đã nhập',
          );
          if (NurtureVideo.read(s)!.position + 1 >=
              video.duration * _commentDeadlineRatio) {
            throw StateError(
              'Đã quá thời điểm bình luận; đã dừng và giữ bản nháp.',
            );
          }
          if (clippedPost) {
            await _clickClippedPost(video);
          } else {
            s = await _waitFor(
              video.key,
              (s) => !s.keyboardVisible && _visiblePost(s) != null,
              stage: 'tìm nút Post trong khung',
            );
            final post = _visiblePost(s)!;
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
                final button = _visiblePost(fresh);
                if (fresh.keyboardVisible ||
                    fresh.viewport.bounds != s.viewport.bounds ||
                    button == null ||
                    !button.bounds.contains(fresh.viewport.toScreen(point)) ||
                    current.position + 1 >=
                        current.duration * _commentDeadlineRatio) {
                  throw StateError(
                    'Nút Post hoặc thời điểm gửi đã đổi; đã giữ bản nháp.',
                  );
                }
              },
            );
          }
          _check();
          s = await _waitFor(
            video.key,
            (s) => _editor(s)?.length == 0 && _matches(s, text) > baseline,
            stage: 'xác nhận bình luận đã gửi',
          );
          _comments++;
          _pendingCommentDraft = false;
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
          await _releaseKeyboard();
        }
        return;
      } else {
        s = await _waitFor(
          video.key,
          (s) =>
              !s.keyboardVisible &&
              s.find(RegExp(r'^Post$', caseSensitive: false)) != null,
          stage: 'tìm nút gửi bình luận',
        );
        if (NurtureVideo.read(s)!.position + 1 >=
            video.duration * _commentDeadlineRatio) {
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
                current.position + 1 >=
                    current.duration * _commentDeadlineRatio) {
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
        stage: 'xác nhận bình luận đã gửi',
      );
      _comments++;
      _pendingCommentDraft = false;
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
      await _waitFor(
        video.key,
        (s) => _close(s) == null,
        stage: 'đóng khung bình luận',
      );
    } on _CommentNotReady catch (error) {
      if (!pasteAttempted) {
        // Gecko can omit the detail editor while it is unfocused. No paste
        // was attempted, so an unavailable editor does not introduce a draft.
        // A visible existing draft still prevents advancing to another post.
        final fresh = await _snapshot();
        final canContinue =
            NurtureVideo.read(fresh)?.key == video.key &&
            (video.detail
                ? (_editorMetadata(fresh)?.length ?? 0) == 0
                : _commentPanelAbsent(fresh) || await _closeEmptyComments());
        if (canContinue) {
          onCommentSkipped?.call(
            '${error.message} Bỏ qua bình luận này và tiếp tục nuôi.',
          );
          return;
        }
      }
      throw StateError(
        '${error.message} Đã dừng và giữ bản nháp; không gửi lại.',
      );
    }
  }
}
