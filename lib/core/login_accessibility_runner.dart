import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'app_configuration.dart';
import 'cookie_consent_accessibility.dart';
import 'privacy_notice_accessibility.dart';
import 'login_coordinate_profile.dart';
import 'signup_accessibility.dart';

/// All screen reading and input use the bundled Accessibility service.
/// The controller may read CAPTCHA image/slider geometry before snapshots.
/// Account form input continues to use Accessibility.
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
    this.onOtpRejected,
    this.reloadBlankPage,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    Random? random,
  }) : _delay = delay,
       now = now ?? DateTime.now,
       _random = random ?? Random();

  final SignupAccessibility accessibility;
  final LoginCoordinateProfile profile;
  final AppConfiguration configuration;
  final bool Function() isActive, isPageReady;
  final Future<bool> Function() isTikTok;
  final Future<String> Function() getOtp;
  final void Function()? cancelOtpRequest;
  final void Function(String)? onOtpRejected;

  /// Reloads a loaded TikTok document that never rendered any content.
  final Future<void> Function()? reloadBlankPage;
  final Future<void> Function(Duration)? _delay;
  final void Function(String) onStatus;
  final DateTime Function() now;
  final Random _random;
  final Set<String> _actions = {};
  bool _cancelled = false;
  bool _recoveringOtp = false;
  DateTime? otpRequestedAt;
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
    _renewKeyboard();
    final duration = Duration(milliseconds: milliseconds);
    await (_delay?.call(duration) ?? Future<void>.delayed(duration));
    await _guard();
  }

  // Gecko ignores ACTION_CLEAR_FOCUS, so a pasted field keeps focus and the
  // IME reopens as soon as suppression ends, covering Continue. The run
  // keeps the keyboard hidden throughout, renewing the native 10s lease.
  bool _holdingKeyboard = false;
  DateTime? _keyboardRenewedAt;

  /// Fire and forget; filling a field still awaits its own suppression.
  void _renewKeyboard({bool force = false}) {
    final at = _keyboardRenewedAt;
    if (!_holdingKeyboard ||
        (!force &&
            at != null &&
            now().difference(at) < const Duration(seconds: 4))) {
      return;
    }
    _keyboardRenewedAt = now();
    unawaited(
      accessibility.renewKeyboardSuppression().catchError((Object _) {
        // No WebView root during a reload (or no service): retry next time.
        _keyboardRenewedAt = null;
      }),
    );
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
    SignupNode? afterEditor,
  }) {
    final dialog = snapshot.nodes
        .where((n) => n.className.endsWith('Dialog'))
        .lastOrNull;
    bool inDialog(SignupNode node) =>
        dialog != null &&
        (node.id.startsWith('${dialog.id}.') ||
            dialog.bounds.contains(node.bounds.center));
    final matches = snapshot.nodes
        .where(
          (node) =>
              node.enabled &&
              (!requireClickable || node.clickable) &&
              !node.editable &&
              // The modal is titled "Log in" and is clickable, but tapping it
              // presses nothing; a point once recorded on it kept winning.
              !node.className.endsWith('Dialog') &&
              // Desktop exposes the "Log in" heading as a clickable View.
              // A form submit must follow its editor in the same dialog,
              // even when a saved point happens to land on that heading.
              (afterEditor == null ||
                  (node.bounds.top >= afterEditor.bounds.bottom &&
                      (dialog == null || inDialog(node)))) &&
              _matches(node, pattern) &&
              node.bounds.width > 0 &&
              node.bounds.height > 0 &&
              snapshot.viewport.bounds.contains(node.bounds.center),
        )
        .toList();
    // Chromium reports TikTok's web modal as android.app.Dialog while the
    // page behind it stays in the tree; its sidebar "Log in" icon also
    // matches Continue patterns and is smaller than the modal's button.
    // Prefer actionable nodes over their text children or large containers.
    matches.sort((a, b) {
      if (inDialog(a) != inDialog(b)) return inDialog(a) ? -1 : 1;
      final recorded = action == null
          ? null
          : profile.point(action, desktop: snapshot.viewport.landscape);
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

  /// The switch from the phone form; desktop TikTok labels it "Use email or
  /// username".
  @visibleForTesting
  static final useEmailLabel = _exact(
    'use (email|username)( or (email|username))?|email / username|username or email|email or username|sử dụng email|tên người dùng hoặc email',
  );
  static const _maxOpenLoginTaps = 3;
  static const _openLoginRetryAfter = Duration(seconds: 10);
  static const _focusWait = Duration(seconds: 2);
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
      // Signed-in search fields can show a trending topic as their hint;
      // comments can also remain editable. Authentication depends on the
      // signed-in UI and absence of account/verification dialogs below.
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
    _renewKeyboard();
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
    if (!_recoveringOtp &&
        _has(
          snapshot,
          RegExp(
            r'verification code.*(?:expired|incorrect)|expired or incorrect|incorrect verification code|invalid verification code|mã.*(?:hết hạn|không chính xác)',
            caseSensitive: false,
          ),
        )) {
      throw LoginOtpRejected();
    }
    if (_has(
      snapshot,
      RegExp(
        'incorrect password|wrong password|invalid password|username or password doesn.t match|account doesn.t exist|couldn.t find.*account|sai mật khẩu',
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
    debugPrint(
      '[Diag tap] $action node="${node.label}|${node.text}" '
      'class=${node.className} bounds=${node.bounds} point=$point '
      'viewport=${snapshot.viewport.bounds} dialogs=${snapshot.nodes.where((n) => n.className.endsWith('Dialog')).map((n) => n.className).toSet()}',
    );
    await _guard();
    if (action == 'select-verification-email' ||
        action == 'send-code' ||
        action == 'resend-code') {
      otpRequestedAt = now();
    }
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
      // Chromium reports focus to Accessibility asynchronously; on large,
      // dense screens it can trail the tap by more than the OTP pause.
      final focusDeadline = now().add(_focusWait);
      while (!(await _snapshot()).editors.any(
        (node) =>
            node.focused &&
            node.password == (field == 'password') &&
            (field != 'email' || _emailHint.hasMatch(node.hint)),
      )) {
        if (!now().isBefore(focusDeadline)) {
          throw StateError('Ô $field chưa nhận focus qua Accessibility.');
        }
        await _pause(250);
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
      if (!_holdingKeyboard) await accessibility.setKeyboardSuppressed(false);
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
    onStatus('Đang chờ Resend code được bật để gửi lại mã một lần…');
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
    _holdingKeyboard = true;
    _renewKeyboard(force: true);
    try {
      await _run();
    } finally {
      _holdingKeyboard = false;
      _keyboardRenewedAt = null;
      unawaited(
        accessibility.releaseKeyboardSuppression().catchError((Object _) {}),
      );
    }
  }

  Future<void> _run() async {
    onStatus('Đang chờ trang đăng nhập sẵn sàng…');
    var deadline = now().add(const Duration(seconds: 180));
    DateTime? readySince, emailStableSince, blankSince, reloadedAt;
    Object? emailBounds;
    var otpFetched = false;
    var loginTaps = 0, blankReloads = 0;
    DateTime? loginTappedAt;
    String? otp;
    while (now().isBefore(deadline)) {
      try {
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
        // A loaded document can stay blank (seen through a slow proxy): the
        // tree holds only the WebView. Reload it, at most twice.
        if ([
          ...snapshot.nodes,
          ...snapshot.hiddenNodes,
        ].every((n) => n.label.isEmpty && !n.clickable && !n.editable)) {
          blankSince ??= now();
          if (reloadBlankPage != null &&
              blankReloads < 2 &&
              now().difference(blankSince) >= const Duration(seconds: 30)) {
            blankReloads++;
            onStatus('Trang TikTok trống; đang tải lại ($blankReloads/2)…');
            await _guard();
            reloadedAt = now();
            await reloadBlankPage!();
            blankSince = null;
            readySince = null;
            final extended = now().add(const Duration(seconds: 90));
            if (deadline.isBefore(extended)) deadline = extended;
          }
          await _pause(300);
          continue;
        }
        blankSince = null;
        if (_authenticated(snapshot)) {
          alreadyLoggedIn =
              !_actions.contains('submit-password') && !otpFetched;
          return;
        }

        final cookie = CookieConsentAccessibility.button(snapshot);
        if (cookie != null && !_actions.contains('accept-cookies')) {
          await _tap('accept-cookies', snapshot, cookie);
          continue;
        }
        // The privacy notice hides the logged-in page behind it.
        final privacy = PrivacyNoticeAccessibility.button(snapshot);
        if (privacy != null && !_actions.contains('dismiss-privacy')) {
          await _tap('dismiss-privacy', snapshot, privacy);
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
        final switchEmail = _find(snapshot, useEmailLabel);
        // The phone form keeps a hidden, unlabelled password editor; only an
        // email/username editor shows the switch has happened.
        if (!identity &&
            email == null &&
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
          if (method != null &&
              !_actions.contains('select-verification-email')) {
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
                _recoveringOtp = false;
                deadline = now().add(const Duration(seconds: 45));
                continue;
              }
            } else if (!_actions.contains('submit-otp')) {
              if (snapshot.keyboardVisible) {
                await accessibility.dismissKeyboard();
                await _pause(250);
                continue;
              }
              final next = _find(
                snapshot,
                _continue,
                requireClickable: true,
                action: 'submit-otp',
              );
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
          final submit = _find(
            snapshot,
            _continue,
            requireClickable: true,
            action: 'submit-password',
            afterEditor: password,
          );
          if (submit != null) {
            await _tap('submit-password', snapshot, submit, fast: true);
            deadline = now().add(const Duration(seconds: 45));
            onStatus('Đang chờ kết quả đăng nhập…');
          }
        } else if (!_actions.contains('submit-password') && !otpFetched) {
          final useEmail = _find(snapshot, useEmailLabel);
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
          } else if (login != null &&
              loginTaps < _maxOpenLoginTaps &&
              (loginTappedAt == null ||
                  now().difference(loginTappedAt) >= _openLoginRetryAfter)) {
            // TikTok can drop a tap while the page still hydrates. Opening the
            // login dialog submits nothing, so a bounded retry is safe.
            _actions.remove('open-login');
            loginTaps++;
            loginTappedAt = now();
            await _tap('open-login', snapshot, login);
          }
        }
        await _pause(300);
      } on LoginOtpRejected {
        if (!otpFetched ||
            otp == null ||
            !_actions.contains('filled-otp') ||
            _actions.contains('resend-code')) {
          rethrow;
        }
        onStatus('OTP sai hoặc hết hạn. Đang chuẩn bị gửi lại mã một lần…');
        onOtpRejected?.call(otp);
        _recoveringOtp = true;
        try {
          if (!await accessibility.clearOtp(otp)) {
            throw StateError(
              'Ô OTP đã thay đổi. Đã giữ nội dung, không gửi lại mã.',
            );
          }
          await accessibility.dismissKeyboard();
          cancelOtpRequest?.call();
          await _resendOtpOnce();
        } catch (_) {
          _recoveringOtp = false;
          rethrow;
        }
        _actions.removeAll(['focus-otp', 'filled-otp', 'submit-otp']);
        otpFetched = false;
        otp = null;
        deadline = now().add(const Duration(seconds: 45));
      } on PlatformException {
        // The reloading document briefly refuses URL and tree reads.
        if (reloadedAt == null ||
            now().difference(reloadedAt) > const Duration(seconds: 30)) {
          rethrow;
        }
        await _pause(500);
      }
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

class LoginOtpRejected extends StateError {
  LoginOtpRejected()
    : super('OTP không hợp lệ. Đã dừng, không gửi lại mã quá một lần.');
}

class LoginAccessibilityRateLimited implements Exception {
  const LoginAccessibilityRateLimited();
}
