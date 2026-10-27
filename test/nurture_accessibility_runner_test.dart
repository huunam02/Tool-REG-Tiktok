import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/nurture_accessibility_runner.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

/// Draws every rate (0 < any rate). `full: false` runs pair it with
/// `longWatchRate: 0` and `commentRate: 0` so the post is swiped early.
class _Random implements Random {
  _Random(this.full);
  final bool full;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => full;
  @override
  int nextInt(int max) => 0;
}

/// Always draws the latest random choice.
class _LatestRandom implements Random {
  @override
  double nextDouble() => 0.999;
  @override
  bool nextBool() => true;
  @override
  int nextInt(int max) => max - 1;
}

Map<String, dynamic> _node(
  String id,
  Rect b, {
  String text = '',
  String description = '',
  String hint = '',
  bool editor = false,
  bool focused = false,
  int length = 0,
  bool clickable = false,
  bool enabled = true,
}) => {
  'id': id,
  'bounds': [b.left, b.top, b.right, b.bottom],
  'text': text,
  'description': description,
  'hint': hint,
  'editable': editor,
  'focused': focused,
  'length': length,
  'clickable': clickable,
  'enabled': enabled,
};

String _clock(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

Map<String, dynamic> _frame({
  int position = 0,
  int duration = 30,
  bool landscape = false,
  bool panel = false,
  bool focused = false,
  int length = 0,
  bool posted = false,
  String card = '0.1',
  String? likes,
}) {
  const vp = Rect.fromLTWH(0, 0, 400, 800);
  final media = landscape
      ? const Rect.fromLTWH(40, 250, 300, 170)
      : const Rect.fromLTWH(80, 70, 250, 500);
  return {
    'ready': true,
    'webBounds': [vp.left, vp.top, vp.right, vp.bottom],
    'nodes': [
      _node(card, vp),
      _node('$card.0', media),
      _node(
        '$card.0.2',
        Rect.fromLTWH(media.left, media.bottom - 30, media.width, 20),
      ),
      _node(
        '$card.0.2.0',
        Rect.fromLTWH(media.left, media.bottom - 30, media.width, 20),
        text: '${_clock(position)} / ${_clock(duration)}',
      ),
      _node('$card.1', const Rect.fromLTWH(350, 260, 30, 310)),
      _node(
        '$card.1.0.0',
        const Rect.fromLTWH(350, 260, 30, 30),
        text: 'creator',
      ),
      _node(
        '$card.1.2',
        Rect.fromLTWH(350, landscape ? 340 : 450, 30, 30),
        description: 'Read or add comments 5 comments',
        clickable: true,
      ),
      if (likes != null)
        {
          ..._node(
            '$card.1.1.0',
            const Rect.fromLTWH(350, 400, 30, 30),
            text: 'Like video $likes likes',
            clickable: true,
          ),
          'className': 'android.widget.ToggleButton',
        },
      if (panel) ...[
        _node(
          'panel.editor',
          const Rect.fromLTWH(290, 750, 80, 30),
          hint: 'Add comment...',
          editor: true,
          focused: focused,
          length: length,
          clickable: true,
        ),
        _node(
          'panel.post',
          const Rect.fromLTWH(375, 750, 20, 30),
          description: 'Post',
          clickable: true,
          enabled: length > 0,
        ),
        _node(
          'panel.close',
          const Rect.fromLTWH(380, 10, 20, 20),
          description: 'exit',
          clickable: true,
        ),
        if (posted)
          _node(
            'panel.comment',
            const Rect.fromLTWH(290, 80, 90, 30),
            text: 'Configured comment',
          ),
      ],
    ],
  };
}

Map<String, dynamic> _liveFrame({String badge = 'LIVE now'}) {
  const vp = Rect.fromLTWH(0, 0, 400, 800);
  return {
    'ready': true,
    'webBounds': [vp.left, vp.top, vp.right, vp.bottom],
    'nodes': [
      _node('p', vp),
      _node('p.0.0', const Rect.fromLTWH(40, 200, 300, 470)),
      _node('p.0.0.1', const Rect.fromLTWH(60, 600, 80, 20), text: badge),
      {
        ..._node(
          'p.1.0.0.0',
          const Rect.fromLTWH(380, 400, 16, 16),
          clickable: true,
        ),
        'className': 'android.widget.Button',
      },
      {
        ..._node(
          'p.1.0.1.0',
          const Rect.fromLTWH(380, 425, 16, 16),
          clickable: true,
        ),
        'className': 'android.widget.Button',
      },
    ],
  };
}

class _Service extends SignupAccessibility {
  DateTime clock = DateTime(2026);
  bool landscape = false,
      panel = false,
      focused = false,
      posted = false,
      keyboard = false,
      moved = false,
      allowMove = true,
      stall = false;
  bool confirmPost = true, suppressed = false;
  bool focusWorks = true, hiddenEditor = false;
  bool openWorks = true, searchEditor = false;
  int missingClockAfterOpen = 0, missingClockFrames = 0, panelDelaySeconds = 0;
  int closes = 0;

  /// The like toggle's count label; null exposes no toggle.
  String? likes;

  /// TikTok shows each like, then rolls back a rejected one after 3s.
  bool likeWorks = true, likeAccepted = true;
  int likeTaps = 0;
  DateTime? _rollbackAt;
  DateTime? postedAt;
  String? publicComment;
  final keyboardPolicies = <bool>[];
  int length = 0, taps = 0, swipes = 0, posts = 0, pastes = 0;
  int? forcePosition;
  int unreadyFrames = 0;
  int duration = 30;

  /// The next post's clock is missing until it loads after a swipe.
  int loadSecondsAfterMove = 0;
  bool playbackErrorAfterMove = false;
  DateTime? _loadedAt;

  String? pasteReason;
  bool live = false;
  String liveBadge = 'LIVE now';
  int liveSkips = 0;

  /// A popup outside the card is exposed until this time.
  DateTime? dialogUntil;
  Completer<SignupSnapshot>? blockedSnapshot;
  final snapshotEntered = Completer<void>();
  @override
  Future<SignupSnapshot> snapshot() async {
    if (!snapshotEntered.isCompleted) snapshotEntered.complete();
    if (blockedSnapshot case final pending?) return pending.future;
    if (unreadyFrames > 0) {
      unreadyFrames--;
      return SignupSnapshot({'ready': false});
    }
    if (live) return SignupSnapshot(_liveFrame(badge: liveBadge));
    final data = {
      ..._frame(
        position:
            forcePosition ??
            (stall ? 0 : clock.difference(DateTime(2026)).inSeconds % duration),
        duration: duration,
        landscape: landscape,
        panel: panel,
        focused: focused,
        length: length,
        posted: posted,
        card: moved ? '0.2' : '0.1',
        likes: likes,
      ),
      'keyboardVisible': keyboard,
    };
    if (_rollbackAt != null && !clock.isBefore(_rollbackAt!)) {
      _rollbackAt = null;
      likes = '${int.parse(likes!) - 1}';
    }
    final nodes = data['nodes'] as List;
    if (searchEditor) {
      nodes.add(
        _node(
          'search',
          const Rect.fromLTWH(10, 20, 30, 20),
          hint: 'Search',
          editor: true,
        ),
      );
    }
    if (moved && playbackErrorAfterMove) {
      final media = nodes.firstWhere((n) => n['id'] == '0.2.0');
      media['text'] = 'Watch in full screen';
      media['clickable'] = true;
      nodes.removeWhere((n) => n['id'] == '0.2.0.2.0');
      nodes.add(
        _node(
          '0.2.0.error',
          const Rect.fromLTWH(100, 280, 200, 20),
          text:
              "We're having trouble playing this video. Please refresh and try again.",
        ),
      );
    }
    if (hiddenEditor) {
      data['hidden'] = nodes.where((n) => n['id'] == 'panel.editor').toList();
      nodes.removeWhere((n) => n['id'] == 'panel.editor');
    }
    if (dialogUntil != null && clock.isBefore(dialogUntil!)) {
      nodes.add({
        ..._node('9', const Rect.fromLTWH(100, 300, 200, 100)),
        'className': 'android.app.Dialog',
      });
      nodes.add(
        _node('9.0', const Rect.fromLTWH(110, 310, 180, 30), text: 'Popup'),
      );
    }
    if (moved && _loadedAt != null && clock.isBefore(_loadedAt!)) {
      nodes.removeWhere((n) => (n['text'] as String).contains(' / '));
    }
    if (panel && missingClockFrames > 0) {
      missingClockFrames--;
      nodes.removeWhere((n) => (n['text'] as String).contains(' / '));
    }
    if (panel && publicComment != null) {
      nodes.add(
        _node(
          'panel.public',
          const Rect.fromLTWH(290, 100, 90, 30),
          text: publicComment!,
        ),
      );
    }
    return SignupSnapshot(data);
  }

  Future<void> delay(Duration d) async {
    clock = clock.add(d);
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset p) async {
    taps++;
    if (live) {
      if (const Rect.fromLTWH(380, 425, 16, 16).contains(p)) {
        liveSkips++;
        live = false;
      }
      return;
    }
    if (likes != null && const Rect.fromLTWH(350, 400, 30, 30).contains(p)) {
      likeTaps++;
      final count = int.tryParse(likes!);
      if (likeWorks && count != null) {
        likes = '${count + 1}';
        if (!likeAccepted) _rollbackAt = clock.add(const Duration(seconds: 3));
      }
      return;
    }
    if (!panel) {
      if (openWorks) {
        panel = true;
        missingClockFrames = missingClockAfterOpen;
        clock = clock.add(Duration(seconds: panelDelaySeconds));
      }
    } else if (p.dy < 50) {
      panel = false;
      closes++;
    } else if (p.dx > 370) {
      posts++;
      postedAt ??= clock;
      posted = confirmPost;
      length = 0;
    } else {
      focused = focusWorks;
      keyboard = !suppressed;
    }
  }

  @override
  Future<void> swipe(SignupViewport viewport, Offset a, Offset b) async {
    swipes++;
    if (allowMove) moved = true;
    _loadedAt = clock.add(Duration(seconds: loadSecondsAfterMove));
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pastes++;
    expect(field, 'comment');
    if (pasteReason != null) return {'ok': false, 'reason': pasteReason};
    length = text.length;
    typed = text;
    // The search player moved on while the text was going in.
    if (moveOnPaste) moved = true;
    return {'ok': true};
  }

  bool moveOnPaste = false;

  /// Text this fake's editor holds from the runner's own paste.
  String? typed;
  bool clearWorks = true;
  int clears = 0;

  @override
  Future<bool> clearComment(String expected) async {
    clears++;
    if (typed != expected) return typed == null;
    if (!clearWorks) return false;
    typed = null;
    length = 0;
    return true;
  }

  @override
  Future<void> setKeyboardSuppressed(bool value) async {
    suppressed = value;
    keyboardPolicies.add(value);
  }

  @override
  Future<void> renewKeyboardSuppression() => setKeyboardSuppressed(true);

  @override
  Future<void> releaseKeyboardSuppression() => setKeyboardSuppressed(false);

  @override
  Future<void> dismissKeyboard() async {
    keyboard = false;
  }

  @override
  Future<void> cancelPaste() async {}
}

class _ServerErrorService extends _Service {
  _ServerErrorService({
    this.recoverAfter = 1,
    this.scenario = 'error',
    this.searchPlayer = false,
  });
  final int recoverAfter;
  final String scenario;
  final bool searchPlayer;
  int retries = 0;
  final retryTimes = <DateTime>[];

  @override
  Future<SignupSnapshot> snapshot() async {
    if (retries >= recoverAfter) {
      if (searchPlayer) {
        return (_SearchService()
              ..state = 'player'
              ..clock = clock)
            .snapshot();
      }
      return super.snapshot();
    }
    final nodes = <Map<String, dynamic>>[
      _node('error', const Rect.fromLTWH(80, 200, 280, 160)),
      if (scenario != 'missing-title')
        _node(
          'error.title',
          const Rect.fromLTWH(120, 240, 200, 20),
          text: 'Something went wrong',
        ),
      if (scenario != 'missing-details')
        _node(
          'error.details',
          const Rect.fromLTWH(80, 270, 280, 20),
          text: 'Sorry, something wrong with the server, please try again.',
        ),
      if (scenario != 'missing-button')
        _node(
          'error.retry',
          Rect.fromLTWH(scenario == 'offscreen' ? 410 : 180, 310, 80, 20),
          text: 'Try again',
          clickable: true,
          enabled: scenario != 'disabled',
        ),
      if (scenario == 'duplicate')
        _node(
          'error.retry2',
          const Rect.fromLTWH(180, 340, 80, 20),
          text: 'Try again',
          clickable: true,
        ),
      if (scenario == 'caption')
        ...(_frame()['nodes'] as List).cast<Map<String, dynamic>>(),
      if (scenario == 'draft')
        _node(
          'hidden-draft',
          const Rect.fromLTWH(290, 750, 70, 20),
          editor: true,
          hint: '',
          length: 5,
        ),
      if (scenario == 'captcha')
        _node(
          'captcha',
          const Rect.fromLTWH(90, 400, 200, 20),
          text: 'Verify to continue',
        ),
      if (scenario == 'login')
        _node(
          'login',
          const Rect.fromLTWH(90, 400, 200, 20),
          text: 'Log in to TikTok',
        ),
    ];
    return SignupSnapshot({
      'ready': true,
      'webBounds': [0, 0, 400, 800],
      'nodes': nodes,
    });
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset p) async {
    expect(const Rect.fromLTWH(180, 310, 80, 20).contains(p), isTrue);
    retries++;
    retryTimes.add(clock);
  }
}

class _UnreadableFeedService extends _Service {
  _UnreadableFeedService(this.unreadable);
  final Set<int> unreadable;
  int post = 0, nextTaps = 0;
  bool nextWorks = true;

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot(frame());

  Map<String, dynamic> frame() {
    final card = '0.0.$post';
    final data = _frame(
      card: card,
      duration: 120,
      position: clock.difference(DateTime(2026)).inSeconds % 120,
    );
    final nodes = data['nodes'] as List;
    final media = nodes.firstWhere((n) => n['id'] == '$card.0');
    media['text'] = 'Watch in full screen';
    media['clickable'] = true;
    if (unreadable.contains(post)) {
      nodes.firstWhere((n) => n['id'] == '$card.0.2.0')['text'] =
          '00:00 / 00:00';
    }
    nodes.addAll(<Map<String, dynamic>>[
      {
        ..._node(
          '0.1.0.0.0',
          const Rect.fromLTWH(380, 400, 16, 16),
          clickable: true,
        ),
        'className': 'android.widget.Button',
      },
      {
        ..._node(
          '0.1.0.1.0',
          const Rect.fromLTWH(380, 425, 16, 16),
          clickable: true,
        ),
        'className': 'android.widget.Button',
      },
    ]);
    return data;
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset p) async {
    expect(const Rect.fromLTWH(380, 425, 16, 16).contains(p), isTrue);
    taps++;
    nextTaps++;
    if (nextWorks) post++;
  }
}

/// Gecko keeps the playing card's pre-scroll geometry: the card is flagged
/// visible but it and its action column are reported 600 px lower, so the
/// column and clock fall outside the viewport (hidden).
class _StaleFeedService extends _UnreadableFeedService {
  _StaleFeedService({this.mediaShown = true}) : super({}) {
    post = 1;
  }

  /// False: Gecko hides the playing card's media too.
  final bool mediaShown;

  @override
  Map<String, dynamic> frame() {
    final data = super.frame();
    final card = '0.0.$post';
    const vp = Rect.fromLTWH(0, 0, 400, 800);
    final nodes = <Map<String, dynamic>>[];
    final hidden = <Map<String, dynamic>>[];
    for (final n in (data['nodes'] as List).cast<Map<String, dynamic>>()) {
      final id = n['id'] as String;
      if (id != card && !id.startsWith('$card.')) {
        nodes.add(n);
        continue;
      }
      final b = n['bounds'] as List;
      final moved = {
        ...n,
        'bounds': [b[0], b[1] + 600, b[2], b[3] + 600],
      };
      final r = SignupNode.rectFrom(moved['bounds']);
      final shown = id == '$card.0' ? mediaShown : vp.overlaps(r) && id == card;
      (shown ? nodes : hidden).add(moved);
    }
    return {...data, 'nodes': nodes, 'hidden': hidden};
  }
}

/// The playing post shows TikTok's playback error until Next is tapped.
class _PlaybackErrorFeedService extends _UnreadableFeedService {
  _PlaybackErrorFeedService(this.failing) : super({});
  final Set<int> failing;

  @override
  Map<String, dynamic> frame() {
    final data = super.frame();
    if (!failing.contains(post)) return data;
    final card = '0.0.$post';
    final nodes = data['nodes'] as List;
    nodes.removeWhere((n) => n['id'] == '$card.0.2.0');
    nodes.add(
      _node(
        '$card.0.error',
        const Rect.fromLTWH(100, 280, 200, 20),
        text:
            "We're having trouble playing this video. Please refresh and try again.",
      ),
    );
    return data;
  }
}

/// A draft appears without its hint while the opening attempt is waiting.
class _UnrecognizedDraftService extends _Service {
  _UnrecognizedDraftService({required this.hidden, required this.enabled}) {
    openWorks = false;
    searchEditor = true;
  }
  final bool hidden, enabled;

  @override
  Future<SignupSnapshot> snapshot() async {
    final snapshot = await super.snapshot();
    if (taps > 0) {
      (hidden ? snapshot.hiddenNodes : snapshot.nodes).add(
        SignupNode(
          _node(
            'unknown.editor',
            const Rect.fromLTWH(290, 750, 80, 30),
            editor: true,
            length: 5,
            enabled: enabled,
          ),
        ),
      );
    }
    return snapshot;
  }
}

/// TikTok's sidebar search → suggestions → Videos tab → result player.
class _RoomService extends _Service {
  _RoomService(this.roomFrame);
  final Map<String, dynamic> roomFrame;
  bool room = true, roomAfterSwipe = false, exitWorks = true;
  int exits = 0;

  @override
  Future<SignupSnapshot> snapshot() async =>
      room ? SignupSnapshot(roomFrame) : await super.snapshot();

  @override
  Future<void> tap(SignupViewport viewport, Offset p) async {
    if (!room) return super.tap(viewport, p);
    final exit = NurtureVideo.liveRoomExit(SignupSnapshot(roomFrame))!;
    expect(exit.bounds.contains(viewport.toScreen(p)), isTrue);
    exits++;
    if (exitWorks) room = false;
  }

  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    await super.swipe(viewport, from, to);
    if (roomAfterSwipe) {
      roomAfterSwipe = false;
      room = true;
    }
  }
}

