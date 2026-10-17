import 'dart:async';
import 'dart:math';

import 'app_configuration.dart';
import 'login_coordinate_profile.dart';
import 'signup_accessibility.dart';

/// All screen reading and input use the bundled Accessibility service.
/// WebView is consulted only to verify the origin, never to inspect/mutate DOM.
class LoginAccessibilityRunner {
  LoginAccessibilityRunner({
    required this.accessibility,
    required this.configuration,
    required this.isActive,
    required this.isTikTok,
    required this.isPageReady,
    required this.getOtp,
    required this.onStatus,
    required this.profile,
    this.cancelOtpRequest,
    DateTime Function()? now,
    Random? random,
  }) : now = now ?? DateTime.now,
       _random = random ?? Random();

  final SignupAccessibility accessibility;
  final LoginCoordinateProfile profile;
  final AppConfiguration configuration;
  final bool Function() isActive, isPageReady;
  final Future<bool> Function() isTikTok;
  final Future<String> Function() getOtp;
  final void Function()? cancelOtpRequest;
  final void Function(String) onStatus;
  final DateTime Function() now;
  final Random _random;
  final Set<String> _actions = {};
  bool _cancelled = false;
  bool alreadyLoggedIn = false;

  void cancel() {
    _cancelled = true;
    unawaited(accessibility.cancelPaste().catchError((_) {}));
  }

  Future<void> _guard() async {
    if (_cancelled || !isActive()) throw const LoginAccessibilityCancelled();
    if (!await isTikTok()) {
      throw StateError(
        'Đã dừng tự đăng nhập vì trang hiện tại không phải TikTok.',
      );
    }
    if (_cancelled || !isActive()) throw const LoginAccessibilityCancelled();
  }

