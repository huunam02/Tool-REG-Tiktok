import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'firefox_user_agent.dart';
import 'signup_accessibility.dart';

class RotateCaptchaChallenge {
  const RotateCaptchaChallenge({
    required this.outer,
    required this.inner,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.x,
    required this.y,
    required this.travel,
  });
  final String outer, inner;
  final double viewportWidth, viewportHeight, x, y, travel;

  static RotateCaptchaChallenge? fromResult(dynamic value) {
    if (value == null || value == 'null') return null;
    final raw = value is String ? jsonDecode(value) : value;
    if (raw is! Map) throw StateError('Không đọc được CAPTCHA xoay.');
    double number(String name) {
      final n = raw[name];
      if (n is! num || !n.isFinite) {
        throw StateError('Tọa độ CAPTCHA không hợp lệ.');
      }
      return n.toDouble();
    }

    final c = RotateCaptchaChallenge(
      outer: raw['outer'] as String,
      inner: raw['inner'] as String,
      viewportWidth: number('viewportWidth'),
      viewportHeight: number('viewportHeight'),
      x: number('x'),
      y: number('y'),
      travel: number('travel'),
    );
    if (c.outer.isEmpty ||
        c.inner.isEmpty ||
        c.viewportWidth <= 0 ||
        c.viewportHeight <= 0 ||
        c.x < 0 ||
        c.y < 0 ||
        c.travel <= 0 ||
        c.x + c.travel >= c.viewportWidth ||
        c.y >= c.viewportHeight) {
      throw StateError('Thanh kéo CAPTCHA nằm ngoài WebView.');
    }
    return c;
  }

  bool sameAs(RotateCaptchaChallenge other) =>
      outer == other.outer &&
      inner == other.inner &&
      viewportWidth == other.viewportWidth &&
      viewportHeight == other.viewportHeight &&
      x == other.x &&
      y == other.y &&
      travel == other.travel;

  Offset screenPoint(Rect bounds, double angle) =>
      bounds.topLeft +
      Offset(
        (x + travel * angle / 360) * bounds.width / viewportWidth,
        y * bounds.width / viewportWidth,
      );
}

/// Taps the puzzle's refresh control through Accessibility: the control the
/// Accessibility tree names, else the one [readGeometry] locates in CSS
/// pixels (`{viewportWidth, x, y}`).
Future<void> refreshRotateCaptcha({
  required SignupAccessibility accessibility,
  required Future<dynamic> Function() readGeometry,
  required Future<void> Function() guard,
}) async {
  final snapshot = await accessibility.snapshot();
  await guard();
  final bounds = snapshot.viewport.bounds;
  if (!snapshot.ready || !bounds.isFinite || bounds.isEmpty) {
    throw StateError('Không đọc được WebView để đổi mã CAPTCHA.');
  }
  final named = snapshot.nodes
      .where(
        (n) =>
            n.clickable &&
            n.enabled &&
            RegExp(
              r'^(refresh|reload)\b',
              caseSensitive: false,
            ).hasMatch(n.label.trim()) &&
            !n.bounds.intersect(bounds).isEmpty,
      )
      .toList();
  Offset? point = named.length == 1
      ? named.single.bounds.intersect(bounds).center
      : null;
  if (point == null) {
    final value = await readGeometry();
    await guard();
    final raw = value is String ? jsonDecode(value) : value;
    if (raw is Map &&
        raw['viewportWidth'] is num &&
        raw['x'] is num &&
        raw['y'] is num &&
        (raw['viewportWidth'] as num) > 0) {
      final scale = bounds.width / (raw['viewportWidth'] as num);
      point =
          bounds.topLeft +
          Offset((raw['x'] as num) * scale, (raw['y'] as num) * scale);
    }
  }
  if (point == null || !bounds.contains(point)) {
    throw StateError('Không tìm thấy nút đổi mã CAPTCHA. Hãy xử lý thủ công.');
  }
  await accessibility.tapScreen(bounds, point);
}

