import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/scripts/auto_login_script.dart';
import '../core/scripts/auto_cookie_script.dart';
import '../core/scripts/auto_signup_script.dart';
import '../core/scripts/auto_watch_script.dart';
import '../core/scripts/country_modal_script.dart';
import '../core/webview_proxy_ip.dart';
import '../core/app_configuration.dart';
import '../core/otp_api.dart';
import '../core/webview_failure.dart';
import '../core/webview_locale.dart';
import '../core/tiktok_launch_action.dart';
import 'app_controller.dart';

class TikTokController extends AppController with WidgetsBindingObserver {
  TikTokController(
      {required this.configuration,
      this.launchAction = TikTokLaunchAction.browse,
      this.otpReaderFactory});

  final AppConfiguration configuration;
  final TikTokLaunchAction launchAction;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;
  String get initialUrl => launchAction.initialUrl;

  static const commentInputChannel = MethodChannel('test_tiktok/comment_input');
  InAppWebViewController? webViewController;
  bool initialActionStarted = false;
  bool initialPageLoaded = false;
  bool autoLoginBusy = false;
  int autoLoginAttempt = 0;
  bool autoSignupBusy = false;
  int autoSignupAttempt = 0;
  String activeLoginOtp = '';
  String activeSignupOtp = '';
  OtpCodeRequest? loginOtpRequest;
  OtpCodeRequest? signupOtpRequest;

  int loadingProgress = 0;

  WebViewFailure? pageFailure;
  WebViewFailure? proxyWarning;
  bool proxyWarningIsIpCheck = false;
  bool checkingIp = false;
  int navigationId = 0;
  String? detectedIp;
  WebViewProxyIpChecker? _ipChecker;
  bool autoWatchEnabled = false;
  bool autoWatchBusy = false;
  bool appActive = true;
  late final List<String> comments;
  bool pasteBusy = false;