  Future<void> _pause(int milliseconds) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    await _guard();
  }

  static RegExp _exact(String value) =>
      RegExp('^(?:$value)\$', caseSensitive: false);

  static bool _matches(SignupNode node, RegExp pattern) => [
    node.text,
    node.description,
    node.hint,
    node.label,
  ].any((value) => pattern.hasMatch(value.trim()));

  SignupNode? _find(
    SignupSnapshot snapshot,
    RegExp pattern, {
    bool requireClickable = false,
    String? action,
  }) {
    final matches = snapshot.nodes
        .where(
          (node) =>
              node.enabled &&
              (!requireClickable || node.clickable) &&
              !node.editable &&
              _matches(node, pattern) &&
              node.bounds.width > 0 &&
              node.bounds.height > 0 &&
              snapshot.viewport.bounds.contains(node.bounds.center),
        )
        .toList();
    // Prefer actionable nodes over their text children or large containers.
    matches.sort((a, b) {
      final recorded = action == null ? null : profile.point(action);
      if (recorded != null) {
        final physical = snapshot.viewport.toScreen(recorded);
        final aMatches = a.bounds.contains(physical),
            bMatches = b.bounds.contains(physical);
        if (aMatches != bMatches) return aMatches ? -1 : 1;
      }
      if (a.clickable != b.clickable) return a.clickable ? -1 : 1;
      return (a.bounds.width * a.bounds.height).compareTo(
        b.bounds.width * b.bounds.height,
      );
    });
    return matches.firstOrNull;
  }

  bool _has(SignupSnapshot snapshot, RegExp pattern) =>
      snapshot.nodes.any((node) => _matches(node, pattern));

  static final _identity = _exact(
    "verify (it['’]s|it is) really you|verify (your )?identity|xác minh (danh tính|đó thực sự là bạn)",
  );
  static final _codeTitle = _exact(
    'verify (your )?email|email verification|enter (the |your )?(verification |6[- ]digit )?code|nhập mã( xác minh)?|xác minh email',
  );
  static final _sendCode = _exact(
    'send( verification)? code|gửi mã( xác minh)?',
  );
  static final _continue = _exact(
    'log in|login|continue|next|verify|confirm|đăng nhập|tiếp tục|tiếp theo|xác nhận',
  );
  static final _login = _exact('log in|login|đăng nhập');
  static final _emailHint = RegExp(
    'email|e-mail|username|tên người dùng',
    caseSensitive: false,
  );
  static final _otpHint = RegExp('code|otp|mã', caseSensitive: false);
  static final _delivery = RegExp(
    r'^(resend|send again|gửi lại|\d+\s*s)',
    caseSensitive: false,
  );
  static final _resend = _exact(
    'resend( code)?|send( code)? again|gửi lại( mã)?',
  );

  bool _authenticated(SignupSnapshot snapshot) =>
      _has(snapshot, _exact('messages|tin nhắn')) &&
      _has(snapshot, _exact('profile|hồ sơ')) &&
      snapshot.editors.every(
        (n) =>
            RegExp(r'^search|^tìm kiếm', caseSensitive: false).hasMatch(n.hint),
      ) &&
      !_has(
        snapshot,
        _exact(
          'log in( to tiktok)?|login|đăng nhập( tiktok)?|sign up for tiktok|đăng ký tiktok',
        ),
      ) &&
      !_has(snapshot, _identity) &&
      !_has(snapshot, _codeTitle);

  Future<SignupSnapshot> _snapshot() async {
    await _guard();
    final snapshot = await accessibility.snapshot();
    await _guard();
    // Only the foreground web dialog may supply controls. Home remains
    // exposed behind TikTok modals in Chromium's Accessibility tree.
    final dialogs = snapshot.nodes.where(
      (n) => n.className == 'android.app.AlertDialog',
    );
    if (dialogs.isNotEmpty) {
      final id = dialogs.last.id;
      snapshot.nodes.removeWhere((n) => n.id != id && !n.id.startsWith('$id.'));
    }
    if (_has(
      snapshot,
      RegExp(
        'maximum number of attempts|too many (attempts|requests)',
        caseSensitive: false,
      ),
    )) {
      throw const LoginAccessibilityRateLimited();
    }
    if (_has(
      snapshot,
      RegExp(
        'captcha|drag.*slider|puzzle|verify to continue|kéo.*thanh trượt',
        caseSensitive: false,
      ),
    )) {
      throw StateError(
        'TikTok yêu cầu CAPTCHA. Hãy hoàn tất trên trang đăng nhập.',
      );
    }
    if (_has(
      snapshot,
      RegExp(
        'incorrect password|wrong password|invalid password|username or password doesn.t match|expired or incorrect|incorrect verification code|account doesn.t exist|couldn.t find.*account|sai mật khẩu|mã.*không chính xác',
        caseSensitive: false,
      ),
    )) {
      throw StateError(
        'TikTok báo lỗi tài khoản, mật khẩu hoặc OTP. Hãy kiểm tra biểu mẫu.',
      );
    }
    return snapshot;
  }

  Future<void> _tap(
    String action,
    SignupSnapshot snapshot,
    SignupNode node, {
    bool fast = false,
  }) async {
    await _guard();
    if (!_actions.add(action)) {
      throw StateError('Bước $action đã thực hiện; đã dừng để tránh gửi lại.');
    }
    final point = await profile.target(action, snapshot.viewport, node);
    await _guard();
    await accessibility.tap(snapshot.viewport, point);
    await _pause(fast ? 250 : 2000 + _random.nextInt(5001));
  }

  Future<void> _fill(
    String field,
    String value,
    SignupSnapshot snapshot,
    SignupNode editor,
  ) async {
    // Native paste also checks existing content without exposing field values.
    if (editor.length > 0) {
      throw StateError(
        'Biểu mẫu đã có thông tin. Đã dừng để giữ nội dung của bạn.',
      );
    }
    // On short (16:9) screens an open keyboard covers the lower half of the
    // WebView and Chromium drops the controls under it, including the field
    // just focused. Paste needs no keyboard, so keep it hidden throughout.
    await _setKeyboardSuppressed(true);
    try {
      await _tap('focus-$field', snapshot, editor, fast: field == 'otp');
      final focused = await _snapshot();
      if (!focused.editors.any(
        (node) =>
            node.focused &&
            node.password == (field == 'password') &&
            (field != 'email' || _emailHint.hasMatch(node.hint)),
      )) {
        throw StateError('Ô $field chưa nhận focus qua Accessibility.');
      }
      await _setKeyboardSuppressed(true); // Renew the native 10s lease.
      await _guard();
      final result = await accessibility.paste(value, field);
      await _guard();
      if (result['ok'] != true) {
        throw StateError(
          'Accessibility chưa dán được $field (${result['reason'] ?? 'unknown'}).',
        );
      }
      _actions.add('filled-$field');
      // Blur while suppressed so restoring the policy does not reopen it.
      await accessibility.dismissKeyboard();
    } finally {
      await accessibility.setKeyboardSuppressed(false);
    }
    await _hideKeyboard();
    await _pause(field == 'otp' ? 250 : 2000 + _random.nextInt(5001));
  }

  Future<void> _setKeyboardSuppressed(bool suppressed) async {
    await _guard();
    await accessibility.setKeyboardSuppressed(suppressed);
  }

  /// Safety net if the keyboard still opened: controls under it vanish from
  /// the Accessibility tree on short screens.
  Future<void> _hideKeyboard() async {
    final deadline = now().add(const Duration(seconds: 5));
    while ((await _snapshot()).keyboardVisible) {
      if (!now().isBefore(deadline)) {
        throw StateError('Không đóng được bàn phím sau khi dán.');
      }
      await accessibility.dismissKeyboard();
      await _pause(300);
    }
  }

  Future<String> _readOtp() async {
    final deadline = now().add(
      Duration(seconds: (configuration.otpApi?.waitSeconds ?? 180) + 15),
    );
    var finished = false;
    String? code;
    Object? failure;
    // Attach both handlers immediately, including when the screen interrupts
    // the request. The controller cancels its mailbox request on exit.
    final pending = getOtp().then<void>(
      (value) {
        code = value;
        finished = true;
      },
      onError: (Object error) {
        failure = error;
        finished = true;
      },
    );
    while (!finished) {
      await _pause(250);
      await _snapshot();
      if (!finished && !now().isBefore(deadline)) {
        throw LoginOtpTimeout();
      }
    }
    await pending;
    await _guard();
    if (failure != null) throw failure!;
    return code!;
  }

  Future<void> _resendOtpOnce() async {
    if (_actions.contains('resend-code')) {
      throw StateError(
        'Hết thời gian chờ OTP sau khi đã gửi lại 1 lần. Đã dừng, không bấm Resend code thêm.',
      );
    }
    onStatus('Hết thời gian chờ OTP. Đang chờ Resend code được bật…');
    final deadline = now().add(const Duration(seconds: 75));
    while (now().isBefore(deadline)) {
      final snapshot = await _snapshot();
      if (!snapshot.ready || !snapshot.viewport.valid || !isPageReady()) {
        await _pause(300);
        continue;
      }
      if (snapshot.editors.any(
        (n) => !n.password && _otpHint.hasMatch(n.hint) && n.length > 0,
      )) {
        throw StateError(
          'Ô OTP đã có nội dung. Đã dừng để giữ bản nháp, không gửi lại mã.',
        );
      }
      final resend = _find(
        snapshot,
        _resend,
        requireClickable: true,
        action: 'resend-code',
      );
      if (resend == null) {
        await _pause(300);
        continue;
      }
      onStatus('Đang bấm Resend code một lần bằng Accessibility…');
      await _tap('resend-code', snapshot, resend, fast: true);
      final acknowledgementDeadline = now().add(const Duration(seconds: 15));
      while (now().isBefore(acknowledgementDeadline)) {
        final next = await _snapshot();
        final disabledResend = next.nodes.any(
          (n) => !n.enabled && _delivery.hasMatch(n.label),
        );
        final countdown =
            _has(
              next,
              RegExp(
                r'^(resend|send|gửi lại).*\d|^\d+\s*s$',
                caseSensitive: false,
              ),
            ) ||
            (_has(next, _exact(r'\d+')) &&
                _has(next, _exact('s|seconds|giây')));
        if (next.ready && next.viewport.valid && disabledResend && countdown) {
          onStatus('Đã gửi lại mã 1 lần. Đang lấy OTP mới…');
          return;
        }
        await _pause(250);
      }
      throw StateError(
        'TikTok chưa xác nhận gửi lại mã. Đã dừng, không bấm Resend code thêm.',
      );
    }
    throw StateError(
      'Nút Resend code chưa sẵn sàng sau khi hết thời gian chờ OTP. Đã dừng.',
    );
  }

  Future<void> run() async {
    onStatus('Đang chờ trang đăng nhập sẵn sàng…');
    var deadline = now().add(const Duration(seconds: 180));
    DateTime? readySince, emailStableSince;
    Object? emailBounds;
    var otpFetched = false;
    String? otp;
    while (now().isBefore(deadline)) {
      final snapshot = await _snapshot();
      if (!isPageReady() || !snapshot.ready || !snapshot.viewport.valid) {
        readySince = null;
        await _pause(300);
        continue;
      }
      readySince ??= now();
      if (now().difference(readySince) < const Duration(seconds: 5)) {
        await _pause(300);
        continue;
      }
      if (_authenticated(snapshot)) {
        alreadyLoggedIn = !_actions.contains('submit-password') && !otpFetched;
        return;
      }

      final cookie = _find(
        snapshot,
        _exact('accept all( cookies)?|allow all( cookies)?|chấp nhận tất cả'),
      );
      if (cookie != null && !_actions.contains('accept-cookies')) {
        await _tap('accept-cookies', snapshot, cookie);
        continue;
      }

      final identity = _has(snapshot, _identity);
      final editors = snapshot.editors
          .where(
            (n) => !RegExp(
              r'^search|^tìm kiếm',
              caseSensitive: false,
            ).hasMatch(n.hint),
          )
          .toList();
      final password = editors.where((n) => n.password).firstOrNull;
      final email = editors
          .where((n) => !n.password && _emailHint.hasMatch(n.hint))
          .firstOrNull;
      final switchEmail = _find(
        snapshot,
        _exact(
          'use (email|username)|email / username|username or email|email or username|sử dụng email|tên người dùng hoặc email',
        ),
      );
      if (!identity &&
          password == null &&
          switchEmail != null &&
          !_actions.contains('use-email') &&
          !_actions.contains('submit-password')) {
        await _tap('use-email', snapshot, switchEmail);
        continue;
      }
      final otpEditors = editors
          .where((n) => !n.password && _otpHint.hasMatch(n.hint))
          .toList();
      final codeScreen =
          _has(snapshot, _codeTitle) ||
          otpEditors.isNotEmpty ||
          (_actions.contains('select-verification-email') &&
              (_has(snapshot, _sendCode) || _has(snapshot, _delivery))) ||
          (editors.length == 6 && password == null && email == null);

      if (identity && !codeScreen) {
        final method = _find(
          snapshot,
          RegExp(r'^e-?mail(?:\s+.*)?$', caseSensitive: false),
        );
        if (method != null && !_actions.contains('select-verification-email')) {
          if (emailBounds != method.bounds) {
            emailBounds = method.bounds;
            emailStableSince = now();
          }
          onStatus('Đang chờ 5 giây trước khi chọn Email xác minh…');
          if (now().difference(emailStableSince!) >=
              const Duration(seconds: 5)) {
            await _tap(
              'select-verification-email',
              snapshot,
              method,
              fast: true,
            );
            deadline = now().add(const Duration(seconds: 45));
          }
        } else if (method == null) {
          emailStableSince = null;
          emailBounds = null;
        }
      } else if (codeScreen) {
        final send = _find(snapshot, _sendCode, requireClickable: true);
        final otpVisible =
            otpEditors.isNotEmpty ||
            (password == null && email == null && editors.isNotEmpty);
        final acknowledged =
            (otpVisible && !_has(snapshot, _sendCode)) ||
            _has(snapshot, _delivery);
        if (send != null &&
            !acknowledged &&
            !_actions.contains('send-code') &&
            !otpFetched) {
          onStatus('Đang gửi mã xác minh bằng Accessibility…');
          await _tap('send-code', snapshot, send, fast: true);
          deadline = now().add(const Duration(seconds: 15));
        } else if (acknowledged) {
          // An OTP form without an active Send code, or a resend/countdown,
          // acknowledges delivery. Never fetch from API just for a gesture.
          if (!otpFetched) {
            onStatus('Đang lấy OTP đăng nhập…');
            try {
              otp = await _readOtp();
            } on LoginOtpTimeout {
              cancelOtpRequest?.call();
              await _resendOtpOnce();
              deadline = now().add(const Duration(seconds: 45));
              continue;
            }
            await _guard();
            if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
              throw StateError('OTP không đủ 6 số.');
            }
            otpFetched = true;
            deadline = now().add(const Duration(seconds: 45));
            continue; // Read fresh nodes after the API wait.
          }
          if (!_actions.contains('filled-otp')) {
            final editor =
                otpEditors.firstOrNull ??
                editors.where((n) => !n.password).firstOrNull;
            if (editor != null) {
              onStatus('Đang dán OTP bằng Accessibility…');
              await _fill('otp', otp!, snapshot, editor);
              deadline = now().add(const Duration(seconds: 45));
              continue;
            }
          } else if (!_actions.contains('submit-otp')) {
            if (snapshot.keyboardVisible) {
              await accessibility.dismissKeyboard();
              await _pause(250);
              continue;
            }
            final next = _find(snapshot, _continue, requireClickable: true);
            final enteredLength = editors
                .where((n) => !n.password)
                .fold<int>(0, (sum, node) => sum + node.length);
            if (next != null && enteredLength == 6) {
              await _tap('submit-otp', snapshot, next, fast: true);
              deadline = now().add(const Duration(seconds: 45));
            }
          }
        }
      } else if (!identity &&
          password != null &&
          !_actions.contains('submit-password')) {
        onStatus('Đang nhập tài khoản và mật khẩu bằng Accessibility…');
        if (!_actions.contains('filled-email') && email != null) {
          await _fill(
            'email',
            configuration.loginUsername.trim(),
            snapshot,
            email,
          );
          continue;
        }
        if (!_actions.contains('filled-password')) {
          await _fill(
            'password',
            configuration.loginPassword,
            snapshot,
            password,
          );
          continue;
        }
        if (email == null ||
            email.length != configuration.loginUsername.trim().length ||
            password.length != configuration.loginPassword.length) {
          throw StateError(
            'Chưa xác nhận đủ tài khoản và mật khẩu; đã dừng trước khi gửi.',
          );
        }
        if (snapshot.keyboardVisible) {
          await accessibility.dismissKeyboard();
          await _pause(300);
          continue;
        }
        final submit = _find(snapshot, _continue, requireClickable: true);
        if (submit != null) {
          await _tap('submit-password', snapshot, submit, fast: true);
          deadline = now().add(const Duration(seconds: 45));
          onStatus('Đang chờ kết quả đăng nhập…');
        }
      } else if (!_actions.contains('submit-password') && !otpFetched) {
        final useEmail = _find(
          snapshot,
          _exact(
            'use (email|username)|email / username|username or email|email or username|sử dụng email|tên người dùng hoặc email',
          ),
        );
        final phoneEmail = _find(
          snapshot,
          _exact(
            'use phone( number)?( /| or) email|sử dụng số điện thoại hoặc email',
          ),
        );
        final login = _find(
          snapshot,
          _login,
          requireClickable: true,
          action: 'open-login',
        );
        if (useEmail != null && !_actions.contains('use-email')) {
          await _tap('use-email', snapshot, useEmail);
        } else if (phoneEmail != null && !_actions.contains('phone-email')) {
          await _tap('phone-email', snapshot, phoneEmail);
        } else if (login != null && !_actions.contains('open-login')) {
          await _tap('open-login', snapshot, login);
        }
      }
      await _pause(300);
    }
    throw StateError(
      'Chưa xác nhận được đăng nhập qua Accessibility. Hãy kiểm tra màn TikTok.',
    );
  }
}

class LoginAccessibilityCancelled implements Exception {
  const LoginAccessibilityCancelled();
}

class LoginOtpTimeout extends StateError {
  LoginOtpTimeout([super.message = 'Hết thời gian chờ OTP đăng nhập.']);
}

class LoginAccessibilityRateLimited implements Exception {
  const LoginAccessibilityRateLimited();
}
