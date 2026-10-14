import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/scripts/auto_login_script.dart';
import '../core/send_code_accessibility.dart';
import '../core/scripts/auto_cookie_script.dart';
import '../core/scripts/auto_interest_script.dart';
import '../core/scripts/auto_signup_script.dart';
import '../core/scripts/auto_watch_script.dart';
import '../core/scripts/country_modal_script.dart';
import '../core/webview_proxy_ip.dart';
import '../core/webview_user_agent.dart';
import '../core/app_configuration.dart';
import '../core/otp_api.dart';
import '../core/webview_failure.dart';
import '../core/tiktok_launch_action.dart';
import '../core/tiktok_account_failure.dart';
import 'app_controller.dart';

class TikTokController extends AppController with WidgetsBindingObserver {
  TikTokController({
    required this.configuration,
    this.launchAction = TikTokLaunchAction.browse,
    this.otpReaderFactory,
    this.onReturnToConfiguration,
    bool? useAccessibility,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _accessibilityOverride = useAccessibility;

  final AppConfiguration configuration;
  final TikTokLaunchAction launchAction;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;
  final VoidCallback? onReturnToConfiguration;
  final DateTime Function() _now;
  final bool? _accessibilityOverride;
  String get initialUrl => launchAction.initialUrl;

  static const commentInputChannel = MethodChannel('test_tiktok/comment_input');
  // Randomize the login/signup JS evaluation cadence, not API timeouts.
  // Most normal interactions wait 3-6s, while all waits remain inside 2-10s.
  static final Random _actionRandom = Random();

  static Duration get accountActionInterval {
    final bucket = _actionRandom.nextInt(100);
    final milliseconds = switch (bucket) {
      < 70 => 3000 + _actionRandom.nextInt(3001), // 70%: 3-6 seconds
      < 85 => 2000 + _actionRandom.nextInt(1001), // 15%: 2-3 seconds
      _ => 6001 + _actionRandom.nextInt(4000), // 15%: >6-10 seconds
    };
    return Duration(milliseconds: milliseconds);
  }

  // OTP entry and Next/Continue should be responsive, not delayed 2-10s.
  static Duration get otpActionInterval =>
      Duration(milliseconds: 200 + _actionRandom.nextInt(201));

  static bool isFastAccountStep(dynamic result) {
    if (result is! String) return false;
    if (const {
      'requesting-verification',
      'waiting-send-code',
      'waiting-email-verification',
      'requesting-email-verification',
      'verification-requested',
      'email-verification-selected',
      'otp-required',
      'waiting-otp',
      'waiting-otp-paste',
      'waiting-verification-transition',
      'waiting-next',
      'waiting-password-screen', // Go to the post-OTP Next/password screen.
      'waiting-password-submit', // Continue as soon as the form is ready.
      'submitted',
      'otp-submitted',
      'password-submitted',
    }.contains(result)) {
      return true;
    }
    // Supports Next/Continue statuses returned by login/signup scripts.
    return result == 'next' ||
        result.startsWith('next-') ||
        result.endsWith('-next') ||
        result.startsWith('waiting-next') ||
        result == 'continue' ||
        result.startsWith('continue-');
  }

  InAppWebViewController? webViewController;
  bool initialActionStarted = false;
  bool initialPageLoaded = false;
  bool autoLoginBusy = false;
  SendCodeAccessibility? _sendCodeAccessibility;
  final Map<String, int> _accountTapAttempts = {};
  bool _requestingAccessibility = false;
  bool get _usesAccessibility =>
      _accessibilityOverride ?? (!kIsWeb && Platform.isAndroid);
  int autoLoginAttempt = 0;
  bool autoSignupBusy = false;
  String signupStatus = 'Đang đăng ký tự động…';
  int autoSignupAttempt = 0;
  String activeLoginOtp = '';
  String activeSignupOtp = '';
  OtpCodeRequest? loginOtpRequest;
  OtpCodeRequest? signupOtpRequest;

  int loadingProgress = 0;

  WebViewFailure? pageFailure;
  TikTokAccountFailure? accountFailure;
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
    unawaited(_sendCodeAccessibility?.dispose());
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
        if (await commentInputChannel.invokeMethod<bool>('paste', {
              'context': 'comment',
            }) ==
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

  Future<bool> clickLoginSendCode(List<dynamic> args) =>
      tapAccountButton(args, signup: false);

  Future<bool> clickLoginEmailVerification(List<dynamic> args) =>
      tapAccountButton(
        args,
        signup: false,
        action: 'select-verification-email',
      );

  Future<bool> clickLoginPasswordContinue(List<dynamic> args) =>
      tapAccountButton(args, signup: false, action: 'continue-password');

  Future<bool> clickLoginOtpContinue(List<dynamic> args) =>
      tapAccountButton(args, signup: false, action: 'continue-otp');

  Future<bool> clickSignupSendCode(List<dynamic> args) =>
      tapAccountButton(args, signup: true);

  Future<bool> clickSignupPasswordSubmit(List<dynamic> args) =>
      tapAccountButton(args, signup: true, action: 'submit-password');

  Future<bool> clickSignupUsernameSkip(List<dynamic> args) =>
      tapAccountButton(args, signup: true, action: 'skip-username');

  Future<bool> tapAccountButton(
    List<dynamic> args, {
    required bool signup,
    String action = 'send-code',
  }) async {
    final controller = webViewController;
    final accessibility = _sendCodeAccessibility;
    final attempt = signup ? autoSignupAttempt : autoLoginAttempt;
    final context = signup ? 'signup' : 'login';
    const labels = {
      'signup': {
        'send-code': 'Send code',
        'submit-password': 'Sign up',
        'skip-username': 'Skip',
      },
      'login': {
        'select-verification-email': 'Email',
        'send-code': 'Send code',
        'continue-password': 'Continue',
        'continue-otp': 'Continue',
      },
    };
    final buttonLabel = labels[context]?[action];
    if (buttonLabel == null) return false;
    bool isActive() =>
        active &&
        appActive &&
        (signup
            ? autoSignupBusy && attempt == autoSignupAttempt
            : autoLoginBusy && attempt == autoLoginAttempt);
    if (!_usesAccessibility ||
        controller == null ||
        accessibility == null ||
        args.length != 1 ||
        args.first != attempt ||
        !isActive()) {
      return false;
    }
    // Keep the one-touch latch outside JavaScript so a page/context replacement
    // cannot dispatch a second gesture for the same button step.
    final stepKey = '$context/$action';
    if (_accountTapAttempts[stepKey] == attempt) return false;
    _accountTapAttempts[stepKey] = attempt;
    debugPrint(
      '[$buttonLabel] Gesture requested for $context attempt $attempt.',
    );
    try {
      final completed = await accessibility.tapButton(
        buttonLabel: buttonLabel,
        getTarget: () async {
          if (!isActive()) return null;
          final url = await controller.getUrl();
          if (!isActive() ||
              url?.scheme != 'https' ||
              url?.host != 'www.tiktok.com') {
            return null;
          }
          final point =
              await const MethodChannel(
                'test_tiktok/send_code_target',
              ).invokeMapMethod<String, dynamic>('getTarget', {
                'id': controller.platform.params.id,
                'attempt': attempt,
                'context': context,
                'action': action,
              });
          if (!isActive() || point == null) return null;
          final x = point['x'];
          final y = point['y'];
          if (x is! num || y is! num) return null;
          return Offset(x.toDouble(), y.toDouble());
        },
      );
      debugPrint('[$buttonLabel] $context gesture completed: $completed.');
      return completed;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pasteAccountFromClipboard(
    List<dynamic> args, {
    required bool signup,
  }) async {
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
    final source =
        'window.$stateName?.canPasteFromClipboard('
        '$attempt, ${jsonEncode(field)}, ${jsonEncode(text)}) === true;';
    pasteBusy = true;
    try {
      debugPrint('Auto $accountContext: pasting $field from clipboard.');
      final url = await controller.getUrl();
      // Account dialogs can keep the Home URL. The script authorizes only the
      // focused field in the visible form for this attempt.
      if (!isActive() ||
          url?.scheme != 'https' ||
          url?.host != 'www.tiktok.com' ||
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
    final otp = signup
        ? currentConfiguration.signupOtp
        : currentConfiguration.loginOtp;
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

  Future<bool> ensureAccountAccessibility() async {
    if (_requestingAccessibility) return false;
    if (_usesAccessibility) {
      _requestingAccessibility = true;
      try {
        if (!await FlutterAccessibilityService.isAccessibilityPermissionEnabled()) {
          await FlutterAccessibilityService.requestAccessibilityPermission();
          if (active) {
            notify(
              'Bật Trợ năng cho Tool TikTok, quay lại ứng dụng rồi chạy thao tác lại.',
            );
          }
          return false;
        }
        if (!active || !appActive) return false;
        _sendCodeAccessibility ??= SendCodeAccessibility();
        _sendCodeAccessibility!.start();
      } catch (_) {
        if (active)
          notify('Không thể kết nối dịch vụ Trợ năng để bấm Send code.');
        return false;
      } finally {
        _requestingAccessibility = false;
      }
    }
    return true;
  }

  Future<void> autoSignup() async {
    if (autoSignupBusy) {
      cancelAutoSignup();
      return;
    }
    final controller = webViewController;
    if (controller == null ||
        autoWatchBusy ||
        autoLoginBusy ||
        !appActive ||
        accountFailure != null) {
      return;
    }
    if (configuration.signupEmail.trim().isEmpty ||
        configuration.signupPassword.isEmpty) {
      notify('Hãy nhập email và mật khẩu đăng ký ở màn Cấu hình.');
      return;
    }
    if (!validateOtpMailbox(signup: true)) return;
    if (!await ensureAccountAccessibility()) return;
    activeSignupOtp = configuration.signupOtp.trim();
    final attempt = ++autoSignupAttempt;
    mutate(() {
      autoSignupBusy = true;
      signupStatus = 'Đang đăng ký tự động…';
      autoWatchEnabled = false;
    });
    bool isActive() =>
        active && appActive && autoSignupBusy && attempt == autoSignupAttempt;
    String? message;
    var submitted = false;
    var otpSubmitted = false;
    var passwordSubmitted = false;
    var signupSucceeded = false;
    var awaitingOtpTransition = false;
    DateTime? verificationRequiredSince;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    try {
      await stopAutoWatch();
      if (!active || !isActive()) return;
      final birthday =
          configuration.birthday ?? AppConfiguration.randomSignupBirthday();
      message = 'Không thể mở trang đăng ký. Hãy thử tải lại TikTok.';
      var deadline = DateTime.now().add(const Duration(seconds: 240));
      var evaluationFailures = 0;
      String? lastStep;
      message =
          'Chưa hoàn tất đăng ký. Hãy kiểm tra biểu mẫu trên TikTok; '
          'bạn có thể chọn ngày sinh hoặc tiếp tục thủ công.';
      while (isActive() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(
          isFastAccountStep(lastStep) ||
                  (otpRequest?.code != null && activeSignupOtp.isEmpty)
              ? otpActionInterval
              : accountActionInterval,
        );
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
              allowPasswordSubmit: !passwordSubmitted,
              waitForOtpApi:
                  configuration.otpApi != null && activeSignupOtp.isEmpty,
              useAccessibilitySendCode: _usesAccessibility,
              useAccessibilityPasswordSubmit: _usesAccessibility,
              useAccessibilityUsernameSkip: _usesAccessibility,
            ),
          );
          evaluationFailures = 0;
        } catch (error) {
          debugPrint('Auto signup: evaluation failed (${error.runtimeType}).');
          if (++evaluationFailures >= 5) {
            message =
                'Không thể chạy thao tác trên biểu mẫu đăng ký. '
                'Hãy dừng app rồi chạy lại, tránh hot restart WebView.';
            break;
          }
          continue;
        }
        if (!isActive()) return;
        if (result == 'waiting-otp-paste' || result == 'otp-submitted') {
          awaitingOtpTransition = true;
        } else if (result == 'waiting-password-screen' ||
            result == 'waiting-password-submit' ||
            result == 'password-submitted') {
          awaitingOtpTransition = false;
        }
        // TikTok can briefly expose a verification view while accepting the
        // pasted OTP and mounting the password form. Confirm it persists before
        // ending the attempt; the script performs no input/click in this state.
        if (result == 'verification-required' && awaitingOtpTransition) {
          if (verificationRequiredSince == null) {
            verificationRequiredSince = _now();
            debugPrint('Auto signup: waiting-verification-transition.');
          }
          if (_now().difference(verificationRequiredSince) <
              const Duration(milliseconds: 1500)) {
            lastStep = 'waiting-verification-transition';
            continue;
          }
        } else {
          verificationRequiredSince = null;
        }
        if (result == 'account-rate-limited') {
          showAccountFailure(TikTokAccountFailure.rateLimited);
          return;
        }
        if (result is String && result != lastStep) {
          debugPrint('Auto signup: $result.');
          lastStep = result;
        }
        final status = switch (result) {
          'waiting-send-code' => 'Đang chờ 5 giây trước khi bấm Send code…',
          'requesting-verification' => 'Đang chờ TikTok xác nhận gửi mã…',
          'verification-requested' => 'TikTok đã tiếp nhận yêu cầu gửi mã…',
          'waiting-otp' => 'Đang chờ ô nhập OTP đăng ký…',
          'waiting-paste' => 'Đang nhập thông tin đăng ký…',
          'waiting-otp-paste' => 'Đang nhập OTP đăng ký…',
          'waiting-password-screen' => 'Đang chờ màn nhập mật khẩu ổn định…',
          'waiting-password-submit' =>
            'Đã nhập mật khẩu, chờ 10 giây trước khi bấm Sign up…',
          'otp-submitted' => 'Đang chờ kết quả đăng ký…',
          'password-submitted' => 'Đã gửi mật khẩu, đang chờ kết quả đăng ký…',
          'waiting-username-skip' =>
            'Đang chờ trước khi bỏ qua tạo tên người dùng…',
          'username-skipped' => 'Đã bấm Skip, đang chờ hoàn tất đăng ký…',
          _ => null,
        };
        if (status != null && signupStatus != status) {
          mutate(() => signupStatus = status);
        }
        if ((result == 'verification-requested' || result == 'otp-required') &&
            activeSignupOtp.isEmpty &&
            configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          otpRequest = requestOtp(signup: true);
          mutate(() => signupOtpRequest = otpRequest);
          deadline = DateTime.now().add(
            Duration(seconds: configuration.otpApi!.waitSeconds + 45),
          );
          message = 'Đã yêu cầu mã. Đang lấy OTP đăng ký từ API…';
          // Poll the OTP field immediately even if the prior step was slow.
          lastStep = 'otp-required';
          continue;
        }
        if (result == 'submitted' ||
            result == 'otp-submitted' ||
            result == 'password-submitted') {
          submitted = true;
          if (result == 'otp-submitted') otpSubmitted = true;
          if (result == 'password-submitted') {
            passwordSubmitted = true;
            deadline = DateTime.now().add(const Duration(seconds: 45));
          }
          message =
              'Đã gửi đăng ký nhưng chưa xác nhận được kết quả. '
              'Hãy kiểm tra trên TikTok.';
        } else if (result == 'already-logged-in' ||
            result == 'signup-success') {
          signupSucceeded = true;
          message = result == 'already-logged-in'
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng ký TikTok thành công.';
          break;
        } else if (result == 'verification-required') {
          message =
              'TikTok yêu cầu CAPTCHA hoặc mã xác minh. '
              'Hãy hoàn tất trên trang đăng ký.';
          break;
        } else if (result == 'verification-requested') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          if (activeSignupOtp.isEmpty && otpRequest == null) {
            message =
                'Đã gửi mã. Hãy nhập OTP trên trang đăng ký, '
                'hoặc điền Mã OTP đăng ký ở màn Cấu hình rồi chạy lại.';
            break;
          }
          message = 'Đã yêu cầu mã. Đang chờ OTP để tự nhập mã đăng ký.';
        } else if (result == 'username-skip-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessageFor('Skip') ??
              'Chưa chạm được nút Skip trên màn tạo username.';
          break;
        } else if (result == 'password-submit-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessageFor('Sign up') ??
              'Chưa chạm được nút Sign up trên màn mật khẩu sau OTP.';
          break;
        } else if (result == 'send-code-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessage ??
              'Chưa chạm được nút Send code trên biểu mẫu đăng ký. Hãy kiểm tra nút gửi mã trên TikTok.';
          break;
        } else if (result == 'verification-request-failed') {
          message =
              'TikTok chưa xác nhận gửi mã sau khi bấm Send code. '
              'Đã dừng và chưa gọi API OTP. Hãy kiểm tra thông báo trên biểu mẫu rồi thử lại.';
          break;
        } else if (result == 'otp-required') {
          message = 'Đang lấy OTP đăng ký từ API…';
        } else if (result == 'waiting-otp' || result == 'waiting-otp-paste') {
          otpRequestedAt ??= DateTime.now().millisecondsSinceEpoch;
          message = 'Đang chờ ô OTP đăng ký để tự nhập mã.';
        } else if (result == 'email-registered') {
          message =
              'Email đăng ký đã có tài khoản TikTok. '
              'Hãy đăng nhập hoặc đổi email đăng ký ở màn Cấu hình.';
          break;
        } else if (result == 'checkbox-failed') {
          message =
              'Chưa tích được ô nhận tin TikTok. '
              'Hãy tích ô này trên biểu mẫu rồi tiếp tục.';
          break;
        } else if (result == 'signup-error') {
          message =
              'TikTok báo lỗi đăng ký. Hãy kiểm tra thông tin trên trang.';
          break;
        } else if (result == 'paste-failed') {
          message =
              'Không thể dán thông tin đăng ký từ clipboard. '
              'Đã dừng, bạn có thể nhập thủ công.';
          break;
        } else if (result == 'draft-exists') {
          message =
              'Có thông tin đang nhập trên biểu mẫu. '
              'Đã dừng để giữ nội dung của bạn.';
          break;
        } else if (result == 'birthday-required') {
          message =
              'Không thể chọn ngày sinh tự động. '
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
        if (signupSucceeded && appActive && pageFailure == null) {
          mutate(() => autoWatchEnabled = true);
          await startAutoWatch();
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
    if (controller == null ||
        autoWatchBusy ||
        autoSignupBusy ||
        !appActive ||
        accountFailure != null) {
      return;
    }
    if (configuration.loginUsername.trim().isEmpty ||
        configuration.loginPassword.isEmpty) {
      notify('Hãy nhập tài khoản và mật khẩu đăng nhập ở màn Cấu hình.');
      return;
    }
    if (!validateOtpMailbox(signup: false)) return;
    if (!await ensureAccountAccessibility()) return;
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
    var loginSucceeded = false;
    int? otpRequestedAt;
    OtpCodeRequest? otpRequest;
    var message = 'Không thể mở trang đăng nhập. Hãy thử tải lại TikTok.';
    int? emailVerificationRequestedAt;
    var emailVerificationPreparing = false;
    try {
      await stopAutoWatch();
      if (!isActive()) return;
      var deadline = _now().add(const Duration(seconds: 180));
      String? lastStep;
      message =
          'Không tìm thấy biểu mẫu đăng nhập. Bạn có thể đăng nhập thủ công.';
      while (isActive() && _now().isBefore(deadline)) {
        await Future<void>.delayed(
          isFastAccountStep(lastStep) ||
                  (otpRequest?.code != null && activeLoginOtp.isEmpty)
              ? otpActionInterval
              : accountActionInterval,
        );
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
              emailVerificationRequestedAt: emailVerificationRequestedAt,
              allowOtpSubmit: !otpSubmitted,
              waitForOtpApi:
                  configuration.otpApi != null && activeLoginOtp.isEmpty,
              useAccessibilitySendCode: _usesAccessibility,
              useAccessibilityContinue: _usesAccessibility,
              useAccessibilityEmailVerification: _usesAccessibility,
            ),
          );
        } catch (error) {
          debugPrint('Auto login: evaluation failed (${error.runtimeType}).');
          continue;
        }
        if (!isActive()) return;
        if (result == 'account-rate-limited') {
          showAccountFailure(TikTokAccountFailure.rateLimited);
          return;
        }
        if (result is String && result != lastStep) {
          debugPrint('Auto login: $result.');
          lastStep = result;
        }
        if ((result == 'waiting-email-verification' ||
                result == 'requesting-email-verification') &&
            !emailVerificationPreparing) {
          emailVerificationPreparing = true;
          deadline = _now().add(const Duration(seconds: 45));
          message = 'Đang chờ 5 giây trước khi chạm hộp Email…';
        }
        if (result == 'email-verification-selected' &&
            emailVerificationRequestedAt == null) {
          emailVerificationRequestedAt ??= _now().millisecondsSinceEpoch;
          deadline = _now().add(const Duration(seconds: 45));
          message = 'Đã chọn Email. Đang chờ TikTok gửi mã xác minh…';
        }
        if ((result == 'verification-requested' || result == 'otp-required') &&
            activeLoginOtp.isEmpty &&
            configuration.otpApi != null &&
            otpRequest == null) {
          otpRequestedAt ??= _now().millisecondsSinceEpoch;
          otpRequest = requestOtp(signup: false);
          mutate(() => loginOtpRequest = otpRequest);
          deadline = _now().add(
            Duration(seconds: configuration.otpApi!.waitSeconds + 45),
          );
          message = 'Đã yêu cầu mã. Đang lấy OTP đăng nhập từ API…';
          // Poll the OTP field immediately even if the prior step was slow.
          lastStep = 'otp-required';
          continue;
        }
        if (result == 'submitted' || result == 'otp-submitted') {
          if (!submitted) {
            // Opening the login methods can use most of the initial budget.
            // Give the post-password identity dialog its own waiting period.
            deadline = _now().add(const Duration(seconds: 45));
          }
          submitted = true;
          if (result == 'otp-submitted') {
            otpSubmitted = true;
            // Give TikTok time to finish Next and load the signed-in page,
            // even if entering the code used most of the original deadline.
            deadline = _now().add(const Duration(seconds: 45));
          }
          message =
              'Đã gửi đăng nhập nhưng chưa xác nhận được kết quả. '
              'Hãy kiểm tra trên TikTok.';
        } else if (result == 'already-logged-in' || result == 'login-success') {
          loginSucceeded = true;
          message = result == 'already-logged-in'
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng nhập TikTok thành công.';
          break;
        } else if (result == 'verification-requested') {
          otpRequestedAt ??= _now().millisecondsSinceEpoch;
          if (activeLoginOtp.isEmpty && otpRequest == null) {
            message =
                'Đã gửi mã. Hãy nhập OTP trên trang đăng nhập, '
                'hoặc điền Mã OTP đăng nhập ở màn Cấu hình rồi chạy lại.';
            break;
          }
          message = 'Đã yêu cầu mã. Đang chờ OTP để tự nhập mã đăng nhập.';
        } else if (result == 'otp-required') {
          message = 'Đang lấy OTP đăng nhập từ API…';
        } else if (result == 'email-verification-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessageFor('Email') ??
              'Chưa chạm được hộp Email. Hãy kiểm tra hộp xác minh trên TikTok.';
          break;
        } else if (result == 'continue-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessageFor('Continue') ??
              'Chưa chạm được nút Continue trên biểu mẫu đăng nhập.';
          break;
        } else if (result == 'send-code-accessibility-failed') {
          message =
              _sendCodeAccessibility?.failureMessage ??
              'Chưa chạm được nút Send code. Hãy kiểm tra nút gửi mã trên TikTok.';
          break;
        } else if (result == 'verification-request-failed') {
          message =
              'TikTok chưa xác nhận gửi mã. '
              'Đã dừng và chưa gọi API OTP. Hãy kiểm tra hộp xác minh rồi thử lại.';
          break;
        } else if (result == 'waiting-otp' || result == 'waiting-otp-paste') {
          otpRequestedAt ??= _now().millisecondsSinceEpoch;
          message = 'Đang chờ ô OTP đăng nhập để tự nhập mã.';
        } else if (result == 'draft-exists') {
          message =
              'Biểu mẫu đã có thông tin khác. Đã dừng để giữ nội dung của bạn.';
          break;
        } else if (result == 'verification-required') {
          message =
              'TikTok yêu cầu CAPTCHA hoặc mã xác minh. '
              'Hãy hoàn tất trên trang đăng nhập.';
          break;
        } else if (result == 'paste-failed') {
          message =
              'Không thể dán thông tin đăng nhập từ clipboard. '
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
        if (loginSucceeded && appActive && pageFailure == null) {
          mutate(() => autoWatchEnabled = true);
          await startAutoWatch();
        }
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
        accountFailure != null ||
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
    initialPageLoaded =
        pageFailure == null &&
        url?.scheme == 'https' &&
        url?.host == 'www.tiktok.com';
    await updateNavigationState();
    if (pageFailure != null) return;
    try {
      await webViewController?.evaluateJavascript(
        source: autoAcceptCookieScript,
      );
      await webViewController?.evaluateJavascript(
        source: autoSelectInterestScript,
      );
    } catch (_) {
      // A navigation can destroy the old document; the next document installs it again.
    }
    await injectAutoCloseCountryModal();
    unawaited(logBrowserIdentity());
    unawaited(checkProxyIp());
    await runInitialAction();
    await startAutoWatch();
  }

  Future<void> logBrowserIdentity() async {
    if (!kDebugMode || !initialPageLoaded) return;
    try {
      final agent = await webViewController?.evaluateJavascript(
        source:
            "location.origin === 'https://www.tiktok.com' ? navigator.userAgent : null",
      );
      if (!active || agent is! String) return;
      debugPrint('[WebView identity] User-Agent thực tế: $agent');
      debugPrint(
        '[WebView identity] Khớp cấu hình: ${agent == configuration.userAgent}',
      );
    } catch (_) {
      // A navigation may replace the document before this debug-only read.
    }
  }

  void showProxyWarning(WebViewFailure failure, {bool ipCheck = false}) {
    if (!active || configuration.proxy == null) return;
    if (ipCheck && proxyWarning != null && !proxyWarningIsIpCheck) return;
    mutate(() {
      proxyWarning = failure;
      proxyWarningIsIpCheck = ipCheck;
      if (!ipCheck) detectedIp = null;
    });
    notify(
      '${failure.title}\n${failure.message}',
      actionLabel: 'Thử lại',
      onAction: retryProxyWarning,
    );
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

  Future<void> onWebViewCreated(InAppWebViewController controller) async {
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
      handlerName: 'FlutterLoginSendCode',
      callback: clickLoginSendCode,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterLoginEmailVerification',
      callback: clickLoginEmailVerification,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterLoginPasswordContinue',
      callback: clickLoginPasswordContinue,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterLoginOtpContinue',
      callback: clickLoginOtpContinue,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterSignupPaste',
      callback: pasteSignupFromClipboard,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterSignupSendCode',
      callback: clickSignupSendCode,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterSignupPasswordSubmit',
      callback: clickSignupPasswordSubmit,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterSignupUsernameSkip',
      callback: clickSignupUsernameSkip,
    );
    controller.addJavaScriptHandler(
      handlerName: 'FlutterAutoWatch',
      callback: (args) {
        if (args.isNotEmpty) {
          handleAutoWatchMessage(args.first.toString());
        }
      },
    );
    if (needsAndroidDesktopIdentity) {
      try {
        await configureAndroidDesktopIdentity(
          controller,
          userAgent: configuration.userAgent,
        );
        if (!active) return;
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(initialUrl)),
        );
      } catch (_) {
        if (active) {
          showPageFailure(
            const WebViewFailure(
              'Không thể cấu hình Chrome desktop',
              'Hãy cập nhật Android System WebView rồi mở lại TikTok.',
            ),
          );
        }
      }
    }
  }

  Future<HttpAuthResponse?> onReceivedHttpAuthRequest(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    final proxy = configuration.proxy;
    // The Android plugin increments this counter before the first
    // callback (1); WebKit reports previous failures starting at 0.
    final firstChallengeCount = defaultTargetPlatform == TargetPlatform.android
        ? 1
        : 0;
    if (proxy == null ||
        challenge.protectionSpace.host != proxy.uri.host ||
        challenge is! HttpAuthenticationChallenge) {
      return null;
    }
    if (proxy.username.isEmpty ||
        challenge.previousFailureCount > firstChallengeCount) {
      showProxyWarning(
        proxy.username.isEmpty
            ? WebViewFailure.missingProxyAuth
            : WebViewFailure.proxyAuth,
      );
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
      accountFailure = null;
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
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    await handlePageLoadComplete(url);
  }

  void onConsoleMessage(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  ) {
    if (!active) return;
    final failure = TikTokAccountFailure.fromConsole(consoleMessage.message);
    if (failure != null) showAccountFailure(failure);
  }

  void showAccountFailure(TikTokAccountFailure failure) {
    if (!active ||
        (accountFailure != null &&
            accountFailure!.priority > failure.priority) ||
        accountFailure?.message == failure.message) {
      return;
    }
    // These backend errors also occur on a manual tap. Stop pending account
    // actions and mailbox requests, then show the reason without resizing the page.
    cancelAutoActions();
    mutate(() => accountFailure = failure);
    notify(
      '${failure.title}\n${failure.message}',
      duration: const Duration(seconds: 6),
      actionLabel: 'Cấu hình',
      onAction: onReturnToConfiguration,
    );
    debugPrint('[TikTok account] ${failure.title}: ${failure.message}');
  }

  void onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (error.description.contains('net::ERR_ABORTED') ||
        error.type == WebResourceErrorType.CANCELLED) {
      return;
    }
    final failure = WebViewFailure.network(
      error,
      usingProxy: configuration.proxy != null,
    );
    if (request.isForMainFrame == false) {
      if (failure.isConnectionFailure) {
        showProxyWarning(failure);
      }
      return;
    }
    final authFailure =
        proxyWarning == WebViewFailure.proxyAuth ||
        proxyWarning == WebViewFailure.missingProxyAuth;
    showPageFailure(authFailure ? proxyWarning! : failure);
  }

  void onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
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
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url.toString();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  void goHome() {
    cancelAutoActions();
    unawaited(
      webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(tiktokHomeUrl)),
      ),
    );
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
