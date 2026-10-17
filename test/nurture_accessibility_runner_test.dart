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

Map<String, dynamic> _frame({
  int position = 0,
  int duration = 30,
  bool landscape = false,
  bool panel = false,
  bool focused = false,
  int length = 0,
  bool posted = false,
  String card = '0.1',
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
        text:
            '00:${position.toString().padLeft(2, '0')} / 00:${duration.toString().padLeft(2, '0')}',
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
  bool focusWorks = true;
  int missingClockAfterOpen = 0, missingClockFrames = 0, panelDelaySeconds = 0;
  int closes = 0;
  String? publicComment;
  final keyboardPolicies = <bool>[];
  int length = 0, taps = 0, swipes = 0, posts = 0, pastes = 0;
  int? forcePosition;
  @override
  Future<SignupSnapshot> snapshot() async {
    final data = {
      ..._frame(
        position:
            forcePosition ??
            (stall ? 0 : clock.difference(DateTime(2026)).inSeconds % 30),
        landscape: landscape,
        panel: panel,
        focused: focused,
        length: length,
        posted: posted,
        card: moved ? '0.2' : '0.1',
      ),
      'keyboardVisible': keyboard,
    };
    final nodes = data['nodes'] as List;
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
    if (!panel) {
      panel = true;
      missingClockFrames = missingClockAfterOpen;
      clock = clock.add(Duration(seconds: panelDelaySeconds));
    } else if (p.dy < 50) {
      panel = false;
      closes++;
    } else if (p.dx > 370) {
      posts++;
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
  }

  @override
  Future<Map<String, dynamic>> paste(String text, String field) async {
    pastes++;
    expect(field, 'comment');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
        v.comments,
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
    'saved orientation points survive restart and reject a shifted button',
    () async {
      final profile = await NurtureCoordinateProfile.load();
      final s = SignupSnapshot(_frame(landscape: true));
      final v = NurtureVideo.read(s)!;
      final key = '${v.layout(s.viewport)}/open-comments';
      final point = await profile.target(key, s.viewport, v.comments);
      final restored = await NurtureCoordinateProfile.load();
      expect(restored.point(key), point);
      await expectLater(
        restored.target(
          key,
          s.viewport,
          SignupNode(_node('moved', const Rect.fromLTWH(350, 500, 30, 30))),
        ),
        throwsStateError,
      );
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
      random: _Random(false),
      now: () => service.clock,
      delay: service.delay,
    ).start();
    expect(totals!.watchMilliseconds, 0);
    expect(service.swipes, 0);
  });

  test('a failed swipe is never dispatched again', () async {
    final service = _Service()..allowMove = false;
    final runner = NurtureAccessibilityRunner(
      accessibility: service,
      profile: NurtureCoordinateProfile({}),
      comments: [],
      isActive: () => true,
      isTikTok: () async => true,
      onProgress: (_, _) async {},
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
                key.endsWith('/open-comments'),
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

  for (final scenario in [
    'clock-reflow',
    'focus-not-ready',
    'late-panel',
    'empty-panel-on-start',
    'public-comment-captcha',
  ]) {
    test('nurture continues through $scenario without switching off', () async {
      final service = _Service();
      switch (scenario) {
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
      if (scenario == 'focus-not-ready' || scenario == 'late-panel') {
        expect(service.pastes, 0);
        expect(service.posts, 0);
        expect(skipped, hasLength(1));
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
}