/// Gecko can temporarily omit the editor after paste/submit and show it later.
class _MissingDraftService extends _Service {
  @override
  Future<SignupSnapshot> snapshot() async {
    final s = await super.snapshot();
    if (pastes == 0) return s;
    s.nodes.removeWhere((n) => n.editable);
    s.hiddenNodes.removeWhere((n) => n.editable);
    return s;
  }
}

class _PrefetchedNextService extends _Service {
  int samplesAfterMove = 0;

  @override
  Future<SignupSnapshot> snapshot() async {
    if (!moved) return super.snapshot();
    samplesAfterMove++;
    if (samplesAfterMove <= 2) {
      return SignupSnapshot(
        _frame(
          card: samplesAfterMove == 1 ? '0.prefetched' : '0.1',
          position: clock.difference(DateTime(2026)).inSeconds % duration,
        ),
      );
    }
    return super.snapshot();
  }
}

class _SearchService extends SignupAccessibility {
  _SearchService({
    this.hiddenClock = false,
    this.keepsDrawer = false,
    this.hiddenEditor = false,
    this.hasVideosTab = true,
    this.liveResult = false,
    this.liveBadgeSibling = false,
    this.feedTile = false,
    this.resultDelaySeconds = 0,
    this.narrowDrawer = false,
    this.resultsBelowLive = false,
    this.scrollWorks = true,
  });
  final bool hiddenClock, keepsDrawer, hiddenEditor, hasVideosTab, liveResult;

  /// The desktop drawer's box: about 15% of the page, right of the sidebar.
  final bool narrowDrawer;
  final bool resultsBelowLive, scrollWorks;
  int resultScrolls = 0;
  final bool feedTile;
  final bool liveBadgeSibling;
  final int resultDelaySeconds;
  DateTime? _resultsReadyAt;
  bool drawerClosed = false;
  DateTime clock = DateTime(2026);
  String state = 'feed';
  int video = 1;
  bool postVisible = false, revealWorks = true, revealMovesPost = true;

  /// Accessibility ACTION_CLICK on the clipped Post; refused when false.
  bool submitAccepted = true;
  int submits = 0;

  /// Player posts that are photo slideshows: a /photo/ URL and no clock.
  final photos = <int>{};
  bool commentFocused = false;
  String commentText = '', publishedComment = '';
  final pasted = <String>[];
  final tapped = <String>[];

  Map<String, dynamic> _button(
    String id,
    Rect r, {
    String text = '',
    String description = '',
  }) => {
    ..._node(id, r, text: text, description: description, clickable: true),
    'className': 'android.widget.Button',
  };

