import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'auto_login_script.dart';
import 'auto_signup_script.dart';
import 'auto_watch_script.dart';
import 'app_configuration.dart';
import 'otp_api.dart';

const String tiktokHomeUrl = 'https://www.tiktok.com/';
const String tiktokProfileUrl = 'https://www.tiktok.com/profile';
const String tiktokLoginUrl =
    'https://www.tiktok.com/login/phone-or-email/email';
const String tiktokSignupUrl =
    'https://www.tiktok.com/signup/phone-or-email/email';

enum TikTokLaunchAction { browse, login, signup }

class TikTokPage extends StatefulWidget {
  const TikTokPage(
      {super.key,
      required this.configuration,
      this.launchAction = TikTokLaunchAction.browse,
      this.otpReaderFactory});

  final AppConfiguration configuration;
  final TikTokLaunchAction launchAction;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;

  String get initialUrl => switch (launchAction) {
        TikTokLaunchAction.browse => tiktokHomeUrl,
        TikTokLaunchAction.login => tiktokLoginUrl,
        TikTokLaunchAction.signup => tiktokSignupUrl,
      };

  @override
  State<TikTokPage> createState() => _TikTokPageState();
}

class _TikTokPageState extends State<TikTokPage> with WidgetsBindingObserver {
  static const _commentInputChannel =
      MethodChannel('test_tiktok/comment_input');
  InAppWebViewController? _webViewController;
  bool _initialActionStarted = false;
  bool _initialPageLoaded = false;
  bool _autoLoginBusy = false;
  int _autoLoginAttempt = 0;
  bool _autoSignupBusy = false;
  int _autoSignupAttempt = 0;
  String _activeLoginOtp = '';
  String _activeSignupOtp = '';
  OtpCodeRequest? _loginOtpRequest;
  OtpCodeRequest? _signupOtpRequest;

  int _loadingProgress = 0;

