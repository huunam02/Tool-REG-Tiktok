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
      panel = true;
      missingClockFrames = missingClockAfterOpen;
      clock = clock.add(Duration(seconds: panelDelaySeconds));
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
    return {'ok': true};
  }

  @override
  Future<void> setKeyboardSuppressed(bool value) async {
    suppressed = value;
    keyboardPolicies.add(value);
  }

  @override
  Future<void> dismissKeyboard() async {
    keyboard = false;
  }

  @override
  Future<void> cancelPaste() async {}
}

/// TikTok's sidebar search → suggestions → Videos tab → result player.
class _SearchService extends SignupAccessibility {
  _SearchService({
    this.hiddenClock = false,
    this.keepsDrawer = false,
    this.hiddenEditor = false,
    this.hasVideosTab = true,
    this.liveResult = false,
  });
  final bool hiddenClock, keepsDrawer, hiddenEditor, hasVideosTab, liveResult;
  bool drawerClosed = false;
  DateTime clock = DateTime(2026);
  String state = 'feed';
  int video = 1;
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
          const Rect.fromLTWH(45, 90, 150, 20),
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
            '0.7.live.0',
            const Rect.fromLTWH(45, 185, 30, 15),
            text: 'LIVE',
          ),
        ]);
      }
      for (var i = 0; i < 4; i++) {
        nodes.add(
          _button(
            '0.7.$i',
            Rect.fromLTWH(40.0 + i * 90, 40, 80, 120),
            description: 'Watch in full screen',
          ),
        );
      }
    }
    if (state == 'player') {
      final position = clock.difference(DateTime(2026)).inSeconds % 30;
      nodes.addAll([
        {..._node('9', vp), 'className': 'android.app.AlertDialog'},
        _node('9.0', const Rect.fromLTWH(0, 0, 260, 800)),
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
          text: 'https:[email]/video/90000$video?is_from_webapp=1',
        ),
        _node('9.3', const Rect.fromLTWH(260, 770, 140, 20)),
        _node(
          '9.3.0.1',
          const Rect.fromLTWH(265, 772, 130, 15),
          editor: true,
          clickable: true,
          hint: 'Add comment...',
        ),
      ]);
    }
    final hidden = nodes
        .where(
          (n) =>
              (hiddenClock && n['id'] == '9.0.1') ||
              (hiddenEditor && n['id'] == '9.3.0.1'),
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
  Future<void> tap(SignupViewport viewport, Offset p) async {
    bool hit(double x, double y, double w, double h) =>
        Rect.fromLTWH(x, y, w, h).contains(p);
    if (state == 'feed' && hit(10, 100, 20, 20)) {
      tapped.add('open');
      state = 'drawer';
    } else if (state == 'typed' && hit(40, 300, 160, 20)) {
      tapped.add('view-all');
      state = 'results';
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
    } else {
      tapped.add('stray $p');
    }
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pasted.add('$field:$text');
    if (state == 'drawer') state = 'typed';
    return {'ok': true};
  }

  @override
  Future<void> setKeyboardSuppressed(bool value) async {}

  @override
  Future<void> cancelPaste() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
        isA<StateError>().having(
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

  for (final seconds in [12, 25]) {
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
      if (seconds < 20) {
        await runner.start();
        expect(runner.totals.videos, 1);
      } else {
        await expectLater(runner.start(), throwsStateError);
        expect(runner.totals.videos, 0);
      }
      expect(service.swipes, 1);
    });
  }

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
    await expectLater(runner.start(), throwsStateError);
    expect(service.swipes, 1);
    expect(runner.totals.videos, 0);
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

  test('an unconfirmed comment is dispatched once and never counted', () async {
    final service = _Service()..confirmPost = false;
    var until = service.clock.add(const Duration(minutes: 1));
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
    await expectLater(runner.start(), throwsStateError);
    expect(service.posts, 1);
    expect(runner.totals.comments, 0);
    until = service.clock.add(const Duration(seconds: 3));
    await runner.start();
    expect(service.posts, 1);
  });

  test('a hidden feed comment draft is preserved before any gesture', () async {
    final service = _Service()
      ..hiddenEditor = true
      ..panel = true
      ..length = 5;
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
    expect(
      [service.taps, service.pastes, service.posts, service.swipes],
      [0, 0, 0, 0],
    );
    expect(service.length, 5);
  });

  for (final scenario in [
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
        case 'hidden-empty-editor':
          service.hiddenEditor = true;
        case 'clock-reflow':
          service.missingClockAfterOpen = 3;
        case 'focus-not-ready':
          service.focusWorks = false;
        case 'late-panel':
          service.panelDelaySeconds = 15;
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
      if (scenario == 'focus-not-ready' ||
          scenario == 'late-panel' ||
          scenario == 'hidden-empty-editor') {
        expect(service.pastes, 0);
        expect(service.posts, 0);
        expect(skipped, hasLength(1));
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
          service.clock = service.clock.add(const Duration(seconds: 25));
        }
      },
    );
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: profile,
      comments: ['Configured comment'],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
      random: _Random(true),
      now: () => service.clock,
      delay: service.delay,
    );
    await expectLater(runner.start(), throwsStateError);
    expect(service.posts, 0);
    expect(service.length, greaterThan(0));
    expect(service.keyboardPolicies, [true, false]);
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