  @override
  Future<SignupSnapshot> snapshot() async {
    const vp = Rect.fromLTWH(0, 0, 400, 800);
    final nodes = <Map<String, dynamic>>[
      _node('0', vp),
      _node(
        '0.1',
        const Rect.fromLTWH(10, 100, 20, 20),
        editor: true,
        clickable: true,
        hint: 'trending phrase',
      ),
    ];
    if (feedTile &&
        (state == 'feed' ||
            (_resultsReadyAt != null && clock.isBefore(_resultsReadyAt!)))) {
      nodes.addAll(
        List<Map<String, dynamic>>.from(
          _frame(
                card: 'feed.1',
                position: clock.difference(DateTime(2026)).inSeconds % 30,
              )['nodes']
              as List,
        ),
      );
      final media = nodes.firstWhere((n) => n['id'] == 'feed.1.0');
      media.addAll({
        'description': 'Watch in full screen',
        'clickable': true,
        'className': 'android.widget.Button',
      });
      return SignupSnapshot({
        'ready': true,
        'webBounds': [0, 0, 400, 800],
        'nodes': nodes,
      });
    }
    final drawerOpen =
        state == 'drawer' ||
        state == 'typed' ||
        (keepsDrawer && state == 'results' && !drawerClosed);
    if (drawerOpen) {
      nodes.add(
        _node('0.2', const Rect.fromLTWH(40, 60, 160, 20), text: 'Search'),
      );
      nodes.add(
        _node(
          '0.3',
          narrowDrawer
              ? const Rect.fromLTWH(45, 90, 58, 20)
              : const Rect.fromLTWH(45, 90, 150, 20),
          editor: true,
          focused: true,
          clickable: true,
          hint: 'trending phrase',
        ),
      );
      nodes.add(
        _button('0.8', const Rect.fromLTWH(190, 55, 15, 15), text: 'Close'),
      );
    }
    if (state == 'typed' || (drawerOpen && state == 'results')) {
      nodes.add(
        _node(
          '0.4',
          const Rect.fromLTWH(40, 300, 160, 20),
          text: 'View all results for “Cats”',
        ),
      );
    }
    if (state == 'results' || state == 'videos' || state == 'player') {
      nodes.add(
        _button('0.5', const Rect.fromLTWH(60, 10, 20, 15), text: 'Top'),
      );
      if (hasVideosTab) {
        nodes.add(
          _button('0.6', const Rect.fromLTWH(160, 10, 30, 15), text: 'Videos'),
        );
      }
      if (liveResult) {
        nodes.addAll([
          _button(
            '0.7.live',
            const Rect.fromLTWH(40, 180, 80, 120),
            text: 'Watch in full screen',
          ),
          _node(
            liveBadgeSibling ? '0.7.badge' : '0.7.live.0',
            const Rect.fromLTWH(45, 185, 30, 15),
            text: 'LIVE',
          ),
        ]);
      }
      for (var i = 0; i < 4; i++) {
        nodes.add(
          _button(
            '0.7.$i',
            Rect.fromLTWH(
              40.0 + i * 90,
              resultsBelowLive && resultScrolls < 2 ? 840 : 40,
              80,
              120,
            ),
            description: 'Watch in full screen',
          ),
        );
      }
      if (resultsBelowLive) {
        nodes.add({
          ..._node('0.7', const Rect.fromLTWH(40, 0, 360, 800)),
          'scrollable': true,
        });
      }
    }
    if (state == 'player') {
      final position = clock.difference(DateTime(2026)).inSeconds % 30;
      nodes.addAll([
        {..._node('9', vp), 'className': 'android.app.AlertDialog'},
        _node('9.0', const Rect.fromLTWH(0, 0, 260, 800)),
        if (!photos.contains(video))
          _node(
            '9.0.1',
            const Rect.fromLTWH(140, 780, 40, 12),
            text: '00:${position.toString().padLeft(2, '0')}/00:30',
          ),
        _button(
          '9.0.5',
          const Rect.fromLTWH(230, 500, 20, 20),
          description: 'Go to next video',
        ),
        _node('9.1', const Rect.fromLTWH(260, 0, 140, 760)),
        _node(
          '9.1.0',
          const Rect.fromLTWH(265, 200, 130, 15),
          text:
              'https:[email]/${photos.contains(video) ? 'photo' : 'video'}'
              '/90000$video?is_from_webapp=1',
        ),
        _node('9.3', const Rect.fromLTWH(260, 770, 140, 20)),
        _node(
          '9.3.0.1',
          const Rect.fromLTWH(265, 772, 100, 15),
          editor: true,
          clickable: true,
          focused: commentFocused,
          length: commentText.length,
          hint: commentText.isEmpty ? 'Add comment...' : '',
        ),
        if (postVisible)
          _button('9.3.1', const Rect.fromLTWH(375, 772, 20, 15), text: 'Post'),
        _node(
          '9.2',
          const Rect.fromLTWH(265, 740, 100, 20),
          text: 'Comments (10)',
        ),
        if (publishedComment.isNotEmpty)
          _node(
            '9.1.2',
            const Rect.fromLTWH(265, 300, 100, 20),
            text: publishedComment,
          ),
      ]);
    }
    final hidden = nodes
        .where(
          (n) =>
              (hiddenClock && n['id'] == '9.0.1') ||
              (hiddenEditor && n['id'] == '9.3.0.1') ||
              (resultsBelowLive &&
                  resultScrolls < 2 &&
                  RegExp(r'^0\.7\.\d+$').hasMatch(n['id'] as String)),
        )
        .toList();
    nodes.removeWhere((n) => hidden.contains(n));
    return SignupSnapshot({
      'ready': true,
      'webBounds': [vp.left, vp.top, vp.right, vp.bottom],
      'nodes': nodes,
      'hidden': hidden,
    });
  }

  Future<void> delay(Duration d) async => clock = clock.add(d);

  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {
    expect(resultsBelowLive, isTrue);
    expect(viewport.bounds.contains(viewport.toScreen(from)), isTrue);
    expect(viewport.bounds.contains(viewport.toScreen(to)), isTrue);
    expect(from.dy, greaterThan(to.dy));
    tapped.add('scroll-results');
    if (scrollWorks) resultScrolls++;
  }

  @override
  Future<void> tap(SignupViewport viewport, Offset p) async {
    bool hit(double x, double y, double w, double h) =>
        Rect.fromLTWH(x, y, w, h).contains(p);
    if (state == 'feed' && hit(10, 100, 20, 20)) {
      tapped.add('open');
      state = 'drawer';
    } else if (state == 'typed' && hit(40, 300, 160, 20)) {
      tapped.add('view-all');
      state = 'results';
      _resultsReadyAt = clock.add(Duration(seconds: resultDelaySeconds));
    } else if (state == 'results' &&
        keepsDrawer &&
        !drawerClosed &&
        hit(190, 55, 15, 15)) {
      tapped.add('close-search');
      drawerClosed = true;
    } else if (state == 'results' &&
        (!keepsDrawer || drawerClosed) &&
        hit(160, 10, 30, 15)) {
      tapped.add('videos-tab');
      state = 'videos';
    } else if ((state == 'videos' ||
            (!hasVideosTab && state == 'results' && drawerClosed)) &&
        hit(40, 40, 350, 120)) {
      tapped.add('result');
      state = 'player';
    } else if (state == 'player' && hit(230, 500, 20, 20)) {
      tapped.add('next');
      video++;
    } else if (state == 'player' && postVisible && hit(375, 772, 20, 15)) {
      tapped.add('post');
      publishedComment = commentText;
      commentText = '';
    } else if (state == 'player' && hit(265, 772, 100, 15)) {
      commentFocused = true;
    } else if (state == 'player' && hit(265, 740, 100, 20)) {
      commentFocused = false;
    } else {
      tapped.add('stray $p');
    }
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pasted.add('$field:$text');
    if (state == 'drawer') state = 'typed';
    if (field == 'comment') commentText = text;
    return {'ok': true};
  }

  @override
  Future<bool> clearComment(String expected) async {
    if (commentText == expected) commentText = '';
    return commentText != expected;
  }

  @override
  Future<bool> submitComment() async {
    submits++;
    if (!submitAccepted || commentText.isEmpty) return false;
    tapped.add('a11y-post');
    publishedComment = commentText;
    commentText = '';
    return true;
  }

  @override
  Future<Map<String, dynamic>> revealCommentPost(SignupNode editor) async {
    postVisible = revealWorks && revealMovesPost;
    return {
      'ok': revealWorks,
      'reason': revealWorks ? 'post-reveal-requested' : 'post-offscreen',
    };
  }

  @override
  Future<void> setKeyboardSuppressed(bool value) async {}