  String? _pageError;
  bool _autoWatchEnabled = false;
  bool _autoWatchBusy = false;
  bool _appActive = true;
  late final List<String> _comments;
  bool _pasteBusy = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.configuration.comments;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _cancelAutoLogin(updateUi: false);
    _cancelAutoSignup(updateUi: false);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopAutoWatch());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive && _autoLoginBusy) _cancelAutoLogin();
    if (!_appActive && _autoSignupBusy) _cancelAutoSignup();
    if (_appActive) unawaited(_runInitialAction());
    if (_autoWatchEnabled && _appActive) {
      unawaited(_startAutoWatch());
    } else {
      unawaited(_stopAutoWatch());
    }
  }

  Future<void> _startAutoWatch() async {
    if (!mounted || !_autoWatchEnabled || !_appActive) return;
    try {
      final result = await _webViewController?.evaluateJavascript(
        source: buildAutoWatchScript(_comments),
      );
      if (result != true) throw StateError('Video watcher did not start');
      // The app may have been paused or the toggle disabled during injection.
      if (!mounted || !_autoWatchEnabled || !_appActive) {
        await _stopAutoWatch();
      }
    } catch (_) {
      if (!mounted || !_autoWatchEnabled) return;
      setState(() => _autoWatchEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể bật tự động xem. Hãy thử tải lại TikTok.'),
        ),
      );
    }
  }

  Future<void> _stopAutoWatch() async {
    try {
      await _webViewController?.evaluateJavascript(source: autoWatchStopScript);
    } catch (_) {
      // Navigation/disposal may already have destroyed the old page.
    }
  }

  Future<bool> _pasteCommentFromClipboard(List<dynamic> args) async {
    if (!mounted ||
        !_autoWatchEnabled ||
        !_appActive ||
        _pasteBusy ||
        args.length != 1 ||
        args.first is! String) {
      return false;
    }
    final text = args.first as String;
    if (!_comments.contains(text)) return false;
    _pasteBusy = true;
    try {
      final url = await _webViewController?.getUrl();
      if (url == null ||
          url.scheme != 'https' ||
          !(url.host == 'tiktok.com' || url.host.endsWith('.tiktok.com'))) {
        return false;
      }
      final source =
          'window.__flutterAutoWatch?.canPasteComment(${jsonEncode(text)}) === true;';
      if (await _webViewController?.evaluateJavascript(source: source) !=
          true) {
        return false;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted ||
          !_autoWatchEnabled ||
          !_appActive ||
          await _webViewController?.evaluateJavascript(source: source) !=
              true) {
        return false;
      }
      for (var retry = 0; retry < 6; retry++) {
        if (!mounted ||
            !_autoWatchEnabled ||
            !_appActive ||
            await _webViewController?.evaluateJavascript(source: source) !=
                true) {
          return false;
        }
        if (await _commentInputChannel
                .invokeMethod<bool>('paste', {'context': 'comment'}) ==
            true) {
          return true;
        }
        if (retry < 5) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _pasteBusy = false;
    }
  }

  Future<void> _toggleAutoWatch() async {
    if (_autoWatchBusy ||
        _autoLoginBusy ||
        _autoSignupBusy ||
        _webViewController == null) {
      return;
    }
    if (!_autoWatchEnabled && _comments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Hãy nhập nội dung bình luận ở màn Cấu hình.'),
      ));
      return;
    }
    if (!mounted || _autoLoginBusy || _autoSignupBusy) return;
    setState(() {
      _autoWatchBusy = true;
      _autoWatchEnabled = !_autoWatchEnabled;
    });
    if (_autoWatchEnabled) {
      await _startAutoWatch();
    } else {
      await _stopAutoWatch();
    }
    if (mounted) setState(() => _autoWatchBusy = false);
  }

  Future<void> _stopAutoLogin(int attempt) async {
    try {
      await _webViewController?.evaluateJavascript(
        source: buildAutoLoginStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void _cancelAutoLogin({bool updateUi = true}) {
    _loginOtpRequest?.cancel();
    _loginOtpRequest = null;
    final attempt = _autoLoginAttempt++;
    unawaited(_stopAutoLogin(attempt));
    if (updateUi && mounted) setState(() => _autoLoginBusy = false);
  }

  Future<void> _stopAutoSignup(int attempt) async {
    try {
      await _webViewController?.evaluateJavascript(
        source: buildAutoSignupStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void _cancelAutoSignup({bool updateUi = true}) {
    _signupOtpRequest?.cancel();
    _signupOtpRequest = null;
    final attempt = _autoSignupAttempt++;
    unawaited(_stopAutoSignup(attempt));
    if (updateUi && mounted) setState(() => _autoSignupBusy = false);
  }

  Future<bool> _pasteSignupFromClipboard(List<dynamic> args) =>
      _pasteAccountFromClipboard(args, signup: true);

  Future<bool> _pasteLoginFromClipboard(List<dynamic> args) =>
      _pasteAccountFromClipboard(args, signup: false);

  Future<bool> _pasteAccountFromClipboard(List<dynamic> args,
      {required bool signup}) async {
    final controller = _webViewController;
    final attempt = signup ? _autoSignupAttempt : _autoLoginAttempt;
    final accountContext = signup ? 'signup' : 'login';
    final stateName = signup ? '__flutterAutoSignup' : '__flutterAutoLogin';
    bool isActive() =>
        mounted &&
        _appActive &&
        (signup
            ? _autoSignupBusy && attempt == _autoSignupAttempt
            : _autoLoginBusy && attempt == _autoLoginAttempt);
    if (!isActive() ||
        _pasteBusy ||
        controller == null ||
        args.length != 2 ||
        args[0] != attempt ||
        (args[1] != 'email' && args[1] != 'password' && args[1] != 'otp')) {
      return false;
    }
    final field = args[1] as String;
    final text = switch (field) {
      'email' => (signup
              ? widget.configuration.signupEmail
              : widget.configuration.loginUsername)
          .trim(),
      'otp' => signup ? _activeSignupOtp : _activeLoginOtp,
      _ => signup
          ? widget.configuration.signupPassword
          : widget.configuration.loginPassword,
    };
    if (text.isEmpty) return false;
    final source = 'window.$stateName?.canPasteFromClipboard('
        '$attempt, ${jsonEncode(field)}, ${jsonEncode(text)}) === true;';
    _pasteBusy = true;
    try {
      debugPrint('Auto $accountContext: pasting $field from clipboard.');
      final url = await controller.getUrl();
      if (!isActive() ||
          url?.scheme != 'https' ||
          url?.host != 'www.tiktok.com' ||
          !(url?.path.startsWith('/$accountContext') ?? false) ||
          await controller.evaluateJavascript(source: source) != true) {
        return false;
      }
      if (!isActive()) return false;
      await Clipboard.setData(ClipboardData(text: text));
      // DOM focus can arrive before the native editor is ready to paste. Retry
      // only rejected native actions, checking the field and attempt each time.
      for (var retry = 0; retry < 6; retry++) {
        if (!isActive() ||
            await controller.evaluateJavascript(source: source) != true ||
            !isActive()) {
          return false;
        }
        final pasted = await _commentInputChannel.invokeMethod<bool>('paste', {
          'context': accountContext,
          'attempt': attempt,
        });
        if (pasted == true) return true;
        if (retry < 5) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      debugPrint('Auto $accountContext: native paste rejected for $field.');
      return false;
    } catch (_) {
      return false;
    } finally {
      _pasteBusy = false;
    }
  }

  bool _validateOtpMailbox({required bool signup}) {
    final configuration = widget.configuration;
    final otp = signup ? configuration.signupOtp : configuration.loginOtp;
    if (configuration.otpApi == null || otp.trim().isNotEmpty) return true;
    final email =
        signup ? configuration.signupEmail : configuration.loginUsername;
    final password = signup
        ? configuration.signupMailboxPassword
        : configuration.loginMailboxPassword;
    if (OtpApiConfiguration.isEmail(email) && password.isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text('Hãy nhập email và mật khẩu hộp thư lấy OTP ở màn Cấu hình.'),
    ));
    return false;
  }

  OtpCodeRequest _requestOtp({required bool signup}) {
    final configuration = widget.configuration;
    final api = configuration.otpApi!;
    final reader = widget.otpReaderFactory?.call(api) ?? OtpApiClient(api);
    return OtpCodeRequest.start(
      reader,
      email: signup ? configuration.signupEmail : configuration.loginUsername,
      password: signup
          ? configuration.signupMailboxPassword
          : configuration.loginMailboxPassword,
    );
  }

  Future<void> _autoSignup() async {
    if (_autoSignupBusy) {
      _cancelAutoSignup();
      return;
    }
    final controller = _webViewController;
    if (controller == null || _autoWatchBusy || _autoLoginBusy || !_appActive) {
      return;
    }
    if (widget.configuration.signupEmail.trim().isEmpty ||
        widget.configuration.signupPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Hãy nhập email và mật khẩu đăng ký ở màn Cấu hình.'),
      ));
      return;
    }
    if (!_validateOtpMailbox(signup: true)) return;
    _activeSignupOtp = widget.configuration.signupOtp.trim();
    final attempt = ++_autoSignupAttempt;
    setState(() {
      _autoSignupBusy = true;
      _autoWatchEnabled = false;
    });
    bool isActive() =>
        mounted &&
        _appActive &&
        _autoSignupBusy &&
        attempt == _autoSignupAttempt;
    String? message;
    var submitted = false;
    var otpSubmitted = false;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    try {
      await _stopAutoWatch();
      if (!mounted || !isActive()) return;
      final birthday = widget.configuration.birthday ??
          AppConfiguration.randomSignupBirthday();
      message = 'Không thể mở trang đăng ký. Hãy thử tải lại TikTok.';
      var deadline = DateTime.now().add(const Duration(seconds: 120));
      var evaluationFailures = 0;
      String? lastStep;
      message = 'Chưa hoàn tất đăng ký. Hãy kiểm tra biểu mẫu trên TikTok; '
          'bạn có thể chọn ngày sinh hoặc tiếp tục thủ công.';
      while (isActive() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!isActive()) return;
        if (otpRequest?.error != null) {
          message = otpRequest!.error;
          break;
        }
        if (_activeSignupOtp.isEmpty && otpRequest?.code != null) {
          setState(() => _activeSignupOtp = otpRequest!.code!);
        }
        dynamic result;
        try {
          final url = await controller.getUrl();
          if (!isActive()) return;
          if (url?.scheme != 'https' || url?.host != 'www.tiktok.com') {
            message = 'Đã dừng đăng ký vì trang hiện tại không phải TikTok.';
            break;
          }
          result = await controller.evaluateJavascript(
            source: buildAutoSignupScript(
              email: widget.configuration.signupEmail.trim(),
              password: widget.configuration.signupPassword,
              birthday: birthday,
              attempt: attempt,
              allowSubmit: !submitted,
              otp: _activeSignupOtp,
              otpRequestedAt: otpRequestedAt,
              allowOtpSubmit: !otpSubmitted,
              waitForOtpApi: widget.configuration.otpApi != null &&
                  _activeSignupOtp.isEmpty,
            ),
          );
          evaluationFailures = 0;
        } catch (error) {
          debugPrint('Auto signup: evaluation failed (${error.runtimeType}).');
          if (++evaluationFailures >= 5) {
            message = 'Không thể chạy thao tác trên biểu mẫu đăng ký. '
                'Hãy dừng app rồi chạy lại, tránh hot restart WebView.';
            break;
          }
          continue;
        }
        if (!isActive()) return;
        if ((result == 'verification-requested' || result == 'otp-required') &&
            _activeSignupOtp.isEmpty &&
            widget.configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          otpRequest = _requestOtp(signup: true);
          setState(() => _signupOtpRequest = otpRequest);
          deadline = DateTime.now().add(
              Duration(seconds: widget.configuration.otpApi!.waitSeconds + 45));
          message = 'Đã yêu cầu mã. Đang lấy OTP đăng ký từ API…';
          continue;
        }
        if (result is String && result != lastStep) {
          debugPrint('Auto signup: $result.');
          lastStep = result;
        }
        if (result == 'submitted' || result == 'otp-submitted') {
          submitted = true;
          if (result == 'otp-submitted') otpSubmitted = true;
          message = 'Đã gửi đăng ký nhưng chưa xác nhận được kết quả. '
              'Hãy kiểm tra trên TikTok.';
        } else if (result == 'already-logged-in' ||
            result == 'signup-success') {
          message = result == 'already-logged-in'
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng ký TikTok thành công.';
          break;
        } else if (result == 'verification-required') {
          message = 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. '
              'Hãy hoàn tất trên trang đăng ký.';
          break;
        } else if (result == 'verification-requested') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          if (_activeSignupOtp.isEmpty && otpRequest == null) {
            message = 'Đã gửi mã. Hãy nhập OTP trên trang đăng ký, '
                'hoặc điền Mã OTP đăng ký ở màn Cấu hình rồi chạy lại.';
            break;
          }
          message = 'Đã yêu cầu mã. Đang chờ 5 giây để tự nhập OTP đăng ký.';
        } else if (result == 'otp-required') {
          message = 'Đang lấy OTP đăng ký từ API…';
        } else if (result == 'waiting-otp') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          message = 'Đang chờ ô OTP đăng ký để tự nhập mã.';
        } else if (result == 'email-registered') {
          message = 'Email đăng ký đã có tài khoản TikTok. '
              'Hãy đăng nhập hoặc đổi email đăng ký ở màn Cấu hình.';
          break;
        } else if (result == 'checkbox-failed') {
          message = 'Chưa tích được ô nhận tin TikTok. '
              'Hãy tích ô này trên biểu mẫu rồi tiếp tục.';
          break;
        } else if (result == 'signup-error') {
          message =
              'TikTok báo lỗi đăng ký. Hãy kiểm tra thông tin trên trang.';
          break;
        } else if (result == 'paste-failed') {
          message = 'Không thể dán thông tin đăng ký từ clipboard. '
              'Đã dừng, bạn có thể nhập thủ công.';
          break;
        } else if (result == 'draft-exists') {
          message = 'Có thông tin đang nhập trên biểu mẫu. '
              'Đã dừng để giữ nội dung của bạn.';
          break;
        } else if (result == 'birthday-required') {
          message = 'Không thể chọn ngày sinh tự động. '
              'Hãy chọn ngày sinh và tiếp tục thủ công trên TikTok.';
          break;
        } else if (result == 'wrong-origin') {
          message = 'Đã dừng đăng ký vì trang hiện tại không phải TikTok.';
          break;
        }
      }
    } catch (_) {
      message = 'Không thể tự động đăng ký. Hãy thử lại trên TikTok.';
    } finally {
      otpRequest?.cancel();
      if (identical(_signupOtpRequest, otpRequest)) _signupOtpRequest = null;
      await _stopAutoSignup(attempt);
      if (mounted && isActive()) {
        setState(() => _autoSignupBusy = false);
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }
  }

  Future<void> _autoLogin() async {
    if (_autoLoginBusy) {
      _cancelAutoLogin();
      return;
    }
    final controller = _webViewController;
    if (controller == null ||
        _autoWatchBusy ||
        _autoSignupBusy ||
        !_appActive) {
      return;
    }
    if (widget.configuration.loginUsername.trim().isEmpty ||
        widget.configuration.loginPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Hãy nhập tài khoản và mật khẩu đăng nhập ở màn Cấu hình.')),
      );
      return;
    }
    if (!_validateOtpMailbox(signup: false)) return;
    _activeLoginOtp = widget.configuration.loginOtp.trim();
    final attempt = ++_autoLoginAttempt;
    setState(() {
      _autoLoginBusy = true;
      _autoWatchEnabled = false;
    });
    bool isActive() =>
        mounted && _appActive && _autoLoginBusy && attempt == _autoLoginAttempt;
    var submitted = false;
    var otpSubmitted = false;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    var message = 'Không thể mở trang đăng nhập. Hãy thử tải lại TikTok.';
    try {
      await _stopAutoWatch();
      if (!isActive()) return;
      var deadline = DateTime.now().add(const Duration(seconds: 45));
      message =
          'Không tìm thấy biểu mẫu đăng nhập. Bạn có thể đăng nhập thủ công.';
      while (isActive() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!isActive()) return;
        if (otpRequest?.error != null) {
          message = otpRequest!.error!;
          break;
        }
        if (_activeLoginOtp.isEmpty && otpRequest?.code != null) {
          setState(() => _activeLoginOtp = otpRequest!.code!);
        }
        // A navigation can destroy the JavaScript context between polls.
        dynamic result;
        try {
          final url = await controller.getUrl();
          if (!isActive()) return;
          if (url?.scheme != 'https' || url?.host != 'www.tiktok.com') {
            message =
                'Đã dừng tự đăng nhập vì trang hiện tại không phải TikTok.';
            break;
          }
          result = await controller.evaluateJavascript(
            source: buildAutoLoginScript(
              email: widget.configuration.loginUsername.trim(),
              password: widget.configuration.loginPassword,
              allowSubmit: !submitted,
              attempt: attempt,
              otp: _activeLoginOtp,
              otpRequestedAt: otpRequestedAt,
              allowOtpSubmit: !otpSubmitted,
              waitForOtpApi: widget.configuration.otpApi != null &&
                  _activeLoginOtp.isEmpty,
            ),
          );
        } catch (_) {
          continue;
        }
        if (!isActive()) return;
        if ((result == 'verification-requested' || result == 'otp-required') &&
            _activeLoginOtp.isEmpty &&
            widget.configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          otpRequest = _requestOtp(signup: false);
          setState(() => _loginOtpRequest = otpRequest);
          deadline = DateTime.now().add(
              Duration(seconds: widget.configuration.otpApi!.waitSeconds + 45));
          message = 'Đã yêu cầu mã. Đang lấy OTP đăng nhập từ API…';
          continue;
        }
        if (result == 'submitted' || result == 'otp-submitted') {
          submitted = true;
          if (result == 'otp-submitted') otpSubmitted = true;
          message = 'Đã gửi đăng nhập nhưng chưa xác nhận được kết quả. '
              'Hãy kiểm tra trên TikTok.';
        } else if (result == 'already-logged-in' || result == 'login-success') {
          message = result == 'already-logged-in'
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng nhập TikTok thành công.';
          break;
        } else if (result == 'verification-requested') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          if (_activeLoginOtp.isEmpty && otpRequest == null) {
            message = 'Đã gửi mã. Hãy nhập OTP trên trang đăng nhập, '
                'hoặc điền Mã OTP đăng nhập ở màn Cấu hình rồi chạy lại.';
            break;
          }
          message = 'Đã yêu cầu mã. Đang chờ 5 giây để tự nhập OTP đăng nhập.';
        } else if (result == 'otp-required') {
          message = 'Đang lấy OTP đăng nhập từ API…';
        } else if (result == 'waiting-otp') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          message = 'Đang chờ ô OTP đăng nhập để tự nhập mã.';
        } else if (result == 'draft-exists') {
          message =
              'Biểu mẫu đã có thông tin khác. Đã dừng để giữ nội dung của bạn.';
          break;
        } else if (result == 'verification-required') {
          message = 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. '
              'Hãy hoàn tất trên trang đăng nhập.';
          break;
        } else if (result == 'paste-failed') {
          message = 'Không thể dán thông tin đăng nhập từ clipboard. '
              'Đã dừng, bạn có thể nhập thủ công.';
          break;
        } else if (result == 'login-error') {
          message =
              'TikTok báo lỗi đăng nhập. Hãy kiểm tra thông tin trên trang.';
          break;
        } else if (result == 'wrong-origin') {
          message = 'Đã dừng tự đăng nhập vì trang hiện tại không phải TikTok.';
          break;
        }
      }
    } catch (_) {
      // Keep credentials and WebView exception details out of UI messages.
    } finally {
      otpRequest?.cancel();
      if (identical(_loginOtpRequest, otpRequest)) _loginOtpRequest = null;
      await _stopAutoLogin(attempt);
      if (mounted && isActive()) {
        setState(() => _autoLoginBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  void _handleAutoWatchMessage(String message) {
    if (!mounted || !_autoWatchEnabled) return;
    if (message == 'comment-sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi bình luận.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final text = switch (message) {
      'login-required' => 'Bạn cần đăng nhập TikTok để tự động bình luận.',
      'comments-unavailable' =>
        'Bài này không mở được bình luận. Đã dừng tự động.',
      'comment-draft-exists' =>
        'Có bình luận đang soạn. Đã dừng để giữ nội dung của bạn.',
      'comment-post-changed' =>
        'Video đã thay đổi khi đang bình luận. Đã dừng tự động.',
      'comment-paste-failed' =>
        'Không thể dán bình luận từ clipboard. Đã dừng tự động.',
      _ =>
        'Chưa xác nhận được bình luận đã gửi. Đã dừng, không gửi lại để tránh trùng.',
    };
    setState(() => _autoWatchEnabled = false);
    unawaited(_stopAutoWatch());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _runInitialAction() async {
    if (!mounted ||
        !_appActive ||
        !_initialPageLoaded ||
        _initialActionStarted ||
        _webViewController == null) {
      return;
    }
    // Latch before starting: reloads, SPA navigations and resume cannot submit again.
    _initialActionStarted = true;
    switch (widget.launchAction) {
      case TikTokLaunchAction.browse:
        return;
      case TikTokLaunchAction.login:
        await _autoLogin();
      case TikTokLaunchAction.signup:
        await _autoSignup();
    }
  }

  void _cancelAutoActions() {
    _initialActionStarted = true;
    if (_autoLoginBusy) _cancelAutoLogin();
    if (_autoSignupBusy) _cancelAutoSignup();
  }

  Future<void> _handlePageLoadComplete(WebUri? url) async {
    if (!mounted) return;
    _initialPageLoaded =
        url?.scheme == 'https' && url?.host == 'www.tiktok.com';
    await _updateNavigationState();
    await _injectAutoCloseCountryModal();
    await _runInitialAction();
    await _startAutoWatch();
  }

  /// Injects a MutationObserver that watches for the "Select country or region"
  /// modal and automatically clicks the "Done" button.
  Future<void> _injectAutoCloseCountryModal() async {
    try {
      await _webViewController?.evaluateJavascript(
        source: r'''
        (() => {
          if (window.__countryModalObserverActive) return;
          window.__countryModalObserverActive = true;

          const observer = new MutationObserver(() => {
            // Look for "Select country or region" text
            const headings = document.querySelectorAll('h1, h2, h3, h4, div, span');
            for (const el of headings) {
              const text = (el.innerText || el.textContent || '').trim().toLowerCase();
              if (text.includes('select country') || text.includes('select region') ||
                  text.includes('chọn quốc gia') || text.includes('chọn khu vực')) {
                // Find the "Done" button
                const buttons = document.querySelectorAll('button, a, [role="button"]');
                for (const btn of buttons) {
                  const btnText = (btn.innerText || btn.textContent || '').trim().toLowerCase();
                  if (btnText === 'done' || btnText === 'xong' || btnText === 'hoàn tất') {
                    btn.click();
                    return;
                  }
                }
              }
            }
          });

          observer.observe(document.body, {
            childList: true,
            subtree: true,
          });
        })();
      ''',
      );
    } catch (_) {}
  }

  Future<void> _updateNavigationState() async {
    if (!mounted) return;
    setState(() {
      _loadingProgress = 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        titleSpacing: 16,
        title: const Text(
          'TikTok',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
        ),
        actions: [
          IconButton(
            tooltip: 'Trang chủ TikTok',
            onPressed: () {
              _cancelAutoActions();
              _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(tiktokHomeUrl)),
              );
            },
            icon: const Icon(Icons.home_outlined, color: Colors.black),
          ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: () {
              _cancelAutoActions();
              _webViewController?.reload();
            },
            icon: Icon(
              Icons.refresh,
              color: Colors.black,
            ),
          ),
        ],
        bottom: _loadingProgress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress / 100,
                  minHeight: 2,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF25F4EE),
                ),
              )
            : null,
      ),
      bottomNavigationBar: _autoLoginBusy || _autoSignupBusy
          ? SafeArea(
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                    child: Text((_autoLoginBusy &&
                                _loginOtpRequest != null &&
                                _activeLoginOtp.isEmpty) ||
                            (_autoSignupBusy &&
                                _signupOtpRequest != null &&
                                _activeSignupOtp.isEmpty)
                        ? 'Đang chờ API lấy OTP… (tối đa ${widget.configuration.otpApi?.waitSeconds ?? 180} giây)'
                        : _autoLoginBusy
                            ? 'Đang đăng nhập tự động…'
                            : 'Đang đăng ký tự động…')),
                TextButton.icon(
                    onPressed: _cancelAutoActions,
                    icon: const Icon(Icons.stop),
                    label: const Text('Dừng')),
              ]),
            ))
          : null,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: inlineVideoScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              userAgent: widget.configuration.userAgent,
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'FlutterCommentPaste',
                callback: _pasteCommentFromClipboard,
              );
              controller.addJavaScriptHandler(
                handlerName: 'FlutterLoginPaste',
                callback: _pasteLoginFromClipboard,
              );
              controller.addJavaScriptHandler(
                handlerName: 'FlutterSignupPaste',
                callback: _pasteSignupFromClipboard,
              );
              controller.addJavaScriptHandler(
                handlerName: 'FlutterAutoWatch',
                callback: (args) {
                  if (args.isNotEmpty) {
                    _handleAutoWatchMessage(
                      args.first.toString(),
                    );
                  }
                },
              );
            },
            onReceivedHttpAuthRequest: (controller, challenge) async {
              final proxy = widget.configuration.proxy;
              if (proxy == null ||
                  proxy.username.isEmpty ||
                  challenge.protectionSpace.host != proxy.uri.host ||
                  challenge is! HttpAuthenticationChallenge ||
                  challenge.previousFailureCount > 0) {
                return null;
              }
              return HttpAuthResponse(
                username: proxy.username,
                password: proxy.password,
                action: HttpAuthResponseAction.PROCEED,
                permanentPersistence: false,
              );
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              _initialPageLoaded = false;
              setState(() {
                _loadingProgress = 0;
                _pageError = null;
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() {
                _loadingProgress = progress;
              });
            },
            onLoadStop: (controller, url) async {
              await _handlePageLoadComplete(url);
            },
            onReceivedError: (controller, request, error) {
              if (error.description.contains('net::ERR_ABORTED')) return;
              if (!mounted) return;
              setState(() => _pageError = error.description);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              if (!url.startsWith('http://') && !url.startsWith('https://')) {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_pageError != null)
            _ErrorView(
              message: _pageError!,
              onRetry: () => _webViewController?.reload(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('autoWatch'),
        heroTag: 'autoWatch',
        tooltip: _autoWatchEnabled
            ? 'Dừng tự động xem video và bình luận'
            : 'Bật tự động xem video và bình luận',
        backgroundColor: const Color(0xFF25F4EE),
        foregroundColor: Colors.black,
        onPressed: _webViewController == null ||
                _autoWatchBusy ||
                _autoLoginBusy ||
                _autoSignupBusy ||
                _loadingProgress < 100 ||
                (!_initialActionStarted &&
                    widget.launchAction != TikTokLaunchAction.browse)
            ? null
            : _toggleAutoWatch,
        icon: Icon(_autoWatchEnabled ? Icons.stop : Icons.play_arrow),
        label: Text(
            _autoWatchEnabled ? 'Dừng tự động' : 'Bật auto xem và bình luận'),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'Không thể mở TikTok',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