/// Owns one solve attempt; closes pending network work on exit/cancellation.
class RotateCaptchaSolver {
  RotateCaptchaSolver({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  final _random = math.Random();
  final _abort = Completer<void>();
  bool _closed = false;
  Timer? _pauseTimer;
  Completer<void>? _pauseCompleter;

  Future<void> _pause(int milliseconds) async {
    final completion = _pauseCompleter = Completer<void>();
    _pauseTimer = Timer(
      Duration(milliseconds: milliseconds),
      completion.complete,
    );
    try {
      await completion.future;
    } finally {
      _pauseTimer?.cancel();
      _pauseTimer = null;
      _pauseCompleter = null;
    }
  }

  Future<String> _image(String source) async {
    const limit = 5 * 1024 * 1024;
    if (source.startsWith('data:image/')) {
      final data = UriData.parse(source);
      final bytes = data.contentAsBytes();
      if (bytes.isEmpty || bytes.length > limit) {
        throw StateError('Ảnh CAPTCHA không hợp lệ.');
      }
      return base64Encode(bytes);
    }
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('Không hỗ trợ URL ảnh CAPTCHA này.');
    }
    // TikTok's CDN sees the same browser as the page, not dart:io.
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['User-Agent'] = firefoxDesktopUserAgent;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw StateError('Không tải được ảnh CAPTCHA.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > limit) throw StateError('Ảnh CAPTCHA quá lớn.');
    }
    if (bytes.isEmpty) throw StateError('Ảnh CAPTCHA rỗng.');
    return base64Encode(bytes);
  }

  Future<double> angle(RotateCaptchaChallenge challenge, String key) async {
    final outer = await _image(challenge.outer);
    final inner = await _image(challenge.inner);
    final request =
        http.Request(
            'POST',
            Uri.https('www.sadcaptcha.com', '/api/v1/rotate', {
              'licenseKey': key,
            }),
          )
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'outerImageB64': outer, 'innerImageB64': inner});
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'SadCaptcha trả lỗi HTTP ${response.statusCode}. Hãy kiểm tra API key và số dư.',
      );
    }
    final body = jsonDecode(response.body);
    final value = body is Map ? body['angle'] : null;
    if (value is! num || !value.isFinite || value < 0 || value > 360) {
      throw StateError('SadCaptcha trả góc xoay không hợp lệ.');
    }
    return value.toDouble();
  }

  /// With [refresh], a puzzle that is still shown after the drag is swapped
  /// for a new one (TikTok's own reload, else [refresh]) and solved again, up
  /// to [attempts] drags in total.
  Future<bool> solve({
    required String licenseKey,
    required Future<RotateCaptchaChallenge?> Function() read,
    required SignupAccessibility accessibility,
    required Future<bool> Function() isPresent,
    required Future<void> Function() guard,
    required void Function(String) onStatus,
    Future<void> Function()? refresh,
    int attempts = 3,
  }) async {
    Future<void> checkedGuard() async {
      if (_closed) throw RotateCaptchaCancelled();
      await guard();
      if (_closed) throw RotateCaptchaCancelled();
    }

    try {
      return await Future.any([
        _solveWithRetries(
          licenseKey: licenseKey,
          read: read,
          accessibility: accessibility,
          isPresent: isPresent,
          guard: checkedGuard,
          onStatus: onStatus,
          refresh: refresh,
          attempts: attempts,
        ),
        _abort.future.then<bool>((_) => throw RotateCaptchaCancelled()),
      ]);
    } finally {
      close();
    }
  }

  Future<bool> _solveWithRetries({
    required String licenseKey,
    required Future<RotateCaptchaChallenge?> Function() read,
    required SignupAccessibility accessibility,
    required Future<bool> Function() isPresent,
    required Future<void> Function() guard,
    required void Function(String) onStatus,
    required Future<void> Function()? refresh,
    required int attempts,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _solve(
          licenseKey: licenseKey,
          read: read,
          accessibility: accessibility,
          isPresent: isPresent,
          guard: guard,
          onStatus: onStatus,
        );
      } on _CaptchaNotSolved catch (failure) {
        if (refresh == null || attempt >= attempts) {
          throw StateError(failure.message);
        }
        onStatus('CAPTCHA chưa đúng; đổi mã và giải lại ($attempt/$attempts)…');
        if (!await _nextChallenge(failure.challenge, read, isPresent, guard)) {
          await refresh();
          await guard();
          if (!await _nextChallenge(
            failure.challenge,
            read,
            isPresent,
            guard,
            seconds: 8,
          )) {
            throw StateError('Không đổi được mã CAPTCHA. Hãy xử lý thủ công.');
          }
        }
        if (!await isPresent()) return true;
      } on StateError catch (error) {
        if (error is RotateCaptchaCancelled || attempt >= attempts) rethrow;
        onStatus('Chưa xử lý được CAPTCHA; thử lại ($attempt/$attempts)…');
        await guard();
        await _pause(1000);
      }
    }
  }

  /// Waits for a puzzle other than [failed] (TikTok reloads one after a
  /// wrong answer), or for the CAPTCHA to close.
  Future<bool> _nextChallenge(
    RotateCaptchaChallenge failed,
    Future<RotateCaptchaChallenge?> Function() read,
    Future<bool> Function() isPresent,
    Future<void> Function() guard, {
    int seconds = 3,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      await _pause(400);
      await guard();
      if (!await isPresent()) return true;
      final next = await read();
      await guard();
      if (next != null &&
          (next.outer != failed.outer || next.inner != failed.inner)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _solve({
    required String licenseKey,
    required Future<RotateCaptchaChallenge?> Function() read,
    required SignupAccessibility accessibility,
    required Future<bool> Function() isPresent,
    required Future<void> Function() guard,
    required void Function(String) onStatus,
  }) async {
    await guard();
    var challenge = await read();
    await guard();
    final loadingDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (challenge == null &&
        await isPresent() &&
        DateTime.now().isBefore(loadingDeadline)) {
      await _pause(300);
      await guard();
      challenge = await read();
      await guard();
    }
    if (challenge == null) {
      if (await isPresent()) {
        throw StateError('Chưa đọc được CAPTCHA sau thời gian chờ.');
      }
      return false;
    }
    onStatus('Đang lấy góc xoay CAPTCHA từ SadCaptcha…');
    final before = await accessibility.snapshot();
    await guard();
    final solution = await angle(challenge, licenseKey);
    await guard();
    // A person looks at the puzzle before dragging. The puzzle is re-read
    // after the pause, so a change meanwhile still stops the drag.
    await _pause(800 + _random.nextInt(1201));
    await guard();
    final current = await read();
    final snapshot = await accessibility.snapshot();
    await guard();
    if (current == null ||
        !challenge.sameAs(current) ||
        !before.ready ||
        !snapshot.ready ||
        !snapshot.viewport.bounds.isFinite ||
        snapshot.viewport.bounds.isEmpty ||
        before.viewport.bounds != snapshot.viewport.bounds) {
      throw _CaptchaNotSolved(
        challenge,
        'CAPTCHA hoặc khung WebView đã thay đổi; đã dừng kéo.',
      );
    }
    final bounds = snapshot.viewport.bounds;
    final from = current.screenPoint(bounds, 0),
        to = current.screenPoint(bounds, solution);
    debugPrint(
      '[Diag captcha] angle=$solution travel=${current.travel} '
      'viewport=${current.viewportWidth}x${current.viewportHeight} '
      'handle=(${current.x}, ${current.y}) webView=$bounds from=$from to=$to',
    );
    onStatus('Đang kéo CAPTCHA bằng Trợ năng…');
    await guard();
    await accessibility.dragScreen(bounds, from, to);
    await guard();
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var absent = 0;
    while (DateTime.now().isBefore(deadline)) {
      await _pause(400);
      await guard();
      final present = await isPresent();
      await guard();
      absent = present ? 0 : absent + 1;
      if (absent >= 2) return true;
    }
    throw _CaptchaNotSolved(
      current,
      'Chưa xác nhận được kết quả CAPTCHA. Hãy kiểm tra màn hiện tại.',
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _pauseTimer?.cancel();
    final pause = _pauseCompleter;
    if (pause != null && !pause.isCompleted) pause.complete();
    _abort.complete();
    _client.close();
  }
}

/// The puzzle is still shown (or was replaced) after an attempt.
class _CaptchaNotSolved implements Exception {
  const _CaptchaNotSolved(this.challenge, this.message);
  final RotateCaptchaChallenge challenge;
  final String message;
}

class RotateCaptchaCancelled extends StateError {
  RotateCaptchaCancelled() : super('Đã dừng xử lý CAPTCHA.');
}