  @override
  Future<void> cancelPaste() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final search in [false, true]) {
    test(
      'Try again recovers ${search ? 'Search' : 'Feed'} on the current page',
      () async {
        final service = _ServerErrorService(searchPlayer: search);
        final deadline = service.clock.add(const Duration(seconds: 8));
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: [],
          searchKeyword: search ? 'Cats' : null,
          likeRate: 0,
          commentRate: 0,
          longWatchRate: 1,
          isActive: () => service.clock.isBefore(deadline),
          isTikTok: () async => true,
          onProgress: (_, _) async {},
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        expect(service.retries, 1);
        expect(runner.totals.watchMilliseconds, greaterThan(0));
        expect(runner.totals.watchMilliseconds, lessThanOrEqualTo(6000));
        expect(
          service.clock.difference(deadline).inMilliseconds,
          inInclusiveRange(0, 199),
        );
        expect([service.posts, service.pastes, service.swipes], [0, 0, 0]);
      },
    );
  }

  test(
    'persistent server error retries at most three times, ten seconds apart across resume',
    () async {
      final service = _ServerErrorService(recoverAfter: 100);
      var deadline = service.clock.add(const Duration(seconds: 15));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(service.retries, 2);
      deadline = service.clock.add(const Duration(seconds: 30));
      await runner.start();
      expect(service.retries, 3);
      expect(runner.totals.watchMilliseconds, 0);
      expect(runner.totals.videos, 0);
      for (var i = 1; i < service.retryTimes.length; i++) {
        expect(
          service.retryTimes[i].difference(service.retryTimes[i - 1]),
          greaterThanOrEqualTo(const Duration(seconds: 10)),
        );
      }
    },
  );

  for (final scenario in [
    'missing-title',
    'missing-details',
    'missing-button',
    'disabled',
    'offscreen',
    'duplicate',
    'caption',
    'draft',
    'captcha',
    'login',
  ]) {
    test('does not press Try again for $scenario', () async {
      final service = _ServerErrorService(scenario: scenario);
      final deadline = service.clock.add(const Duration(seconds: 5));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        likeRate: 0,
        commentRate: 0,
        longWatchRate: 1,
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        now: () => service.clock,
        delay: service.delay,
      );
      if (scenario == 'login') {
        await expectLater(runner.start(), throwsStateError);
      } else {
        await runner.start();
      }
      expect(service.retries, 0);
    });
  }

  test(
    'Try again rechecks the error screen after saving coordinates',
    () async {
      final service = _ServerErrorService();
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile(
          {},
          save: (_) async {
            // The error clears while profile storage is pending.
            service.retries = 1;
          },
        ),
        comments: [],
        isActive: () => true,
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        now: () => service.clock,
        delay: service.delay,
      );
      await expectLater(runner.start(), throwsStateError);
      expect(service.retryTimes, isEmpty);
    },
  );

  Map<String, dynamic> liveRoom() => Map<String, dynamic>.from(
    jsonDecode(File('test/fixtures/nurture_live_room.json').readAsStringSync())
        as Map,
  );

  test('recorded feed with zero duration still exposes verified next', () {
    final data =
        jsonDecode(
              File(
                'test/fixtures/nurture_feed_no_duration.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final snapshot = SignupSnapshot(data);
    expect(NurtureVideo.read(snapshot), isNull);
    final navigation = NurtureVideo.feedNavigation(snapshot)!;
    expect(navigation.key, '0.0.1.2.0.0|fixture-creator');
    expect(navigation.next.bounds, const Rect.fromLTRB(1286, 1546, 1328, 1587));
    for (final hidden in [false, true]) {
      final draft = SignupNode(
        _node(
          'unknown.editor',
          const Rect.fromLTWH(290, 750, 80, 30),
          editor: true,
          length: 5,
        ),
      );
      final withDraft = SignupSnapshot(data);
      (hidden ? withDraft.hiddenNodes : withDraft.nodes).add(draft);
      expect(NurtureVideo.feedNavigation(withDraft), isNull);
    }
    final ambiguous = SignupSnapshot(data);
    ambiguous.nodes.add(
      SignupNode({
        ...data['nodes'].firstWhere((n) => n['id'] == '0.0.1.2.0.0.1.2') as Map,
        'id': '0.0.1.2.0.0.1.3',
      }),
    );
    expect(NurtureVideo.feedNavigation(ambiguous), isNull);
  });

  for (final unreadable in [
    <int>{0},
    <int>{1},
  ]) {
    test('continues past a zero-duration feed post at $unreadable', () async {
      final service = _UnreadableFeedService(unreadable);
      var active = true;
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        likeRate: 0,
        commentRate: 0,
        longWatchRate: 0,
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (totals, _) async {
          if (service.post >= 2 && totals.videos >= 1) active = false;
        },
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(service.nextTaps, 2);
      expect(runner.totals.skippedVideos, 1);
      expect(runner.totals.comments, 0);
      expect(service.pastes, 0);
      expect(service.posts, 0);
    });
  }

  for (final nextWorks in [false, true]) {
    test(
      'unreadable feed recovery is bounded (nextWorks=$nextWorks)',
      () async {
        final service = _UnreadableFeedService({0, 1, 2, 3, 4})
          ..nextWorks = nextWorks;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: [],
          likeRate: 0,
          isActive: () => true,
          isTikTok: () async => true,
          onProgress: (_, _) async {},
          now: () => service.clock,
          delay: service.delay,
        );
        await expectLater(
          runner.start(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(
                nextWorks
                    ? 'Nhiều bài liên tiếp'
                    : 'Chưa xác nhận được bài mới',
              ),
            ),
          ),
        );
        expect(service.nextTaps, nextWorks ? 3 : 1);
        expect(runner.totals.videos, 0);
        expect(runner.totals.watchMilliseconds, 0);
      },
    );
  }

  Map<String, dynamic> staleLiveAd() => Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/nurture_feed_stale_live_ad.json',
          ).readAsStringSync(),
        )
        as Map,
  );

  test('recorded stale feed geometry exposes only the page Next', () {
    // Next landed on a promoted LIVE; Gecko flags it visible but still
    // reports it ~1700px lower, with its action column hidden.
    final snapshot = SignupSnapshot(staleLiveAd());
    expect(NurtureVideo.read(snapshot), isNull);
    final navigation = NurtureVideo.feedNavigation(snapshot)!;
    expect(navigation.key, '0.0.1.2.0.3|fixture-live LIVE');
    expect(navigation.next.bounds, const Rect.fromLTRB(1286, 1546, 1328, 1587));

    final data = staleLiveAd();
    (data['hidden'] as List).add(
      _node(
        '0.0.1.2.0.3.0.4.0.0',
        const Rect.fromLTRB(566, 4014, 822, 4060),
        text: '00:04 / 00:18',
      ),
    );
    final video = NurtureVideo.read(SignupSnapshot(data))!;
    expect(video.key, '0.0.1.2.0.3|fixture-live LIVE|18');
    expect(video.position, 4);
    expect(video.targetsVerified, isFalse);
    expect([video.comments, video.like], [null, null]);
    expect(video.next!.bounds, const Rect.fromLTRB(1286, 1546, 1328, 1587));

    final ambiguous = SignupSnapshot(data);
    ambiguous.nodes.add(
      SignupNode({
        ...(data['hidden'] as List).firstWhere(
              (n) => n['id'] == '0.0.1.2.0.2.0',
            )
            as Map,
        'clickable': true,
        'enabled': true,
      }),
    );
    expect(NurtureVideo.read(ambiguous), isNull);
    expect(NurtureVideo.feedNavigation(ambiguous), isNull);
  });

  test('a card reported partly outside the viewport exposes no targets', () {
    final data = _frame(likes: '5');
    for (final n in (data['nodes'] as List).cast<Map<String, dynamic>>()) {
      if (n['id'] == '0.1') continue;
      final b = n['bounds'] as List;
      n['bounds'] = [b[0], b[1] + 280, b[2], b[3] + 280];
    }
    final video = NurtureVideo.read(SignupSnapshot(data))!;
    expect(video.key, '0.1|creator|30');
    expect(video.targetsVerified, isFalse);
    expect([video.comments, video.like], [null, null]);
    final settled = NurtureVideo.read(SignupSnapshot(_frame(likes: '5')))!;
    expect(settled.targetsVerified, isTrue);
    expect(settled.like, isNotNull);
    // Recorded: the whole feed reported 581px low while a short landscape
    // post and its buttons still fit inside the viewport.
    final shifted = _frame(landscape: true, likes: '5');
    for (final n in (shifted['nodes'] as List).cast<Map<String, dynamic>>()) {
      final b = n['bounds'] as List;
      n['bounds'] = [b[0], b[1] + 60, b[2], b[3] + 60];
    }
    final low = NurtureVideo.read(SignupSnapshot(shifted))!;
    expect(low.targetsVerified, isFalse);
    expect([low.comments, low.like], [null, null]);
  });

  test('a playing post reported 581px low exposes targets moved back', () {
    // Recorded on Gecko after Next: the screenshot drew the like button at
    // y≈1387 and comments at y≈1487, the tree reported both 581px lower.
    Map<String, dynamic> recorded(String clock) {
      final data = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/nurture_feed_offset_581.json',
              ).readAsStringSync(),
            )
            as Map,
      );
      for (final n in (data['hidden'] as List).cast<Map>()) {
        if (n['id'] == '0.0.1.2.0.1.0.4.0.0') n['text'] = clock;
      }
      return data;
    }

    final video = NurtureVideo.read(SignupSnapshot(recorded('00:05 / 00:16')))!;
    expect(video.key, startsWith('0.0.1.2.0.1|'));
    expect(video.targetsVerified, isTrue);
    expect(video.like!.bounds, const Rect.fromLTRB(1204, 1346, 1266, 1446));
    expect(video.comments!.bounds, const Rect.fromLTRB(1204, 1446, 1266, 1546));
    expect(video.bounds.top, 1842 - 581);
    // Not yet playing: the drawn post is unproven, so nothing is tapped.
    final waiting = NurtureVideo.read(
      SignupSnapshot(recorded('00:00 / 00:16')),
    )!;
    expect(waiting.targetsVerified, isFalse);
    expect([waiting.comments, waiting.like], [null, null]);
  });

  for (final mediaShown in [true, false]) {
    test('stale feed geometry is watched without any card-relative tap '
        '(media shown: $mediaShown)', () async {
      final service = _StaleFeedService(mediaShown: mediaShown);
      final deadline = service.clock.add(const Duration(seconds: 75));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        likeRate: 1,
        commentRate: 1,
        longWatchRate: 1,
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      // The 120s post is watched for its one-minute cap, then the page Next.
      expect(service.nextTaps, 1);
      expect(runner.totals.watchMilliseconds, greaterThanOrEqualTo(55000));
      expect(runner.totals.fullVideos, 1);
      expect([runner.totals.likes, runner.totals.comments], [0, 0]);
      expect([service.pastes, service.posts], [0, 0]);
    });
  }

  test('a hidden stale card is read only when its clock alone started', () {
    Map<String, dynamic> frame(List<String> clocks) {
      final hidden = <Map<String, dynamic>>[];
      for (var i = 0; i < clocks.length; i++) {
        final top = 900.0 + i * 800;
        hidden.addAll([
          _node('0.0.$i', Rect.fromLTWH(10, top, 300, 500)),
          _node(
            '0.0.$i.0',
            Rect.fromLTWH(10, top, 300, 500),
            text: 'Watch in full screen',
            clickable: true,
          ),
          _node(
            '0.0.$i.0.2',
            Rect.fromLTWH(20, top + 450, 100, 20),
            text: clocks[i],
          ),
          _node('0.0.$i.1.0.0', Rect.fromLTWH(350, top, 30, 30), text: 'c$i'),
        ]);
      }
      Map<String, dynamic> button(String id, double top) => {
        ..._node(id, Rect.fromLTWH(380, top, 16, 16), clickable: true),
        'className': 'android.widget.Button',
      };
      return {
        'ready': true,
        'webBounds': [0, 0, 400, 800],
        'nodes': [button('0.1.0.0.0', 400), button('0.1.0.1.0', 425)],
        'hidden': hidden,
      };
    }

    SignupSnapshot snapshot(List<String> clocks) =>
        SignupSnapshot(frame(clocks));
    final video = NurtureVideo.read(
      snapshot(['00:00 / 00:00', '00:07 / 00:23', '00:00 / 00:00']),
    )!;
    expect(video.key, '0.0.1|c1|23');
    expect(video.targetsVerified, isFalse);
    // A post left behind keeps its duration at 00:00; it has not started.
    expect(
      NurtureVideo.read(snapshot(['00:00 / 01:03', '00:07 / 00:23']))?.key,
      '0.0.1|c1|23',
    );
    for (final ambiguous in [
      ['00:03 / 01:03', '00:07 / 00:23'],
      ['00:00 / 01:03', '00:00 / 00:23'],
    ]) {
      expect(NurtureVideo.read(snapshot(ambiguous)), isNull);
    }
  });

  test(
    'a post that autoplays onward before Next is counted, not tapped',
    () async {
      final service = _UnreadableFeedService({});
      var autoplayed = false, active = true;
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile(
          {},
          save: (_) async {
            // TikTok moves on by itself while Next is being prepared.
            if (!autoplayed) {
              autoplayed = true;
              service.post++;
            }
          },
        ),
        comments: [],
        likeRate: 0,
        commentRate: 0,
        longWatchRate: 0,
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (totals, _) async {
          if (totals.videos >= 2) active = false;
        },
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(autoplayed, isTrue);
      expect(runner.totals.skippedVideos, 2);
      // Only the second post needed a tap; post 1 was never skipped unwatched.
      expect(service.nextTaps, 1);
      expect(service.post, 2);
    },
  );

  test('a post TikTok cannot play is skipped through the page Next', () async {
    final service = _PlaybackErrorFeedService({0});
    var active = true;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      likeRate: 0,
      commentRate: 0,
      longWatchRate: 0,
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (totals, _) async {
        if (totals.videos >= 1) active = false;
      },
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.nextTaps, 2);
    expect(runner.totals.skippedVideos, 1);
    expect(runner.totals.watchMilliseconds, greaterThan(0));
  });

  test(
    'persistent playback errors stop after three skips across resume',
    () async {
      final service = _PlaybackErrorFeedService({0, 1, 2, 3, 4, 5});
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => true,
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        now: () => service.clock,
        delay: service.delay,
      );
      await expectLater(
        runner.start(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('không phát được video'),
          ),
        ),
      );
      expect(service.nextTaps, 3);
      await expectLater(runner.start(), throwsStateError);
      expect(service.nextTaps, 3);
      expect(runner.totals.videos, 0);
    },
  );

  test('recorded LIVE room exits via For You rather than sidebar Back', () {
    final snapshot = SignupSnapshot(liveRoom());
    expect(NurtureVideo.isLiveRoom(snapshot), isTrue);
    expect(NurtureVideo.read(snapshot), isNull);
    expect(
      NurtureVideo.liveRoomExit(snapshot)?.name,
      'Go to TikTok For You feed',
    );
    final feed = _frame();
    (feed['nodes'] as List).add(
      _node('sidebar.live', const Rect.fromLTWH(0, 10, 20, 20), text: 'LIVE'),
    );
    expect(NurtureVideo.isLiveRoom(SignupSnapshot(feed)), isFalse);
  });

  for (final scenario in ['feed', 'search', 'after-next']) {
    test(
      'skips a standalone LIVE room in $scenario without counting it',
      () async {
        final service = _RoomService(liveRoom())
          ..room = scenario != 'after-next'
          ..roomAfterSwipe = scenario == 'after-next';
        var active = true;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: ['Configured comment'],
          searchKeyword: scenario == 'search' ? 'Cats' : null,
          isActive: () => active,
          isTikTok: () async => true,
          onProgress: (t, _) async {
            if (service.room) expect(t.watchMilliseconds, 0);
            if (t.videos > 0) active = false;
          },
          likeRate: 0,
          longWatchRate: 0,
          commentRate: 0,
          random: _Random(false),
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        expect(service.exits, 1);
        expect(service.swipes, 1);
        expect(service.posts, 0);
        expect(service.likeTaps, 0);
        expect(runner.totals.videos, 1);
        expect(runner.totals.watchMilliseconds, inInclusiveRange(2000, 5000));
      },
    );
  }

  test('a LIVE room that does not leave gets one exit tap and stops', () async {
    final service = _RoomService(liveRoom())..exitWorks = false;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      now: () => service.clock,
      delay: service.delay,
    );
    await expectLater(
      runner.start(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chưa rời được phòng LIVE'),
        ),
      ),
    );
    expect(service.exits, 1);
    expect(runner.totals.watchMilliseconds, 0);
    expect(runner.totals.videos, 0);
  });

  test('search excludes a LIVE badge exposed beside its result tile', () async {
    final service = _SearchService(
      keepsDrawer: true,
      hasVideosTab: false,
      liveResult: true,
      liveBadgeSibling: true,
    );
    var active = true;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      searchKeyword: 'Cats',
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (t.videos > 0) active = false;
      },
      likeRate: 0,
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.tapped, [
      'open',
      'view-all',
      'close-search',
      'result',
      'next',
    ]);
    expect(runner.totals.videos, 1);
  });

  for (final blockedUrl in [false, true]) {
    test(
      'stop releases a pending ${blockedUrl ? 'URL' : 'snapshot'} read',
      () async {
        final service = _Service();
        final lostSnapshot = Completer<SignupSnapshot>();
        final lostUrl = Completer<bool>();
        final urlEntered = Completer<void>();
        if (!blockedUrl) service.blockedSnapshot = lostSnapshot;
        var reads = 0;
        NurtureTotals? totals;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: ['Configured comment'],
          isActive: () => true,
          isTikTok: () async {
            reads++;
            if (!urlEntered.isCompleted) urlEntered.complete();
            return blockedUrl ? lostUrl.future : true;
          },
          onProgress: (t, _) async => totals = t,
          now: () => service.clock,
          delay: service.delay,
        );
        final running = runner.start();
        await (blockedUrl ? urlEntered.future : service.snapshotEntered.future);
        await runner.stop().timeout(const Duration(seconds: 1));
        await running;
        expect(reads, 1);
        expect(totals!.watchMilliseconds, 0);
        expect(service.taps + service.swipes + service.posts, 0);
        // Losing the document later must not produce an unhandled error or tap.
        if (blockedUrl) {
          lostUrl.completeError(StateError('old document disconnected'));
        } else {
          lostSnapshot.completeError(StateError('old document disconnected'));
        }
        await Future<void>.delayed(Duration.zero);
        expect(service.taps + service.swipes + service.posts, 0);
      },
    );
  }

  test(
    'a late snapshot from a cancelled run cannot replace the new video',
    () async {
      final service = _Service();
      final oldRead = Completer<SignupSnapshot>();
      service.blockedSnapshot = oldRead;
      var active = true;
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => active && !service.moved,
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: (d) async {
          if (!oldRead.isCompleted) {
            oldRead.complete(
              SignupSnapshot(_frame(position: 299, duration: 300)),
            );
          }
          await service.delay(d);
          if (service.clock.difference(DateTime(2026)).inSeconds > 10) {
            active = false;
          }
        },
      );
      final first = runner.start();
      await service.snapshotEntered.future;
      await runner.stop().timeout(const Duration(seconds: 1));
      await first;
      service.blockedSnapshot = null;
      await runner.start();
      expect(service.swipes, 1);
      expect(runner.totals.watchMilliseconds, inInclusiveRange(2000, 4000));
      expect(service.posts, 0);
    },
  );

  test('real portrait feed and open panel retain identity and orientation', () {
    final recording =
        jsonDecode(
              File(
                'test/fixtures/nurture_accessibility_recording.json',
              ).readAsStringSync(),
            )
            as Map;
    final feed = SignupSnapshot(Map<String, dynamic>.from(recording['feed']));
    final panel = SignupSnapshot(Map<String, dynamic>.from(recording['panel']));
    final a = NurtureVideo.read(feed)!, b = NurtureVideo.read(panel)!;
    expect(a.orientation, NurtureVideoOrientation.portrait);
    expect(b.orientation, NurtureVideoOrientation.portrait);
    expect(a.key, b.key);
    expect(a.like?.text, startsWith('Like video'));
    expect(a.likeCount, isNull); // "7.5M" is rounded.
  });

  test('reads the feed when WebView exposes aria-labels as text', () {
    final recording =
        jsonDecode(
              File(
                'test/fixtures/nurture_accessibility_recording.json',
              ).readAsStringSync(),
            )
            as Map;
    final data = jsonDecode(jsonEncode(recording['feed'])) as Map;
    // Android 16 WebView: the accessible name moves from description to text.
    for (final node in (data['nodes'] as List).cast<Map>()) {
      final description = '${node['description'] ?? ''}';
      if (description.isNotEmpty && '${node['text'] ?? ''}'.isEmpty) {
        node['text'] = description;
        node['description'] = '';
      }
    }
    final original = NurtureVideo.read(
      SignupSnapshot(Map<String, dynamic>.from(recording['feed'])),
    )!;
    final moved = NurtureVideo.read(
      SignupSnapshot(Map<String, dynamic>.from(data)),
    )!;
    expect(moved.key, original.key);
    expect(moved.comments?.text, startsWith('Read or add comments'));
  });

  test(
    'real focused comment stays visible with the playback clock while IME is hidden',
    () {
      final recording =
          jsonDecode(
                File(
                  'test/fixtures/nurture_accessibility_recording.json',
                ).readAsStringSync(),
              )
              as Map;
      final snapshot = SignupSnapshot(
        Map<String, dynamic>.from(recording['focused']),
      );
      expect(snapshot.keyboardVisible, isFalse);
      expect(
        snapshot.editors.any((n) => n.focused && n.hint.contains('comment')),
        isTrue,
      );
      expect(NurtureVideo.read(snapshot), isNotNull);
    },
  );

  test('portrait and landscape never share the comment button point', () async {
    final profile = NurtureCoordinateProfile({});
    for (final landscape in [false, true]) {
      final s = SignupSnapshot(_frame(landscape: landscape));
      final v = NurtureVideo.read(s)!;
      await profile.target(
        '${v.layout(s.viewport)}/open-comments',
        s.viewport,
        v.comments!,
      );
    }
    expect(
      profile.points.keys.where((key) => key.startsWith('portrait/')),
      hasLength(1),
    );
    expect(
      profile.points.keys.where((key) => key.startsWith('landscape/')),
      hasLength(1),
    );
    expect(profile.points.values.map((p) => p[1]).toSet(), hasLength(2));
  });

  test(
    'a shifted action column on the same frame records its own point',
    () async {
      final profile = NurtureCoordinateProfile({});
      final s = SignupSnapshot(_frame());
      final v = NurtureVideo.read(s)!;
      await profile.target(v.commentsKey(s.viewport), s.viewport, v.comments!);
      final frame = _frame();
      final nodes = frame['nodes'] as List;
      final button = nodes.indexWhere(
        (n) => (n['description'] as String).startsWith('Read or add comments'),
      );
      nodes[button] = {
        ...nodes[button] as Map<String, dynamic>,
        'bounds': [350.0, 470.0, 380.0, 500.0],
      };
      final shifted = SignupSnapshot(frame);
      final w = NurtureVideo.read(shifted)!;
      expect(w.layout(shifted.viewport), v.layout(s.viewport));
      expect(w.commentsKey(shifted.viewport), isNot(v.commentsKey(s.viewport)));
      final point = await profile.target(
        w.commentsKey(shifted.viewport),
        shifted.viewport,
        w.comments!,
      );
      expect(
        w.comments!.bounds.contains(shifted.viewport.toScreen(point)),
        isTrue,
      );
    },
  );

  test(
    'saved orientation points survive restart and follow a shifted button',
    () async {
      final profile = await NurtureCoordinateProfile.load();
      final s = SignupSnapshot(_frame(landscape: true));
      final v = NurtureVideo.read(s)!;
      final key = '${v.layout(s.viewport)}/open-comments';
      final point = await profile.target(key, s.viewport, v.comments!);
      final restored = await NurtureCoordinateProfile.load();
      expect(restored.point(key), point);
      const moved = Rect.fromLTWH(350, 500, 30, 30);
      final tap = await restored.target(
        key,
        s.viewport,
        SignupNode(_node('moved', moved)),
      );
      // Another device's layout: the live button decides, the save is kept.
      expect(moved.contains(s.viewport.toScreen(tap)), isTrue);
      expect(restored.point(key), point);
    },
  );

  test('skip counts observed playback then makes one verified swipe', () async {
    final service = _Service();
    var active = true;
    NurtureTotals? totals;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.swipes, 1);
    expect(totals!.skippedVideos, 1);
    expect(totals!.fullVideos, 0);
    expect(totals!.watchMilliseconds, greaterThanOrEqualTo(2000));
    expect(service.posts, 0);
  });

  test('0% rates neither like, comment nor watch long', () async {
    final service = _Service();
    var active = true;
    NurtureTotals? totals;
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      likeRate: 0,
      commentRate: 0,
      longWatchRate: 0,
      // nextDouble 0 would draw every rate above 0.
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(totals!.skippedVideos, 1);
    expect(totals!.fullVideos, 0);
    expect(service.likeTaps, 0);
    expect(service.posts, 0);
  });

  test('100% comment rate comments and watches the post in full', () async {
    final service = _Service();
    var active = true;
    NurtureTotals? totals;
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      likeRate: 0,
      commentRate: 1,
      longWatchRate: 0,
      random: _LatestRandom(),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(service.posts, 1);
    expect(service.likeTaps, 0);
    expect(totals!.fullVideos, 1);
  });

  group('like', () {
    Future<(NurtureTotals, List<String>)> run(
      _Service service, {
      double likeRate = NurtureAccessibilityRunner.defaultLikeRate,
    }) async {
      var active = true;
      NurtureTotals? totals;
      final skipped = <String>[];
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (t.videos > 0) active = false;
        },
        onLikeSkipped: skipped.add,
        likeRate: likeRate,
        // nextDouble 0 draws a like; without it the post would be skipped.
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      return (totals!, skipped);
    }

    test('an accepted like is confirmed by its exact count', () async {
      final service = _Service()..likes = '35';
      final (totals, skipped) = await run(service);
      expect(service.likeTaps, 1);
      expect(service.likes, '36');
      expect(totals.likes, 1);
      expect(totals.fullVideos, 1);
      expect(totals.watchMilliseconds, greaterThanOrEqualTo(29000));
      expect(skipped, isEmpty);
    });

    test(
      'a rolled-back like quietly continues without counting or retrying',
      () async {
        final service = _Service()
          ..likes = '35'
          ..likeAccepted = false;
        final (totals, skipped) = await run(service);
        expect(service.likeTaps, 1);
        expect(service.likes, '35');
        expect(totals.likes, 0);
        expect(totals.fullVideos, 1);
        expect(skipped, isEmpty);
      },
    );

    test('a like with no visible effect is not retried', () async {
      final service = _Service()
        ..likes = '35'
        ..likeWorks = false;
      final (totals, skipped) = await run(service);
      expect(service.likeTaps, 1);
      expect(totals.likes, 0);
      expect(totals.fullVideos, 1);
      expect(skipped.single, contains('Chưa xác nhận được thả tim'));
    });

    test('a rounded count counts the single tap', () async {
      final service = _Service()..likes = '1.2K';
      final (totals, skipped) = await run(service);
      expect(service.likeTaps, 1);
      expect(totals.likes, 1);
      expect(skipped, isEmpty);
    });

    test('a zero like rate never likes', () async {
      final service = _Service()..likes = '35';
      final (totals, _) = await run(service, likeRate: 0);
      expect(service.likeTaps, 0);
      expect(totals.likes, 0);
    });
  });

  test('a long video is watched for one minute then swiped', () async {
    final service = _Service()..duration = 600;
    var active = true;
    NurtureTotals? totals;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.swipes, 1);
    expect(totals!.fullVideos, 1);
    expect(totals!.skippedVideos, 0);
    expect(totals!.watchMilliseconds, inInclusiveRange(60000, 65000));
  });

  for (final badge in ['LIVE now', 'Watch LIVE', 'LIVE']) {
    test('a LIVE post ($badge) is skipped with the feed next button', () async {
      final service = _Service()
        ..live = true
        ..liveBadge = badge;
      var active = true;
      NurtureTotals? totals;
      final profile = NurtureCoordinateProfile({});
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: profile,
        comments: [],
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (t.videos > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.liveSkips, 1);
      expect(profile.points.keys, contains('live/feed/next-video'));
      // The LIVE post is not counted; the next real video is.
      expect(totals!.videos, 1);
      expect(totals!.skippedVideos, 1);
    });
  }

  test('a briefly missing WebView does not stop nurture', () async {
    final service = _Service()..unreadyFrames = 5;
    var active = true;
    NurtureTotals? totals;
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(totals!.skippedVideos, 1);
    expect(service.swipes, 1);
  });

  test('a transient dialog pauses nurture without stopping it', () async {
    final service = _Service()
      ..dialogUntil = DateTime(2026).add(const Duration(seconds: 4));
    var active = true;
    NurtureTotals? totals;
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        totals = t;
        if (t.videos > 0) active = false;
      },
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(totals!.skippedVideos, 1);
    expect(service.swipes, 1);
  });

  test('a persistent dialog stops before any gesture and names it', () async {
    final service = _Service()
      ..dialogUntil = DateTime(2026).add(const Duration(hours: 1));
    await expectLater(
      NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => true,
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start(),
      throwsA(
        isA<NurtureDialogOpen>().having(
          (e) => e.message,
          'message',
          contains('hộp thoại (Popup)'),
        ),
      ),
    );
    expect(service.taps + service.swipes, 0);
  });

  test('a persistently missing WebView stops before any gesture', () async {
    final service = _Service()..unreadyFrames = 1000;
    await expectLater(
      NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => true,
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start(),
      throwsA(isA<StateError>()),
    );
    expect(service.taps + service.swipes, 0);
  });

  test('stalled playback contributes no watch time or gestures', () async {
    final service = _Service()..stall = true;
    NurtureTotals? totals;
    final until = service.clock.add(const Duration(seconds: 6));
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => service.clock.isBefore(until),
      isTikTok: () async => true,
      onProgress: (t, _) async => totals = t,
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(totals!.watchMilliseconds, 0);
    expect(service.swipes, 0);
  });

  test('a clock frozen for 15s skips the post once as unwatched', () async {
    final service = _Service()..stall = true;
    NurtureTotals? totals;
    final until = service.clock.add(const Duration(seconds: 40));
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () {
        // The next post plays normally.
        if (service.swipes > 0) service.stall = false;
        return service.clock.isBefore(until);
      },
      isTikTok: () async => true,
      onProgress: (t, _) async => totals = t,
      longWatchRate: 1,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(service.swipes, 1);
    expect(totals!.skippedVideos, 1);
    expect(totals!.fullVideos, 0);
  });

  for (final seconds in [12, 25, 40]) {
    test('next post loading for ${seconds}s after one swipe', () async {
      final service = _Service()..loadSecondsAfterMove = seconds;
      var active = true;
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          if (t.videos > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      );
      if (seconds < 30) {
        await runner.start();
        expect(runner.totals.videos, 1);
      } else {
        await expectLater(
          runner.start(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Chưa đọc được tiến độ video sau Next'),
            ),
          ),
        );
        expect(runner.totals.videos, 0);
      }
      expect(service.swipes, 1);
    });
  }

  test(
    'a prefetched next frame cannot confirm a transition by itself',
    () async {
      final service = _PrefetchedNextService();
      var active = true;
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (totals, _) async {
          if (totals.videos > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.samplesAfterMove, greaterThanOrEqualTo(4));
      expect(service.swipes, 1);
    },
  );

  test('a failed swipe is never dispatched again', () async {
    final service = _Service()..allowMove = false;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await expectLater(
      runner.start(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Chưa xác nhận được video mới sau Next'),
        ),
      ),
    );
    expect(service.swipes, 1);
    expect(runner.totals.videos, 0);
    // Recovery on the same document must not dispatch an uncertain Next twice.
    await expectLater(
      runner.start(),
      throwsA(isA<NurturePlaybackUnavailable>()),
    );
    expect(service.swipes, 1);
    expect(runner.totals.videos, 0);
  });

  test('a TikTok playback error after Next reports playback failure', () async {
    final service = _Service()..playbackErrorAfterMove = true;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      likeRate: 0,
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await expectLater(
      runner.start(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('TikTok không phát được video này'),
        ),
      ),
    );
    expect(service.swipes, 1);
    expect(service.posts, 0);
    expect(runner.totals.videos, 0);
  });

  test('playback failure ignores comment text and hidden media errors', () {
    final error = _node(
      'panel.comment',
      const Rect.fromLTWH(100, 280, 200, 20),
      text:
          "We're having trouble playing this video. Please refresh and try again.",
    );
    final data = _frame();
    final nodes = data['nodes'] as List;
    final media = nodes.firstWhere((n) => n['id'] == '0.1.0');
    media['text'] = 'Watch in full screen';
    media['clickable'] = true;
    nodes.add(error);
    data['hidden'] = [
      {...error, 'id': '0.1.0.error'},
    ];
    expect(NurtureVideo.playbackFailed(SignupSnapshot(data)), isFalse);
  });

  for (final landscape in [false, true]) {
    test(
      'full video posts configured comment once (${landscape ? 'landscape' : 'portrait'})',
      () async {
        final service = _Service()..landscape = landscape;
        var active = true;
        final profile = NurtureCoordinateProfile({});
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: profile,
          comments: ['Configured comment'],
          isActive: () => active,
          isTikTok: () async => true,
          onProgress: (t, _) async {
            if (t.fullVideos > 0) active = false;
          },
          random: _Random(true),
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        expect(service.posts, 1);
        expect(service.pastes, 1);
        expect(runner.totals.comments, 1);
        expect(runner.totals.fullVideos, 1);
        expect(
          profile.points.keys.any(
            (key) =>
                key.startsWith(landscape ? 'landscape/' : 'portrait/') &&
                key.contains('/open-comments/'),
          ),
          true,
        );
        // Restarting on the same post retains its attempt ledger.
        active = false;
        await runner.start();
        expect(service.posts, 1);
      },
    );
  }

  test('a long video is commented within its first 20 seconds', () async {
    final service = _Service()..duration = 600;
    var active = true;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (t.fullVideos > 0) active = false;
      },
      commentRate: 1,
      random: _LatestRandom(),
      now: () => service.clock,
      delay: service.delay,
    );
    final start = service.clock;
    await runner.start();
    expect(service.posts, 1);
    // The latest draw starts at 20s; opening the panel and pasting add <2s.
    expect(
      service.postedAt!.difference(start),
      lessThanOrEqualTo(const Duration(seconds: 22)),
    );
    expect(runner.totals.watchMilliseconds, lessThanOrEqualTo(70000));
  });

  test('a 14s video plans no comment instead of abandoning one', () async {
    final service = _Service()..duration = 14;
    var active = true;
    final skipped = <String>[];
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (t.videos > 0) active = false;
      },
      onCommentSkipped: skipped.add,
      commentRate: 1,
      random: _LatestRandom(),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect([service.pastes, service.posts], [0, 0]);
    expect(skipped, isEmpty);
  });

  for (final duration in [15, 17, 30, 60]) {
    test(
      'latest comment on a ${duration}s video sends 5s before the end',
      () async {
        final service = _Service()..duration = duration;
        var active = true;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: ['Configured comment'],
          isActive: () => active,
          isTikTok: () async => true,
          onProgress: (t, _) async {
            if (t.fullVideos > 0) active = false;
          },
          commentRate: 1,
          random: _LatestRandom(),
          now: () => service.clock,
          delay: service.delay,
        );
        final start = service.clock;
        await runner.start();
        expect(service.posts, 1);
        expect(runner.totals.comments, 1);
        expect(
          service.postedAt!.difference(start).inMilliseconds,
          lessThan((duration - 5) * 1000),
        );
      },
    );
  }

  test('a panel opening too close to the end never receives text', () async {
    final service = _Service()..panelDelaySeconds = 22;
    var active = true;
    final skipped = <String>[];
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (t.fullVideos > 0) active = false;
      },
      onCommentSkipped: skipped.add,
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.pastes, 0);
    expect(service.posts, 0);
    expect(skipped, hasLength(1));
    expect(runner.totals.fullVideos, 1);
  });

  test('preexisting draft is preserved without input or submission', () async {
    final service = _Service()..length = 5;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await expectLater(runner.start(), throwsStateError);
    expect(service.pastes, 0);
    expect(service.posts, 0);
    expect(service.length, 5);
  });

  test(
    'queued nurture keeps watching a draft until the session deadline',
    () async {
      final service = _Service()
        ..panel = true
        ..length = 5;
      final deadline = service.clock.add(const Duration(seconds: 30));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(service.clock, deadline);
      expect(service.length, 5);
      expect(
        [service.taps, service.pastes, service.posts, service.swipes],
        [0, 0, 0, 0],
      );
      expect(runner.totals.watchMilliseconds, greaterThan(20000));
    },
  );

  test(
    'nurture continues after an unconfirmed comment without reposting it',
    () async {
      final service = _Service()..confirmPost = false;
      final deadline = service.clock.add(const Duration(minutes: 1));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(service.clock, deadline);
      // Each typed comment gets exactly one Post; the next post may get its
      // own comment, but an unconfirmed one is never sent again.
      expect(service.posts, service.pastes);
      expect(service.clears, service.posts);
      expect(runner.totals.comments, 0);
      expect(runner.totals.watchMilliseconds, greaterThan(30000));
    },
  );

  test(
    'a post that ends mid-comment clears the text and keeps nurturing',
    () async {
      final service = _Service()..moveOnPaste = true;
      final deadline = service.clock.add(const Duration(minutes: 1));
      final skipped = <String>[];
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        onCommentSkipped: skipped.add,
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(service.clock, deadline);
      // Never published on the post it was not typed for.
      expect(service.posts, lessThan(service.pastes));
      expect(service.clears, greaterThan(0));
      expect(skipped.first, contains('đã xóa nội dung đã nhập'));
      expect(runner.hasPendingCommentDraft, isFalse);
    },
  );

  test('an unconfirmed comment is dispatched once and never counted', () async {
    final service = _Service()..confirmPost = false;
    var until = service.clock.add(const Duration(seconds: 25));
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => service.clock.isBefore(until),
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.posts, 1);
    expect(runner.totals.comments, 0);
    // A restarted runner on the same post never sends it again.
    until = service.clock.add(const Duration(seconds: 3));
    await runner.start();
    expect(service.posts, 1);
  });

  test(
    'an uncertain draft is cleared and nurture moves on while the editor is missing',
    () async {
      final service = _MissingDraftService()..confirmPost = false;
      final deadline = service.clock.add(const Duration(minutes: 1));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(runner.hasPendingCommentDraft, isFalse);
      expect(service.posts, service.pastes);
      expect(service.clears, greaterThan(0));
      expect(service.swipes, greaterThan(0));
      expect(runner.totals.comments, 0);
      expect(runner.totals.watchMilliseconds, greaterThan(30000));
    },
  );

  test(
    'a hidden feed comment draft is kept while nurturing moves on',
    () async {
      final service = _Service()
        ..hiddenEditor = true
        ..panel = true
        ..length = 5;
      final deadline = service.clock.add(const Duration(minutes: 1));
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => service.clock.isBefore(deadline),
        isTikTok: () async => true,
        onProgress: (_, _) async {},
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect([service.taps, service.pastes, service.posts], [0, 0, 0]);
      expect(service.swipes, greaterThan(0));
      expect(service.clears, 0);
      expect(service.length, 5);
    },
  );

  for (final scenario in [
    'panel-did-not-open',
    'hidden-empty-editor',
    'clock-reflow',
    'focus-not-ready',
    'late-panel',
    'empty-panel-on-start',
    'public-comment-captcha',
    'editor-unavailable',
    'paste-not-inserted',
  ]) {
    test('nurture continues through $scenario without switching off', () async {
      final service = _Service();
      switch (scenario) {
        case 'panel-did-not-open':
          service.openWorks = false;
          service.searchEditor = true;
        case 'hidden-empty-editor':
          service.hiddenEditor = true;
        case 'clock-reflow':
          service.missingClockAfterOpen = 3;
        case 'focus-not-ready':
          service.focusWorks = false;
        case 'late-panel':
          service.panelDelaySeconds = 22;
        case 'empty-panel-on-start':
          service.panel = true;
        case 'public-comment-captcha':
          service.publicComment = 'captcha in this video';
        case 'editor-unavailable':
          service.pasteReason = 'editor-unavailable:no-focused-editor';
        case 'paste-not-inserted':
          service.pasteReason = 'paste-not-inserted';
      }
      var active = true;
      final skipped = <String>[];
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (totals, _) async {
          if (totals.fullVideos > 0) active = false;
        },
        onCommentSkipped: skipped.add,
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      expect(runner.totals.fullVideos, 1);
      expect(service.panel, isFalse);
      if (scenario == 'panel-did-not-open' ||
          scenario == 'focus-not-ready' ||
          scenario == 'late-panel' ||
          scenario == 'hidden-empty-editor') {
        expect(service.pastes, 0);
        expect(service.posts, 0);
        expect(skipped, hasLength(1));
        if (scenario == 'panel-did-not-open') {
          expect(service.taps, 1);
          expect(service.closes, 0);
          expect(skipped.single, contains('mở khung bình luận'));
        }
      } else if (scenario == 'editor-unavailable' ||
          scenario == 'paste-not-inserted') {
        expect(service.pastes, 1);
        expect(service.posts, 0);
        expect(skipped.single, contains(service.pasteReason));
      } else {
        expect(service.posts, 1);
        expect(runner.totals.comments, 1);
      }
    });
  }

  for (final (hidden, enabled) in [
    (false, true),
    (false, false),
    (true, false),
  ]) {
    test(
      'opening timeout preserves an unrecognized draft (hidden=$hidden, enabled=$enabled)',
      () async {
        final service = _UnrecognizedDraftService(
          hidden: hidden,
          enabled: enabled,
        );
        final skipped = <String>[];
        final deadline = service.clock.add(const Duration(minutes: 1));
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: ['Configured comment'],
          isActive: () => service.clock.isBefore(deadline),
          isTikTok: () async => true,
          onProgress: (_, _) async {},
          onCommentSkipped: skipped.add,
          likeRate: 0,
          commentRate: 1,
          random: _Random(true),
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        expect(skipped.first, contains('bỏ qua và tiếp tục nuôi'));
        expect(skipped.last, contains('không bình luận thêm'));
        // The unknown draft is neither closed, cleared, typed into nor sent.
        expect(service.taps, 1);
        expect(service.closes, 0);
        expect(service.clears, 0);
        expect(service.pastes, 0);
        expect(service.posts, 0);
        expect(service.swipes, greaterThan(0));
      },
    );
  }

  test('music label reflow does not change the post identity', () {
    final feed = _frame();
    final panel = _frame(panel: true);
    (feed['nodes'] as List).add(
      _node(
        '0.1.sound',
        const Rect.fromLTWH(100, 500, 100, 20),
        description: 'Watch more videos with music soundtrack',
      ),
    );
    expect(
      NurtureVideo.read(SignupSnapshot(feed))!.key,
      NurtureVideo.read(SignupSnapshot(panel))!.key,
    );
  });

  test('a slow coordinate save cannot send after the comment window', () async {
    final service = _Service();
    final profile = NurtureCoordinateProfile(
      {},
      save: (points) async {
        if (points.keys.any((key) => key.contains('/post-comment/'))) {
          // Reach the deadline 5s before the end, without wrapping around.
          final position =
              service.clock.difference(DateTime(2026)).inSeconds %
              service.duration;
          service.clock = service.clock.add(
            Duration(seconds: service.duration - 5 - position),
          );
        }
      },
    );
    final deadline = service.clock.add(const Duration(minutes: 1));
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: profile,
      comments: ['Configured comment'],
      isActive: () => service.clock.isBefore(deadline),
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.posts, 0);
    // The late text is removed instead of being kept or carried on.
    expect(service.clears, greaterThan(0));
    expect(service.length, 0);
    // Held for the whole session, released once when it ends.
    expect(service.keyboardPolicies.first, isTrue);
    expect(service.keyboardPolicies.where((p) => !p), [false]);
    expect(service.keyboardPolicies.last, isFalse);
  });

  test('ambiguous visible videos are not classified or tapped', () {
    final a = _frame(), b = _frame(card: '0.2', landscape: true);
    final s = SignupSnapshot({
      ...a,
      'nodes': [...a['nodes'], ...b['nodes']],
    });
    expect(NurtureVideo.read(s), isNull);
  });

  test('a cancelled save prevents the first comment tap', () async {
    final service = _Service();
    var active = true;
    final profile = NurtureCoordinateProfile(
      {},
      save: (_) async {
        active = false;
      },
    );
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: profile,
      comments: ['Configured comment'],
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(service.taps, 0);
    expect(service.posts, 0);
  });

  test('unknown origin prevents every gesture', () async {
    final service = _Service();
    await expectLater(
      NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        isActive: () => true,
        isTikTok: () async => false,
        onProgress: (_, _) async {},
        now: () => service.clock,
        delay: service.delay,
      ).start(),
      throwsStateError,
    );
    expect(service.taps, 0);
    expect(service.swipes, 0);
  });

  test('the search-result player is read by its video id', () async {
    final service = _SearchService()
      ..state = 'player'
      ..clock = DateTime(2026).add(const Duration(seconds: 7));
    final video = NurtureVideo.read(await service.snapshot())!;
    expect(video.detail, isTrue);
    expect(video.key, 'detail|900001|30');
    expect(video.position, 7);
    expect(video.comments, isNull);
    expect(video.next, isNotNull);
    expect(video.orientation, NurtureVideoOrientation.detail);
  });

  for (final (reveals, moves) in [
    (true, true),
    (false, false),
    (true, false),
  ]) {
    test(
      'Search checks a visible Post before paste (reveal=$reveals, moves=$moves)',
      () async {
        final service = _SearchService()
          ..state = 'player'
          ..revealWorks = reveals
          ..revealMovesPost = moves;
        final deadline = service.clock.add(const Duration(seconds: 28));
        final skipped = <String>[];
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: ['Configured comment'],
          isActive: () => service.clock.isBefore(deadline),
          isTikTok: () async => true,
          onProgress: (_, _) async {},
          onCommentSkipped: skipped.add,
          likeRate: 0,
          commentRate: 1,
          longWatchRate: 1,
          random: _Random(true),
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        if (reveals && moves) {
          expect(service.pasted, ['comment:Configured comment']);
          expect(service.tapped.where((a) => a == 'post'), hasLength(1));
          expect(runner.totals.comments, 1);
          expect(runner.hasPendingCommentDraft, isFalse);
        } else if (!reveals) {
          // Clipped past the WebView edge: sent once through Accessibility.
          expect(service.pasted, ['comment:Configured comment']);
          expect(service.tapped, isNot(contains('post')));
          expect(service.tapped.where((a) => a == 'a11y-post'), hasLength(1));
          expect(service.tapped.where((a) => a.startsWith('stray')), isEmpty);
          expect(runner.totals.comments, 1);
          expect(runner.hasPendingCommentDraft, isFalse);
          expect(skipped, isEmpty);
        } else {
          expect(service.pasted, isEmpty);
          expect(service.tapped, isNot(contains('post')));
          expect(runner.totals.comments, 0);
          expect(runner.hasPendingCommentDraft, isFalse);
          expect(skipped, hasLength(1));
        }
      },
    );
  }

  test('a refused clipped Post is cleared and never resent', () async {
    final service = _SearchService()
      ..state = 'player'
      ..revealWorks = false
      ..revealMovesPost = false
      ..submitAccepted = false;
    final deadline = service.clock.add(const Duration(seconds: 28));
    final skipped = <String>[];
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: ['Configured comment'],
      isActive: () => service.clock.isBefore(deadline),
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      onCommentSkipped: skipped.add,
      likeRate: 0,
      commentRate: 1,
      longWatchRate: 1,
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    expect(service.pasted, ['comment:Configured comment']);
    expect(service.submits, 5);
    expect(service.commentText, isEmpty);
    expect(runner.totals.comments, 0);
    expect(runner.hasPendingCommentDraft, isFalse);
    expect(skipped.first, contains('đã xóa nội dung đã nhập'));
  });

  test(
    'reads the Gecko search player after its playback controls fade out',
    () async {
      final service = _SearchService(hiddenClock: true)
        ..state = 'player'
        ..clock = DateTime(2026).add(const Duration(seconds: 7));
      final snapshot = await service.snapshot();
      expect(snapshot.nodes.any((n) => n.id == '9.0.1'), isFalse);
      final video = NurtureVideo.read(snapshot);
      expect(video, isNotNull);
      expect(video!.position, 7);
      expect(video.duration, 30);
      expect(video.key, 'detail|900001|30');
    },
  );

  test('the search-result player exposes its "N Likes" toggle', () async {
    final service = _SearchService()..state = 'player';
    for (final (label, count) in [('35 Likes', 35), ('97.8K Likes', null)]) {
      final snapshot = await service.snapshot();
      snapshot.nodes.add(
        SignupNode({
          'id': '9.1.2.0',
          'className': 'android.widget.ToggleButton',
          'text': label,
          'clickable': true,
          'enabled': true,
          'bounds': [265, 240, 300, 260],
        }),
      );
      final video = NurtureVideo.read(snapshot)!;
      expect(video.like?.text, label);
      expect(video.likeCount, count);
    }
  });

  for (final delaySeconds in [0, 5]) {
    test(
      'search ignores the feed fullscreen button (results delayed ${delaySeconds}s)',
      () async {
        final service = _SearchService(
          feedTile: true,
          resultDelaySeconds: delaySeconds,
        );
        var active = true;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: [],
          searchKeyword: 'Cats',
          isActive: () => active,
          isTikTok: () async => true,
          onProgress: (totals, _) async {
            if (!service.tapped.contains('result')) {
              expect(totals.watchMilliseconds, 0);
            }
            if (totals.videos > 0) active = false;
          },
          likeRate: 0,
          longWatchRate: 0,
          commentRate: 0,
          random: _Random(false),
          now: () => service.clock,
          delay: service.delay,
        );
        await runner.start();
        expect(service.pasted, ['search:Cats']);
        expect(service.tapped, [
          'open',
          'view-all',
          'videos-tab',
          'result',
          'next',
        ]);
        expect(runner.totals.skippedVideos, 1);
      },
    );
  }

  test('search mode recognizes the narrow desktop search drawer', () async {
    final service = _SearchService(narrowDrawer: true);
    var active = true;
    await NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      searchKeyword: 'Cats',
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (t.videos > 0) active = false;
      },
      longWatchRate: 0,
      commentRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(service.pasted, ['search:Cats']);
    expect(service.tapped, [
      'open',
      'view-all',
      'videos-tab',
      'result',
      'next',
    ]);
  });

  test(
    'search mode enters the keyword via Accessibility and watches results',
    () async {
      final service = _SearchService();
      var active = true;
      NurtureTotals? totals;
      final profile = NurtureCoordinateProfile({});
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: profile,
        comments: [],
        searchKeyword: 'Cats',
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (t.videos > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.pasted, ['search:Cats']);
      expect(service.tapped, [
        'open',
        'view-all',
        'videos-tab',
        'result',
        'next',
      ]);
      expect(totals!.skippedVideos, 1);
      expect(profile.points.keys, contains('detail/feed/next-video'));
    },
  );

  test('a photo post in the search player is recognised and skipped', () async {
    final service = _SearchService()..photos.add(2);
    var active = true;
    final start = service.clock;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      searchKeyword: 'Cats',
      isActive: () => active,
      isTikTok: () async => true,
      onProgress: (t, _) async {
        if (service.video == 3 && t.watchMilliseconds > 0) active = false;
      },
      longWatchRate: 0,
      commentRate: 0,
      likeRate: 0,
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    );
    await runner.start();
    // Next reached the photo, which was skipped once without a 30s stall.
    expect(service.tapped.sublist(service.tapped.indexOf('result')), [
      'result',
      'next',
      'next',
    ]);
    expect(runner.totals.skippedVideos, 1);
    expect(
      service.clock.difference(start),
      lessThan(const Duration(seconds: 30)),
    );
  });

  test(
    'the search player autoplaying onto a photo needs no Next tap',
    () async {
      final service = _SearchService()..photos.add(2);
      var active = true;
      final runner = NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile(
          {},
          save: (points) async {
            // The post ends and TikTok opens the next (a photo) by itself.
            if (points.containsKey('detail/feed/next-video') &&
                service.video == 1) {
              service.video++;
            }
          },
        ),
        comments: [],
        searchKeyword: 'Cats',
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          if (service.video == 3 && t.watchMilliseconds > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        likeRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      );
      await runner.start();
      // Post 1 counted without a tap; the photo skipped with one tap.
      expect(service.tapped.sublist(service.tapped.indexOf('result')), [
        'result',
        'next',
      ]);
      expect(runner.totals.skippedVideos, 1);
    },
  );

  test(
    'closes the search drawer before tapping results and tracks a hidden clock',
    () async {
      final service = _SearchService(hiddenClock: true, keepsDrawer: true);
      var active = true;
      NurtureTotals? totals;
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        searchKeyword: 'Cats',
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (t.videos > 0) active = false;
        },
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.tapped, [
        'open',
        'view-all',
        'close-search',
        'videos-tab',
        'result',
        'next',
      ]);
      expect(totals!.skippedVideos, 1);
      expect(totals!.watchMilliseconds, greaterThan(0));
    },
  );

  test(
    'opens a non-LIVE result when the submitted search keeps its drawer and has no Videos tab',
    () async {
      final service = _SearchService(
        keepsDrawer: true,
        hasVideosTab: false,
        liveResult: true,
      );
      var active = true;
      NurtureTotals? totals;
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: [],
        searchKeyword: 'Cats',
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (t.videos > 0) active = false;
        },
        likeRate: 0,
        longWatchRate: 0,
        commentRate: 0,
        random: _Random(false),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.pasted, ['search:Cats']);
      expect(service.tapped, [
        'open',
        'view-all',
        'close-search',
        'result',
        'next',
      ]);
      expect(totals!.skippedVideos, 1);
    },
  );

  for (final scrollWorks in [true, false]) {
    test(
      'combined desktop results scroll past LIVE at most twice ($scrollWorks)',
      () async {
        final service = _SearchService(
          keepsDrawer: true,
          hasVideosTab: false,
          liveResult: true,
          resultsBelowLive: true,
          scrollWorks: scrollWorks,
        );
        var active = true;
        final runner = NurtureAccessibilityRunner(
          accessibility: service,
          profile: NurtureCoordinateProfile({}),
          comments: [],
          searchKeyword: 'Cats',
          isActive: () => active,
          isTikTok: () async => true,
          onProgress: (t, _) async {
            if (t.videos > 0) active = false;
          },
          likeRate: 0,
          commentRate: 0,
          longWatchRate: 0,
          random: _Random(false),
          now: () => service.clock,
          delay: service.delay,
        );
        if (scrollWorks) {
          await runner.start();
          expect(service.tapped, contains('result'));
          expect(runner.totals.videos, 1);
        } else {
          await expectLater(runner.start(), throwsStateError);
          expect(service.tapped, isNot(contains('result')));
        }
        expect(
          service.tapped.where((t) => t == 'scroll-results'),
          hasLength(2),
        );
        expect(service.tapped.where((t) => t.startsWith('stray')), isEmpty);
      },
    );
  }

  test(
    'an unavailable search comment editor does not stop viewing before any paste',
    () async {
      final service = _SearchService(hiddenClock: true, hiddenEditor: true);
      var active = true;
      final skipped = <String>[];
      NurtureTotals? totals;
      await NurtureAccessibilityRunner(
        accessibility: service,
        profile: NurtureCoordinateProfile({}),
        comments: ['Configured comment'],
        searchKeyword: 'Cats',
        isActive: () => active,
        isTikTok: () async => true,
        onProgress: (t, _) async {
          totals = t;
          if (service.tapped.contains('next')) active = false;
        },
        onCommentSkipped: skipped.add,
        likeRate: 0,
        longWatchRate: 1,
        commentRate: 1,
        random: _Random(true),
        now: () => service.clock,
        delay: service.delay,
      ).start();
      expect(service.pasted, ['search:Cats']);
      expect(skipped, hasLength(1));
      expect(totals!.comments, 0);
      expect(totals!.videos, 1);
      expect(service.tapped.last, 'next');
    },
  );
}
