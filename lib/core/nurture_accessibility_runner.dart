import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'nurture_coordinate_profile.dart';
import 'nurture_data.dart';
import 'signup_accessibility.dart';

enum NurtureVideoOrientation { portrait, landscape }

/// Geometry comes from the playing video's accessible container, not the phone.
class NurtureVideo {
  NurtureVideo({
    required this.key,
    required this.position,
    required this.duration,
    required this.bounds,
    required this.comments,
    this.next,
  });
  final String key;
  final int position, duration;
  final Rect bounds;
  final SignupNode comments;
  final SignupNode? next;
  NurtureVideoOrientation get orientation => bounds.width > bounds.height
      ? NurtureVideoOrientation.landscape
      : NurtureVideoOrientation.portrait;

  String layout(SignupViewport viewport) {
    final a = viewport.fromScreen(bounds.topLeft);
    final b = viewport.fromScreen(bounds.bottomRight);
    // A 4:5 portrait and a 9:16 portrait can also have different button rows.
    return '${orientation.name}/${a.dx.round()}-${a.dy.round()}-${b.dx.round()}-${b.dy.round()}';
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
          ).hasMatch(n.description),
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
      final up = nodes['$page.1.0.0.0'];
      final down = nodes['$page.1.0.1.0'];
      final pairedNavigation =
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
          down.bounds.left > media.right;
      candidates.add(
        NurtureVideo(
          // Music labels can disappear/reappear when the comment panel opens.
          // They describe the layout, not a change of the playing post.
          key: '$card|$author|$duration',
          position: position,
          duration: duration,
          bounds: media,
          comments: button,
          next: pairedNavigation ? down : null,
        ),
      );
    }
    // Multiple exposed posts are ambiguous; don't comment on a guessed card.
    return candidates.length == 1 ? candidates.single : null;
  }
}

class NurtureCancelled implements Exception {}

class _CommentNotReady implements Exception {
  const _CommentNotReady(this.message);
  final String message;
}

class _WatchPlan {
  _WatchPlan(this.full, this.skipAt, this.commentAt);
  final bool full;
  final int skipAt, commentAt;
  int watched = 0;
  bool completed = false, commentAttempted = false;
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
  final Random _random;
  final DateTime Function() _now;
  final Future<void> Function(Duration)? _delay;
  Timer? _sleepTimer;
  Completer<void>? _sleepCompleter;
  final _plans = <String, _WatchPlan>{};
  int _sequence = 0, _watchMs = 0, _full = 0, _skipped = 0, _comments = 0;
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
  );

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
    final full = _random.nextBool();
    final latest = (video.duration * .7).floor() - 6;
    final commentAt = latest >= 5 && comments.isNotEmpty
        ? 5 + _random.nextInt(latest - 4)
        : -1;
    return _WatchPlan(
      full,
      min(2 + _random.nextInt(4), max(1, video.duration ~/ 2)),
      commentAt,
    );
  });

  Future<void> _emit() => onProgress(totals, ++_sequence);

  Future<SignupSnapshot> _snapshot() async {
    _check();
    if (!await isTikTok()) {
      throw StateError('Đã rời TikTok; dừng nuôi tài khoản.');
    }
    _check();
    final s = await accessibility.snapshot();
    _check();
    if (!s.ready || !s.viewport.valid) {
      throw StateError('Khung nuôi cần cố định 400×800.');
    }
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
    final cardRoot = current?.key.split('|').first;
    bool within(String id, String? root) =>
        root != null && (id == root || id.startsWith('$root.'));
    // Video captions and public comments are content, never system prompts.
    final prompts = s.nodes
        .where((n) => !within(n.id, cardRoot) && !within(n.id, panelRoot))
        .toList();
    bool hasPrompt(RegExp pattern) => prompts.any(
      (n) => [n.text, n.description, n.hint].any(pattern.hasMatch),
    );
    if (hasPrompt(
      RegExp(
        r'captcha|drag.*slider|verify to continue|kéo.*thanh trượt',
        caseSensitive: false,
      ),
    )) {
      throw StateError('TikTok yêu cầu xác minh; đã dừng nuôi để bạn xử lý.');
    }
    if (prompts.any((n) => n.className.endsWith('Dialog'))) {
      throw StateError('TikTok đang mở hộp thoại; đã dừng nuôi.');
    }
    if (hasPrompt(RegExp(r'^Log in to TikTok$', caseSensitive: false))) {
      throw StateError('TikTok yêu cầu đăng nhập lại; đã dừng nuôi.');
    }
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
    try {
      while (true) {
        final s = await _snapshot();
        final video = NurtureVideo.read(s);
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
        if (plan.completed || (!plan.full && plan.watched >= plan.skipAt)) {
          await _advance(s, video, plan);
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
    // One advance only. No repeat if the UI failed to move.
    final deadline = _now().add(const Duration(seconds: 8));
    while (_now().isBefore(deadline)) {
      await _sleep();
      final current = NurtureVideo.read(await _snapshot());
      if (current != null && current.key != video.key) {
        if (!plan.completed) {
          plan.completed = true;
          _skipped++;
          await _emit();
        }
        _previous = current;
        return;
      }
    }
    throw StateError('Chưa chuyển được video; đã dừng để kiểm tra tọa độ.');
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
    } while (_now().isBefore(until));
    throw const _CommentNotReady('Bình luận chưa sẵn sàng.');
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
    var pasteAttempted = false;
    try {
      final kind = video.orientation.name;
      await _tap(
        '${video.layout(s.viewport)}/open-comments',
        s,
        video.comments,
      );
      s = await _waitFor(
        video.key,
        (s) => _editor(s) != null && _close(s) != null,
      );
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
          throw StateError(
            'Không nhập được bình luận qua Accessibility; đã giữ bản nháp.',
          );
        }
        await accessibility.dismissKeyboard();
      } finally {
        await accessibility.setKeyboardSuppressed(false);
      }
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
      if (!pasteAttempted && await _closeEmptyComments()) {
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