  @override
  void onInit() {
    super.onInit();
    comments = configuration.comments;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    _ipChecker?.cancel();
    cancelAutoLogin(updateUi: false);
    cancelAutoSignup(updateUi: false);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stopAutoWatch());
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (!appActive && autoLoginBusy) cancelAutoLogin();
    if (!appActive && autoSignupBusy) cancelAutoSignup();
    if (appActive) unawaited(runInitialAction());
    if (autoWatchEnabled && appActive) {
      unawaited(startAutoWatch());
    } else {
      unawaited(stopAutoWatch());
    }
  }

  Future<void> startAutoWatch() async {
    if (!active || !autoWatchEnabled || !appActive || pageFailure != null) {
      return;
    }
    try {
      final result = await webViewController?.evaluateJavascript(
        source: buildAutoWatchScript(comments),
      );
      if (result != true) throw StateError('Video watcher did not start');
      // The app may have been paused or the toggle disabled during injection.
      if (!active || !autoWatchEnabled || !appActive) {
        await stopAutoWatch();
      }
    } catch (_) {
      if (!active || !autoWatchEnabled) return;
      mutate(() => autoWatchEnabled = false);
      notify('Không thể bật tự động xem. Hãy thử tải lại TikTok.');
    }
  }

  Future<void> stopAutoWatch() async {
    try {
      await webViewController?.evaluateJavascript(source: autoWatchStopScript);
    } catch (_) {
      // Navigation/disposal may already have destroyed the old page.
    }
  }

  Future<bool> pasteCommentFromClipboard(List<dynamic> args) async {
    if (!active ||
        !autoWatchEnabled ||
        !appActive ||
        pasteBusy ||
        args.length != 1 ||
        args.first is! String) {
      return false;
    }
    final text = args.first as String;
    if (!comments.contains(text)) return false;
    pasteBusy = true;
    try {
      final url = await webViewController?.getUrl();
      if (url == null ||
          url.scheme != 'https' ||
          !(url.host == 'tiktok.com' || url.host.endsWith('.tiktok.com'))) {
        return false;
      }
      final source =
          'window.__flutterAutoWatch?.canPasteComment(${jsonEncode(text)}) === true;';
      if (await webViewController?.evaluateJavascript(source: source) != true) {
        return false;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (!active ||
          !autoWatchEnabled ||
          !appActive ||
          await webViewController?.evaluateJavascript(source: source) != true) {
        return false;
      }
      for (var retry = 0; retry < 6; retry++) {
        if (!active ||
            !autoWatchEnabled ||
            !appActive ||
            await webViewController?.evaluateJavascript(source: source) !=
                true) {
          return false;
        }
        if (await commentInputChannel
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
      pasteBusy = false;
    }
  }

  Future<void> toggleAutoWatch() async {
    if (autoWatchBusy ||
        autoLoginBusy ||
        autoSignupBusy ||
        webViewController == null) {
      return;
    }
    if (!autoWatchEnabled && comments.isEmpty) {
      notify('Hãy nhập nội dung bình luận ở màn Cấu hình.');
      return;
    }
    if (!active || autoLoginBusy || autoSignupBusy) return;
    mutate(() {
      autoWatchBusy = true;
      autoWatchEnabled = !autoWatchEnabled;
    });
    if (autoWatchEnabled) {
      await startAutoWatch();
    } else {
      await stopAutoWatch();
    }
    if (active) mutate(() => autoWatchBusy = false);
  }

  Future<void> stopAutoLogin(int attempt) async {
    try {
      await webViewController?.evaluateJavascript(
        source: buildAutoLoginStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void cancelAutoLogin({bool updateUi = true}) {
    loginOtpRequest?.cancel();
    loginOtpRequest = null;
    final attempt = autoLoginAttempt++;
    unawaited(stopAutoLogin(attempt));
    if (updateUi && active) mutate(() => autoLoginBusy = false);
  }

  Future<void> stopAutoSignup(int attempt) async {
    try {
      await webViewController?.evaluateJavascript(
        source: buildAutoSignupStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void cancelAutoSignup({bool updateUi = true}) {
    signupOtpRequest?.cancel();
    signupOtpRequest = null;
    final attempt = autoSignupAttempt++;
    unawaited(stopAutoSignup(attempt));
    if (updateUi && active) mutate(() => autoSignupBusy = false);
  }

  Future<bool> pasteSignupFromClipboard(List<dynamic> args) =>
      pasteAccountFromClipboard(args, signup: true);

  Future<bool> pasteLoginFromClipboard(List<dynamic> args) =>
      pasteAccountFromClipboard(args, signup: false);

  Future<bool> pasteAccountFromClipboard(List<dynamic> args,
      {required bool signup}) async {
    final controller = webViewController;
    final attempt = signup ? autoSignupAttempt : autoLoginAttempt;
    final accountContext = signup ? 'signup' : 'login';
    final stateName = signup ? '__flutterAutoSignup' : '__flutterAutoLogin';
    bool isActive() =>
        active &&
        appActive &&
        (signup
            ? autoSignupBusy && attempt == autoSignupAttempt
            : autoLoginBusy && attempt == autoLoginAttempt);
    if (!isActive() ||
        pasteBusy ||
        controller == null ||
        args.length != 2 ||
        args[0] != attempt ||
        (args[1] != 'email' && args[1] != 'password' && args[1] != 'otp')) {
      return false;
    }
    final field = args[1] as String;
    final text = switch (field) {
      'email' =>
        (signup ? configuration.signupEmail : configuration.loginUsername)
            .trim(),
      'otp' => signup ? activeSignupOtp : activeLoginOtp,
      _ => signup ? configuration.signupPassword : configuration.loginPassword,
    };
    if (text.isEmpty) return false;
    final source = 'window.$stateName?.canPasteFromClipboard('
        '$attempt, ${jsonEncode(field)}, ${jsonEncode(text)}) === true;';
    pasteBusy = true;
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
        final pasted = await commentInputChannel.invokeMethod<bool>('paste', {
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
      pasteBusy = false;
    }
  }

  bool validateOtpMailbox({required bool signup}) {
    final currentConfiguration = configuration;
    final otp =
        signup ? currentConfiguration.signupOtp : currentConfiguration.loginOtp;
    if (currentConfiguration.otpApi == null || otp.trim().isNotEmpty) {
      return true;
    }
    final email = signup
        ? currentConfiguration.signupEmail
        : currentConfiguration.loginUsername;
    final password = signup
        ? currentConfiguration.signupMailboxPassword
        : currentConfiguration.loginMailboxPassword;
    if (OtpApiConfiguration.isEmail(email) && password.isNotEmpty) return true;
    notify('Hãy nhập email và mật khẩu hộp thư lấy OTP ở màn Cấu hình.');
    return false;
  }

  OtpCodeRequest requestOtp({required bool signup}) {
    final api = configuration.otpApi!;
    final reader = otpReaderFactory?.call(api) ?? OtpApiClient(api);
    return OtpCodeRequest.start(
      reader,
      email: signup ? configuration.signupEmail : configuration.loginUsername,
      password: signup
          ? configuration.signupMailboxPassword
          : configuration.loginMailboxPassword,
    );
  }

  Future<void> autoSignup() async {
    if (autoSignupBusy) {
      cancelAutoSignup();
      return;
    }
    final controller = webViewController;
    if (controller == null || autoWatchBusy || autoLoginBusy || !appActive) {
      return;
    }
    if (configuration.signupEmail.trim().isEmpty ||
        configuration.signupPassword.isEmpty) {
      notify('Hãy nhập email và mật khẩu đăng ký ở màn Cấu hình.');
      return;
    }
    if (!validateOtpMailbox(signup: true)) return;
    activeSignupOtp = configuration.signupOtp.trim();
    final attempt = ++autoSignupAttempt;
    mutate(() {
      autoSignupBusy = true;
      autoWatchEnabled = false;
    });
    bool isActive() =>
        active && appActive && autoSignupBusy && attempt == autoSignupAttempt;
    String? message;
    var submitted = false;
    var otpSubmitted = false;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    try {
      await stopAutoWatch();
      if (!active || !isActive()) return;
      final birthday =
          configuration.birthday ?? AppConfiguration.randomSignupBirthday();
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
        if (activeSignupOtp.isEmpty && otpRequest?.code != null) {
          mutate(() => activeSignupOtp = otpRequest!.code!);
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
              email: configuration.signupEmail.trim(),
              password: configuration.signupPassword,
              birthday: birthday,
              attempt: attempt,
              allowSubmit: !submitted,
              otp: activeSignupOtp,
              otpRequestedAt: otpRequestedAt,
              allowOtpSubmit: !otpSubmitted,
              waitForOtpApi:
                  configuration.otpApi != null && activeSignupOtp.isEmpty,
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
            activeSignupOtp.isEmpty &&
            configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          otpRequest = requestOtp(signup: true);
          mutate(() => signupOtpRequest = otpRequest);
          deadline = DateTime.now()
              .add(Duration(seconds: configuration.otpApi!.waitSeconds + 45));
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
          if (activeSignupOtp.isEmpty && otpRequest == null) {
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
      if (identical(signupOtpRequest, otpRequest)) signupOtpRequest = null;
      await stopAutoSignup(attempt);
      if (active && isActive()) {
        mutate(() => autoSignupBusy = false);
        if (message != null) {
          notify(message);
        }
      }
    }
  }

  Future<void> autoLogin() async {
    if (autoLoginBusy) {
      cancelAutoLogin();
      return;
    }
    final controller = webViewController;
    if (controller == null || autoWatchBusy || autoSignupBusy || !appActive) {
      return;
    }
    if (configuration.loginUsername.trim().isEmpty ||
        configuration.loginPassword.isEmpty) {
      notify('Hãy nhập tài khoản và mật khẩu đăng nhập ở màn Cấu hình.');
      return;
    }
    if (!validateOtpMailbox(signup: false)) return;
    activeLoginOtp = configuration.loginOtp.trim();
    final attempt = ++autoLoginAttempt;
    mutate(() {
      autoLoginBusy = true;
      autoWatchEnabled = false;
    });
    bool isActive() =>
        active && appActive && autoLoginBusy && attempt == autoLoginAttempt;
    var submitted = false;
    var otpSubmitted = false;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    var message = 'Không thể mở trang đăng nhập. Hãy thử tải lại TikTok.';
    try {
      await stopAutoWatch();
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
        if (activeLoginOtp.isEmpty && otpRequest?.code != null) {
          mutate(() => activeLoginOtp = otpRequest!.code!);
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
              email: configuration.loginUsername.trim(),
              password: configuration.loginPassword,
              allowSubmit: !submitted,
              attempt: attempt,
              otp: activeLoginOtp,
              otpRequestedAt: otpRequestedAt,
              allowOtpSubmit: !otpSubmitted,
              waitForOtpApi:
                  configuration.otpApi != null && activeLoginOtp.isEmpty,
            ),
          );
        } catch (_) {
          continue;
        }
        if (!isActive()) return;
        if ((result == 'verification-requested' || result == 'otp-required') &&
            activeLoginOtp.isEmpty &&
            configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          otpRequest = requestOtp(signup: false);
          mutate(() => loginOtpRequest = otpRequest);
          deadline = DateTime.now()
              .add(Duration(seconds: configuration.otpApi!.waitSeconds + 45));
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
          if (activeLoginOtp.isEmpty && otpRequest == null) {
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
      if (identical(loginOtpRequest, otpRequest)) loginOtpRequest = null;
      await stopAutoLogin(attempt);
      if (active && isActive()) {
        mutate(() => autoLoginBusy = false);
        notify(message);
      }
    }
  }

  void handleAutoWatchMessage(String message) {
    if (!active || !autoWatchEnabled) return;
    if (message == 'comment-sent') {
      notify('Đã gửi bình luận.', duration: const Duration(seconds: 2));
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
    mutate(() => autoWatchEnabled = false);
    unawaited(stopAutoWatch());
    notify(text);
  }

  Future<void> runInitialAction() async {
    if (!active ||
        !appActive ||
        !initialPageLoaded ||
        pageFailure != null ||
        initialActionStarted ||
        webViewController == null) {
      return;
    }
    // Latch before starting: reloads, SPA navigations and resume cannot submit again.
    initialActionStarted = true;
    switch (launchAction) {
      case TikTokLaunchAction.browse:
        return;
      case TikTokLaunchAction.login:
        await autoLogin();
      case TikTokLaunchAction.signup:
        await autoSignup();
    }
  }

  void cancelAutoActions() {
    initialActionStarted = true;
    if (autoLoginBusy) cancelAutoLogin();
    if (autoSignupBusy) cancelAutoSignup();
  }

  Future<void> handlePageLoadComplete(WebUri? url) async {
    if (!active) return;
    initialPageLoaded = pageFailure == null &&
        url?.scheme == 'https' &&
        url?.host == 'www.tiktok.com';
    await updateNavigationState();
    if (pageFailure != null) return;
    try {
      await webViewController?.evaluateJavascript(
          source: autoAcceptCookieScript);
    } catch (_) {
      // A navigation can destroy the old document; the next document installs it again.
    }
    await injectAutoCloseCountryModal();
    unawaited(checkProxyIp());
    await runInitialAction();
    await startAutoWatch();
  }

  void showProxyWarning(WebViewFailure failure, {bool ipCheck = false}) {
    if (!active || configuration.proxy == null) return;
    if (ipCheck && proxyWarning != null && !proxyWarningIsIpCheck) return;
    mutate(() {
      proxyWarning = failure;
      proxyWarningIsIpCheck = ipCheck;
      if (!ipCheck) detectedIp = null;
    });
  }

  void showPageFailure(WebViewFailure failure) {
    if (!active) return;
    _ipChecker?.cancel();
    if (autoLoginBusy) cancelAutoLogin();
    if (autoSignupBusy) cancelAutoSignup();
    if (autoWatchEnabled) unawaited(stopAutoWatch());
    mutate(() {
      pageFailure = failure;
      initialPageLoaded = false;
      autoWatchEnabled = false;
      checkingIp = false;
      detectedIp = null;
    });
  }

  void receiveProxyIp(List<dynamic> args) {
    if (!active ||
        args.length != 2 ||
        args.first != navigationId ||
        pageFailure != null) {
      return;
    }
    final ip = args[1];
    final valid = ip is String && ip.isNotEmpty && ip != 'Không xác định';
    mutate(() {
      checkingIp = false;
      detectedIp = valid ? ip : 'Không xác định';
      if (valid && proxyWarningIsIpCheck) {
        proxyWarning = null;
        proxyWarningIsIpCheck = false;
      }
    });
    if (!valid) {
      showProxyWarning(WebViewFailure.ipUnverified, ipCheck: true);
    }
    debugPrint('Proxy IP detected: $detectedIp');
  }

  /// Check with the same native proxy, independently of TikTok's document.
  Future<void> checkProxyIp() async {
    if (!active ||
        checkingIp ||
        pageFailure != null ||
        webViewController == null) {
      return;
    }
    final checkNavigationId = navigationId;
    final checker = WebViewProxyIpChecker();
    _ipChecker = checker;
    mutate(() => checkingIp = true);
    try {
      final ip = await checker.check(
        userAgent: configuration.userAgent,
        onAuth: (controller, challenge) async {
          if (!active || checkNavigationId != navigationId) {
            return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
          }
          return onReceivedHttpAuthRequest(controller, challenge);
        },
      );
      receiveProxyIp([checkNavigationId, ip ?? 'Không xác định']);
    } catch (_) {
      if (active && checkNavigationId == navigationId) {
        receiveProxyIp([checkNavigationId, 'Không xác định']);
      }
    } finally {
      if (identical(_ipChecker, checker)) _ipChecker = null;
    }
  }

  /// Injects a MutationObserver that watches for the "Select country or region"
  /// modal and automatically clicks the "Done" button.
  Future<void> injectAutoCloseCountryModal() async {
    try {
      await webViewController?.evaluateJavascript(
        source: autoCloseCountryModalScript,
      );
    } catch (_) {}
  }

  Future<void> updateNavigationState() async {
    if (!active) return;
    mutate(() {
      loadingProgress = 100;
    });
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: 'FlutterCommentPaste',
      callback: pasteCommentFromClipboard,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterLoginPaste',
      callback: pasteLoginFromClipboard,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterSignupPaste',
      callback: pasteSignupFromClipboard,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterAutoWatch',
      callback: (args) {
        if (args.isNotEmpty) {
          handleAutoWatchMessage(
            args.first.toString(),
          );
        }
      },
    );
  }

  Future<HttpAuthResponse?> onReceivedHttpAuthRequest(
      InAppWebViewController controller,
      URLAuthenticationChallenge challenge) async {
    final proxy = configuration.proxy;
    // The Android plugin increments this counter before the first
    // callback (1); WebKit reports previous failures starting at 0.
    final firstChallengeCount =
        defaultTargetPlatform == TargetPlatform.android ? 1 : 0;
    if (proxy == null ||
        challenge.protectionSpace.host != proxy.uri.host ||
        challenge is! HttpAuthenticationChallenge) {
      return null;
    }
    if (proxy.username.isEmpty ||
        challenge.previousFailureCount > firstChallengeCount) {
      showProxyWarning(proxy.username.isEmpty
          ? WebViewFailure.missingProxyAuth
          : WebViewFailure.proxyAuth);
      return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
    }
    return HttpAuthResponse(
      username: proxy.username,
      password: proxy.password,
      action: HttpAuthResponseAction.PROCEED,
      permanentPersistence: false,
    );
  }

  void onLoadStart(InAppWebViewController controller, WebUri? url) {
    if (!active) return;
    _ipChecker?.cancel();
    initialPageLoaded = false;
    mutate(() {
      navigationId++;
      loadingProgress = 0;
      pageFailure = null;
      proxyWarning = null;
      proxyWarningIsIpCheck = false;
      checkingIp = false;
      detectedIp = null;
    });
  }

  void onProgressChanged(InAppWebViewController controller, int progress) {
    if (!active) return;
    mutate(() {
      loadingProgress = progress;
    });
  }

  Future<void> onLoadStop(
      InAppWebViewController controller, WebUri? url) async {
    await handlePageLoadComplete(url);
  }

  void onReceivedError(InAppWebViewController controller,
      WebResourceRequest request, WebResourceError error) {
    if (error.description.contains('net::ERR_ABORTED') ||
        error.type == WebResourceErrorType.CANCELLED) {
      return;
    }
    final failure =
        WebViewFailure.network(error, usingProxy: configuration.proxy != null);
    if (request.isForMainFrame == false) {
      if (failure.isConnectionFailure) {
        showProxyWarning(failure);
      }
      return;
    }
    final authFailure = proxyWarning == WebViewFailure.proxyAuth ||
        proxyWarning == WebViewFailure.missingProxyAuth;
    showPageFailure(authFailure ? proxyWarning! : failure);
  }

  void onReceivedHttpError(InAppWebViewController controller,
      WebResourceRequest request, WebResourceResponse response) {
    final status = response.statusCode;
    if (status == null || status < 400) return;
    final failure = WebViewFailure.http(status);
    if (request.isForMainFrame != false) {
      showPageFailure(failure);
    } else if (status == 407) {
      showProxyWarning(failure);
    }
  }

  Future<NavigationActionPolicy?> shouldOverrideUrlLoading(
      InAppWebViewController controller,
      NavigationAction navigationAction) async {
    final url = navigationAction.request.url.toString();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  void goHome() {
    cancelAutoActions();
    unawaited(webViewController?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(tiktokHomeUrl),
        headers: englishWebViewHeaders,
      ),
    ));
  }

  void reloadPage() {
    cancelAutoActions();
    unawaited(webViewController?.reload());
  }

  void retryPage() => unawaited(webViewController?.reload());

  void retryProxyWarning() {
    if (checkingIp) return;
    if (proxyWarningIsIpCheck) {
      unawaited(checkProxyIp());
    } else {
      reloadPage();
    }
  }
}
