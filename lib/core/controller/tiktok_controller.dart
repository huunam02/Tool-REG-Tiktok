import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../scripts/auto_login_script.dart';
import '../scripts/rotate_captcha_script.dart';
import '../rotate_captcha.dart';
import '../captcha_settings_store.dart';
import '../scripts/authenticated_session_script.dart';
import '../scripts/auto_logout_script.dart';
import '../send_code_accessibility.dart';
import '../cookie_consent_accessibility.dart';
import '../signup_accessibility.dart';
import '../signup_birthday_menu.dart';
import '../signup_coordinate_runner.dart';
import '../login_accessibility_runner.dart';
import '../login_coordinate_profile.dart';
import '../nurture_accessibility_runner.dart';
import '../nurture_coordinate_profile.dart';
import '../scripts/auto_cookie_script.dart';
import '../scripts/auto_interest_script.dart';
import '../scripts/auto_signup_script.dart';
import '../scripts/auto_watch_script.dart';
import '../scripts/manual_viewing_script.dart';
import '../manual_viewing_session.dart';
import '../nurture_data.dart';
import '../nurture_store.dart';
import '../scripts/country_modal_script.dart';
import '../webview_proxy_ip.dart';
import '../webview_user_agent.dart';
import '../webview_timezone.dart';
import '../app_configuration.dart';
import '../account_sessions.dart';
import '../app_session.dart';
import '../otp_api.dart';
import '../proxy_store.dart';
import '../webview_failure.dart';
import '../webview_locale.dart';
import '../tiktok_launch_action.dart';
import '../tiktok_flow_result.dart';
import '../tiktok_account_failure.dart';
import 'app_controller.dart';

class TikTokController extends AppController with WidgetsBindingObserver {
  TikTokController({
    required this.configuration,
    this.launchAction = TikTokLaunchAction.browse,
    this.startWithNurture = false,
    this.startWithBrowserCheck = false,
    this.startWithIpCheck = false,
    bool useNativeWebView = false,
    this.useInstalledEngine = true,
    this.manualViewingPlan,
    this.nurtureRepository,
    this.otpReaderFactory,
    this.loginProfileLoader,
    this.nurtureProfileLoader,
    this.rotateCaptchaSolverFactory,
    this.onReturnToConfiguration,
    this.onFlowFinished,
    this.logoutAfterNurture = false,
    this.autoAdvance = false,
    Random? workflowRandom,
    ProxyStore? proxyStore,
    CaptchaSettingsStore? captchaSettingsStore,
    bool? useAccessibility,
    DateTime Function()? now,
  }) : useNativeWebView = useNativeWebView || manualViewingPlan != null,
       proxyStore = proxyStore ?? ProxyStore.instance,
       captchaSettingsStore =
           captchaSettingsStore ?? CaptchaSettingsStore.instance,
       _workflowRandom = workflowRandom ?? Random(),
       _now = now ?? DateTime.now,
       _accessibilityOverride = useAccessibility,
       browserCheckOpen = startWithBrowserCheck || startWithIpCheck;

  final AppConfiguration configuration;
  final ProxyStore proxyStore;
  final CaptchaSettingsStore captchaSettingsStore;
  final ValueChanged<TikTokFlowResult>? onFlowFinished;
  final Random _workflowRandom;
  Timer? _signupLogoutTimer;
  DateTime? signupLogoutAt;
  bool logoutBusy = false;
  bool get waitingToLogout => signupLogoutAt != null;
  bool _signupHandoffStarted = false;
  bool _flowFinished = false;
  bool _watchCompletionPending = false;
  bool _finishingWatch = false;
  int _workflowGeneration = 0;

  /// Log out after nurturing instead of keeping the session (auto runs).
  final bool logoutAfterNurture;

  /// Part of an automatic run over several configurations: a failed or stuck
  /// flow returns [TikTokFlowResult.failed] so Home can continue.
  final bool autoAdvance;
  static const autoFailureDelay = Duration(seconds: 15);
  static const autoFlowTimeout = Duration(minutes: 15);

  /// A long configured nurture session extends the watchdog accordingly.
  Duration get _autoFlowTimeout {
    final needed =
        configuration.nurtureSettings.maxDuration + const Duration(minutes: 12);
    return needed > autoFlowTimeout ? needed : autoFlowTimeout;
  }

  Timer? _autoFailTimer;
  Timer? _autoFlowWatchdog;
  bool _stoppedByUser = false;
  TikTokFlowResult _logoutResult = TikTokFlowResult.signupLoggedOut;

  bool get logoutFollowsNurture =>
      _logoutResult == TikTokFlowResult.nurtureLoggedOut;

  /// Explicit callers may request logout; normal signup/nurture keeps the jar.
  bool get _logsOutAfterNurture => onFlowFinished != null && logoutAfterNurture;

  /// Before logging out, the screen is held for a random 1–2 minutes.
  Duration _logoutHold() => Duration(seconds: 60 + _workflowRandom.nextInt(61));

  void _afterSignupSucceeded() {
    // A route owns the handoff to Home and the next configuration.
    if (onFlowFinished == null ||
        _signupHandoffStarted ||
        !active ||
        configuration.configurationId == null) {
      return;
    }
    if (configuration.configurationId != null && !_registrationSaved) {
      _failAutoFlow();
      return;
    }
    _signupHandoffStarted = true;
    if (configuration.nurtureAfterSignup) {
      unawaited(_nurtureAfterSignup());
    } else {
      unawaited(_finishSignupWithSession());
    }
  }

  Future<void> _finishSignupWithSession() async {
    await _persistCurrentAccountLoginState(true);
    if (!active || _flowFinished) return;
    _flowFinished = true;
    _autoFlowWatchdog?.cancel();
    onFlowFinished?.call(TikTokFlowResult.signupCompleted);
  }

  /// Warm up the new account for the configured time in the session that
  /// created it.
  Future<void> _nurtureAfterSignup() async {
    mutate(() => loginConfirmed = true);
    await _persistCurrentAccountLoginState(true);
    if (!active || pageFailure != null || accountFailure != null) return;
    final settings = configuration.nurtureSettings;
    final minutes = settings.minMinutes == settings.maxMinutes
        ? '${settings.minMinutes}'
        : '${settings.minMinutes}–${settings.maxMinutes}';
    notify(
      'Đăng ký xong. Đang nuôi tài khoản mới $minutes phút.',
      duration: const Duration(seconds: 3),
    );
    await _startTimedAutoWatch();
  }

  void _scheduleLogout(TikTokFlowResult result) {
    if (onFlowFinished == null ||
        _flowFinished ||
        waitingToLogout ||
        logoutBusy ||
        !active) {
      return;
    }
    _logoutResult = result;
    final hold = _logoutHold();
    mutate(() => signupLogoutAt = _now().add(hold));
    _signupLogoutTimer = Timer(hold, _continueSignupLogout);
  }

  /// Leave this configuration after a short notice so the run can continue.
  void _failAutoFlow({String? reason}) {
    if (!autoAdvance ||
        _stoppedByUser ||
        _flowFinished ||
        !active ||
        _autoFailTimer != null) {
      return;
    }
    if (launchAction == TikTokLaunchAction.signup && !_registrationSaved) {
      unawaited(_recordSignupFailure(reason ?? _lastNotice));
    }
    _autoFailTimer = Timer(autoFailureDelay, () {
      if (!active || _flowFinished || _stoppedByUser) return;
      _flowFinished = true;
      _autoFlowWatchdog?.cancel();
      onFlowFinished?.call(TikTokFlowResult.failed);
    });
    mutate(() => autoRunFailing = true);
  }

  /// Shown while a failed automatic flow waits to move on.
  bool autoRunFailing = false;

  /// The latest message shown on this screen: usually why a flow stopped.
  String? _lastNotice;

  @override
  void notify(
    String message, {
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _lastNotice = message;
    super.notify(
      message,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Keep the reason in the configuration's signup log (Cấu hình lỗi tab).
  Future<void> _recordSignupFailure(String? reason) async {
    final id = configuration.configurationId;
    if (id == null) return;
    try {
      await proxyStore.recordSignupFailure(
        id,
        configuration.signupEmail,
        message: reason ?? 'Không rõ nguyên nhân.',
        step: signupStatus,
      );
    } catch (_) {
      debugPrint('Could not record the signup failure.');
    }
  }

  bool get _flowContinues =>
      _flowFinished ||
      _signupHandoffStarted ||
      waitingToLogout ||
      logoutBusy ||
      autoWatchEnabled ||
      _watchCompletionPending ||
      autoSignupBusy ||
      autoLoginBusy;

  /// The person takes over this screen; an automatic run stops advancing.
  void stopByUser() {
    _userTookOver();
    cancelAutoActions();
  }

  void _userTookOver() {
    _stoppedByUser = true;
    _autoFlowWatchdog?.cancel();
    _cancelAutoFailure();
  }

  void _cancelAutoFailure() {
    _autoFailTimer?.cancel();
    _autoFailTimer = null;
    if (autoRunFailing) mutate(() => autoRunFailing = false);
  }

  void cancelSignupHandoff() {
    _workflowGeneration++;
    _signupLogoutTimer?.cancel();
    _signupLogoutTimer = null;
    signupLogoutAt = null;
    logoutBusy = false;
    mutate(() {});
  }

  void _continueSignupLogout() {
    if (!active ||
        !appActive ||
        logoutBusy ||
        !waitingToLogout ||
        _now().isBefore(signupLogoutAt!) ||
        autoSignupBusy ||
        autoLoginBusy ||
        pageFailure != null ||
        accountFailure != null ||
        browserCheckOpen) {
      return;
    }
    unawaited(_logoutAfterSignup());
  }

  Future<void> _logoutAfterSignup() async {
    final generation = _workflowGeneration;
    bool current() =>
        active && generation == _workflowGeneration && waitingToLogout;
    mutate(() => logoutBusy = true);
    final deadline = _now().add(const Duration(seconds: 45));
    var confirmations = 0;
    try {
      await stopAutoWatch();
      while (current() && appActive && _now().isBefore(deadline)) {
        final url = await webViewController?.getUrl();
        if (!current() || !appActive) return;
        if (url == null) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        if (url.scheme != 'https' || url.host != 'www.tiktok.com') {
          throw StateError('Logout left TikTok');
        }
        await _checkRotateCaptcha();
        if (!current() || !appActive) return;
        dynamic result;
        try {
          result = await webViewController?.evaluateJavascript(
            source: buildAutoLogoutScript(generation),
          );
        } catch (_) {
          // Logout can replace the page and briefly destroy its JS context.
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        if (!current() || !appActive) return;
        if (result == 'wrong-origin' || result == 'verification-required') {
          throw StateError('Logout requires attention');
        }
        confirmations = result == 'logged-out' ? confirmations + 1 : 0;
        if (confirmations >= 2) {
          _signupLogoutTimer?.cancel();
          _signupLogoutTimer = null;
          mutate(() {
            signupLogoutAt = null;
            logoutBusy = false;
            loginConfirmed = false;
          });
          await _persistCurrentAccountLoginState(false);
          if (!active || generation != _workflowGeneration) return;
          if (!_flowFinished) {
            _flowFinished = true;
            _autoFlowWatchdog?.cancel();
            onFlowFinished?.call(_logoutResult);
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (current() && appActive) {
        throw StateError('Logout confirmation timed out');
      }
    } catch (_) {
      if (current()) {
        cancelSignupHandoff();
        notify(
          'Chưa xác nhận được đăng xuất TikTok. Đã dừng lịch đăng nhập lại; hãy kiểm tra màn hiện tại.',
        );
        _failAutoFlow();
      }
    } finally {
      if (current()) mutate(() => logoutBusy = false);
    }
  }

  bool _registrationSaved = false;
  Future<void>? _registrationWrite;

  Future<void> _markConfigurationRegistered() async {
    final id = configuration.configurationId;
    if (id == null || _registrationSaved) return;
    final pending = _registrationWrite;
    if (pending != null) return pending;
    final write = _saveRegisteredConfiguration(id);
    _registrationWrite = write;
    try {
      await write;
    } finally {
      _registrationWrite = null;
    }
  }

  Future<void> _saveRegisteredConfiguration(int id) async {
    try {
      final saved = await proxyStore.markRegistered(
        id,
        configuration.signupEmail,
      );
      if (!saved) throw StateError('Signup configuration changed or removed');
      _registrationSaved = true;
    } catch (_) {
      if (active) {
        notify(
          'Đã đăng ký nhưng chưa lưu được trạng thái cấu hình. Hãy bật Đã đăng ký trong Quản lý cấu hình.',
        );
      }
    }
  }

  final TikTokLaunchAction launchAction;
  final bool startWithNurture;
  final bool startWithBrowserCheck;
  final bool startWithIpCheck;
  // Manual-only mode is independent of the browser identity used by automation.
  final bool useNativeWebView;
  final bool useInstalledEngine;
  final NurturePlan? manualViewingPlan;
  final NurtureRepository? nurtureRepository;
  ManualViewingSession? _manualSession;
  ManualViewingSession? _autoViewingSession;

  /// Chosen once per TikTok screen: the For You feed or one random keyword,
  /// so each nurture run's mode is unpredictable.
  late final NurturePlan _nurturePlan = NurturePlan.choose(
    configuration.searchKeywords,
  );
  int? _autoViewingNavigation;
  String? _autoViewingSegment;
  Future<void> _autoWatchOperations = Future.value();
  NurtureAccessibilityRunner? _accessibilityNurture;
  int? _accessibilityNurtureNavigation;
  int? _manualNavigation;
  bool manualViewingClosed = false;
  Future<void>? _manualClose;
  bool get manualViewingClosing => _manualClose != null;
  bool get usesEngineIdentity =>
      needsAndroidDesktopIdentity && useInstalledEngine;
  String? _effectiveUserAgent;
  String get effectiveUserAgent =>
      _effectiveUserAgent ?? configuration.userAgent;
  bool get needsDesktopIdentity => needsAndroidDesktopIdentity;
  Map<String, String>? get navigationHeaders =>
      useNativeWebView ? null : englishWebViewHeaders;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;
  final Future<LoginCoordinateProfile> Function()? loginProfileLoader;
  final Future<NurtureCoordinateProfile> Function()? nurtureProfileLoader;
  final RotateCaptchaSolver Function()? rotateCaptchaSolverFactory;
  final VoidCallback? onReturnToConfiguration;
  final DateTime Function() _now;
  final bool? _accessibilityOverride;
  String get initialUrl => startWithBrowserCheck
      ? browserCheckUrl
      : startWithIpCheck
      ? ipCheckUrl
      : manualViewingPlan?.initialUrl ?? launchAction.initialUrl;
  static const browserCheckUrl = 'https://www.whatismybrowser.com/';
  static const ipCheckUrl = 'https://www.whatismyip.com/';
  bool browserCheckOpen;
  bool browserIdentityReady = false;

  static const commentInputChannel = MethodChannel('test_tiktok/comment_input');
  bool get _usesKeyboardInput =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get usesCoordinateSignup =>
      _usesKeyboardInput &&
      launchAction == TikTokLaunchAction.signup &&
      !useNativeWebView;
  bool get usesAccessibilityLogin =>
      _usesKeyboardInput && _usesAccessibility && !useNativeWebView;
  bool get usesAccessibilityAccountFlow =>
      usesCoordinateSignup || usesAccessibilityLogin;

  /// Width of the 1:2 frame in dp; fixes the page scale to the frame, which
  /// is narrower than the screen on 16:9 phones, tablets and foldables.
  double? signupViewportWidth;
  late final signupAccessibility = SignupAccessibility(
    beforeSnapshot: _checkRotateCaptcha,
    beforeAction: _beforeAccessibilityAction,
  );
  Future<void>? _rotateCaptchaWork;
  RotateCaptchaSolver? _rotateCaptchaSolver;
  Timer? _rotateCaptchaPollTimer;
  bool _rotateCaptchaMonitorRunning = false;
  bool _captchaSettingsReady = false, _captchaSettingsSubscribed = false;
  bool _tikTokScreenVisible = true;
  int _rotateCaptchaEpoch = 0, _nurtureActionEpoch = 0;
  RotateCaptchaChallenge? _failedRotateCaptcha;
  String? _rotateCaptchaFailure, _rotateCaptchaFailureKey, _rotateCaptchaNotice;

  bool get _canCheckRotateCaptcha =>
      active &&
      appActive &&
      _tikTokScreenVisible &&
      autoWatchEnabled &&
      !useNativeWebView &&
      !manualViewingClosed &&
      !browserCheckOpen &&
      pageFailure == null &&
      webViewController != null &&
      _usesAccessibility &&
      _captchaSettingsReady &&
      _captchaKey.isNotEmpty;

  void setTikTokScreenVisible(bool visible) {
    if (_tikTokScreenVisible == visible) return;
    _tikTokScreenVisible = visible;
    if (visible) {
      _startRotateCaptchaMonitor();
    } else {
      _stopRotateCaptchaMonitor();
    }
  }

  // Poll across TikTok routes only while the nurture run is enabled.
  void _startRotateCaptchaMonitor() {
    if (_rotateCaptchaMonitorRunning || !_canCheckRotateCaptcha) return;
    _rotateCaptchaMonitorRunning = true;
    final epoch = _rotateCaptchaEpoch;
    bool current() =>
        _rotateCaptchaMonitorRunning &&
        epoch == _rotateCaptchaEpoch &&
        _canCheckRotateCaptcha;
    void schedule() {
      _rotateCaptchaPollTimer = Timer(const Duration(seconds: 1), () async {
        _rotateCaptchaPollTimer = null;
        if (!current()) return;
        try {
          if (!signupAccessibility.actionBusy) await _checkRotateCaptcha();
        } on RotateCaptchaCancelled {
          // Navigation, route changes and backgrounding invalidate old work.
        } catch (error) {
          if (!current()) return;
          if (autoLoginBusy) cancelAutoLogin();
          if (autoSignupBusy) cancelAutoSignup();
          if (autoWatchEnabled) {
            _cancelAutoWatchTimers();
            mutate(() => autoWatchEnabled = false);
            unawaited(stopAutoWatch());
          }
          final message = error is StateError
              ? error.message.toString()
              : 'Không xử lý được CAPTCHA. Hãy kiểm tra màn hiện tại.';
          if (_rotateCaptchaNotice != message) {
            _rotateCaptchaNotice = message;
            notify(message);
          }
        }
        if (current()) schedule();
      });
    }

    schedule();
  }

  void _clearRotateCaptchaFailure() {
    _failedRotateCaptcha = null;
    _rotateCaptchaFailure = null;
    _rotateCaptchaFailureKey = null;
    _rotateCaptchaNotice = null;
  }

  void _stopRotateCaptchaMonitor() {
    _rotateCaptchaMonitorRunning = false;
    _rotateCaptchaEpoch++;
    _rotateCaptchaPollTimer?.cancel();
    _rotateCaptchaPollTimer = null;
    _rotateCaptchaSolver?.close();
    _clearRotateCaptchaFailure();
  }

  String get _captchaKey => captchaSettingsStore.effectiveLicenseKey;

  void _captchaSettingsChanged() {
    if (!_captchaSettingsSubscribed || !active) return;
    _captchaSettingsReady = captchaSettingsStore.loaded;
    _stopRotateCaptchaMonitor();
    _startRotateCaptchaMonitor();
  }

  Future<void> _loadCaptchaSettings() async {
    try {
      await captchaSettingsStore.load();
    } catch (_) {
      // Keep the current Remote Config values if settings cannot be loaded.
    }
    if (_captchaSettingsSubscribed && active) {
      _captchaSettingsReady = true;
      _startRotateCaptchaMonitor();
    }
  }

  // Hookless instance: a cookie check must not trigger the CAPTCHA hooks.
  late final _cookieConsent = CookieConsentAccessibility(
    accessibility: SignupAccessibility(),
    now: _now,
  );
  Timer? _cookieConsentTimer;

  /// The JS auto-accept is off in Accessibility mode, so the banner is
  /// accepted with a gesture while no signup/login runner is acting (both
  /// accept it themselves) and no other Accessibility action is in flight.
  void _startCookieConsentMonitor() {
    if (_cookieConsentTimer != null || !active) return;
    _cookieConsentTimer = Timer(const Duration(seconds: 2), () async {
      try {
        if (active &&
            appActive &&
            _tikTokScreenVisible &&
            initialPageLoaded &&
            pageFailure == null &&
            !browserCheckOpen &&
            !autoSignupBusy &&
            !autoLoginBusy &&
            !logoutBusy &&
            _rotateCaptchaWork == null &&
            !signupAccessibility.actionBusy &&
            await _cookieConsent.check()) {
          debugPrint('[Cookie] Tapped Allow all.');
        }
      } catch (error) {
        debugPrint('[Cookie] Check failed (${error.runtimeType}).');
      } finally {
        _cookieConsentTimer = null;
        if (active) _startCookieConsentMonitor();
      }
    });
  }

  Future<void> _beforeAccessibilityAction() async {
    final signup = autoSignupBusy,
        login = autoLoginBusy,
        watch = autoWatchEnabled;
    final signupAttempt = autoSignupAttempt, loginAttempt = autoLoginAttempt;
    final watchEpoch = _nurtureActionEpoch;
    await _checkRotateCaptcha();
    // A queued action must still belong to the same active attempt after
    // waiting for CAPTCHA handling.
    if (!active ||
        !appActive ||
        !_tikTokScreenVisible ||
        signup && (!autoSignupBusy || signupAttempt != autoSignupAttempt) ||
        login && (!autoLoginBusy || loginAttempt != autoLoginAttempt) ||
        watch && (!autoWatchEnabled || watchEpoch != _nurtureActionEpoch)) {
      throw RotateCaptchaCancelled();
    }
  }

  Future<void> _checkRotateCaptcha() async {
    if (!_canCheckRotateCaptcha) return;
    final pending = _rotateCaptchaWork;
    if (pending != null) return pending;
    final work = _inspectRotateCaptcha();
    _rotateCaptchaWork = work;
    try {
      await work;
    } finally {
      if (identical(_rotateCaptchaWork, work)) _rotateCaptchaWork = null;
    }
  }

  Future<void> _inspectRotateCaptcha() async {
    final controller = webViewController!;
    final navigation = navigationId, epoch = _rotateCaptchaEpoch;
    bool current() =>
        _canCheckRotateCaptcha &&
        navigationId == navigation &&
        _rotateCaptchaEpoch == epoch;
    final url = await controller.getUrl();
    if (!current() || url?.scheme != 'https' || url?.host != 'www.tiktok.com') {
      return;
    }
    Future<void> guard() async {
      if (!current()) throw RotateCaptchaCancelled();
      final url = await controller.getUrl();
      if (!current() ||
          url?.scheme != 'https' ||
          url?.host != 'www.tiktok.com') {
        throw RotateCaptchaCancelled();
      }
    }

    Future<RotateCaptchaChallenge?> read() async =>
        RotateCaptchaChallenge.fromResult(
          await controller.evaluateJavascript(source: readRotateCaptchaScript),
        );
    Future<bool> isPresent() async =>
        await controller.evaluateJavascript(
          source: rotateCaptchaPresentScript,
        ) !=
        false;
    var challenge = await read();
    await guard();
    if (challenge == null && !await isPresent()) {
      await guard();
      _clearRotateCaptchaFailure();
      return;
    }
    await guard();
    final key = _captchaKey;
    final failed = _failedRotateCaptcha;
    if (_rotateCaptchaFailure != null &&
        _rotateCaptchaFailureKey == key &&
        (challenge == null && failed == null ||
            challenge != null &&
                failed != null &&
                challenge.outer == failed.outer &&
                challenge.inner == failed.inner)) {
      throw StateError(_rotateCaptchaFailure!);
    }
    _clearRotateCaptchaFailure();
    RotateCaptchaSolver? solver;
    try {
      if (!await FlutterAccessibilityService.isAccessibilityPermissionEnabled()) {
        throw StateError('Bật Trợ năng cho Tool TikTok để tự xử lý CAPTCHA.');
      }
      await guard();
      solver = rotateCaptchaSolverFactory?.call() ?? RotateCaptchaSolver();
      _rotateCaptchaSolver = solver;
      await solver.solve(
        licenseKey: key,
        guard: guard,
        read: () async {
          final value = await read();
          if (value != null) challenge = value;
          return value;
        },
        isPresent: isPresent,
        accessibility: SignupAccessibility(), // No recursive hooks.
        // A wrong answer is retried on a new puzzle before giving up.
        refresh: () => refreshRotateCaptcha(
          accessibility: SignupAccessibility(),
          readGeometry: () =>
              controller.evaluateJavascript(source: rotateCaptchaRefreshScript),
          guard: guard,
        ),
        onStatus: (status) {
          if (current()) {
            mutate(() {
              if (autoSignupBusy) signupStatus = status;
              if (autoLoginBusy) loginStatus = status;
            });
          }
        },
      );
      await guard();
    } on RotateCaptchaCancelled {
      rethrow;
    } catch (error) {
      if (!current()) throw RotateCaptchaCancelled();
      final message = error is StateError
          ? error.message.toString()
          : 'Không xử lý được CAPTCHA xoay. Hãy kiểm tra API key, mạng và màn hiện tại.';
      _failedRotateCaptcha = challenge;
      _rotateCaptchaFailure = message;
      _rotateCaptchaFailureKey = key;
      throw StateError(message);
    } finally {
      if (identical(_rotateCaptchaSolver, solver)) _rotateCaptchaSolver = null;
    }
  }

  SignupCoordinateRunner? _signupCoordinateRunner;
  LoginAccessibilityRunner? _loginAccessibilityRunner;
  static const _signupCalibrationChannel = MethodChannel(
    'test_tiktok/signup_calibration',
  );
  // Android investigation: restore button gestures and enter fields manually.
  static const _pauseSignupGestures = false;
  bool get _manualSignupButtonTaps =>
      _pauseSignupGestures && _usesKeyboardInput;
  // Set to false to restore native field input and signup OTP API handling.
  static const _pauseSignupFieldInput = true;
  bool get _manualSignupFieldInput =>
      _pauseSignupFieldInput && _usesKeyboardInput;
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
  String loginStatus = 'Đang đăng nhập tự động…';
  // Confirmed by automatic login or by a session check on a manual start.
  bool loginConfirmed = false;

  Future<void> _persistCurrentAccountLoginState(bool loggedIn) async {
    final id = configuration.configurationId;
    final email = configuration.loginUsername.trim().isEmpty
        ? configuration.signupEmail
        : configuration.loginUsername;
    if (id == null || email.trim().isEmpty) return;
    try {
      final selected = await proxyStore.setCurrentAccountLoggedIn(
        id,
        email,
        loggedIn,
      );
      if (selected) await AccountSessions.save(id, email);
    } catch (_) {
      // Session persistence must not interrupt browser controls.
    }
  }

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

  /// Each nurture session lasts a random time within the configured range
  /// (2–3 minutes by default).
  Duration get minNurtureDuration => configuration.nurtureSettings.minDuration;
  Duration get maxNurtureDuration => configuration.nurtureSettings.maxDuration;
  Timer? _autoWatchStopTimer;
  DateTime? _autoWatchStopsAt;
  bool appActive = true;
  late final List<String> comments;
  bool inputBusy = false;

  @override
  void onInit() {
    super.onInit();
    comments = configuration.comments;
    _captchaSettingsSubscribed = true;
    _captchaSettingsReady = captchaSettingsStore.loaded;
    captchaSettingsStore.addListener(_captchaSettingsChanged);
    if (!_captchaSettingsReady) unawaited(_loadCaptchaSettings());
    final plan = manualViewingPlan;
    final repository = nurtureRepository;
    if (plan != null &&
        repository != null &&
        configuration.loginUsername.trim().isNotEmpty) {
      _manualSession = ManualViewingSession(
        repository: repository,
        email: configuration.loginUsername,
        configurationId: configuration.configurationId,
        plan: plan,
        onError: () => notify(
          'Không thể lưu thống kê phiên xem. Hãy kiểm tra bộ nhớ rồi thử lại.',
        ),
      );
    }
    if (autoAdvance && onFlowFinished != null) {
      final timeout = _autoFlowTimeout;
      _autoFlowWatchdog = Timer(timeout, () {
        if (!active || _flowFinished || _stoppedByUser) return;
        notify('Quá ${timeout.inMinutes} phút chưa xong cấu hình này.');
        _failAutoFlow();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    _autoFlowWatchdog?.cancel();
    _autoFailTimer?.cancel();
    _captchaSettingsSubscribed = false;
    captchaSettingsStore.removeListener(_captchaSettingsChanged);
    _stopRotateCaptchaMonitor();
    _cookieConsentTimer?.cancel();
    _cookieConsentTimer = null;
    _accessibilityNurture?.cancel();
    if (usesAccessibilityAccountFlow) {
      _signupCalibrationChannel.setMethodCallHandler(null);
    }
    unawaited(closeManualViewing());
    cancelSignupHandoff();
    _cancelAutoWatchTimers();
    unawaited(_sendCodeAccessibility?.dispose());
    _ipChecker?.cancel();
    cancelAutoLogin(updateUi: false);
    cancelAutoSignup(updateUi: false);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeAutoViewing());
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    if (!appActive) {
      _stopRotateCaptchaMonitor();
    } else {
      _startRotateCaptchaMonitor();
    }
    if (manualViewingPlan != null) {
      unawaited(_updateManualForeground());
      return;
    }
    if (!appActive && autoLoginBusy) cancelAutoLogin();
    if (!appActive && autoSignupBusy) cancelAutoSignup();
    if (appActive) {
      if (_watchCompletionPending) {
        unawaited(_returnAfterNurture());
        return;
      }
      _continueSignupLogout();
      unawaited(runInitialAction());
    }
    if (autoWatchEnabled && appActive) {
      unawaited(startAutoWatch());
    } else {
      unawaited(stopAutoWatch());
    }
  }

  Future<void> startAutoWatch() => _autoWatchOperations = _autoWatchOperations
      .then((_) => _startAutoWatch());

  Future<void> _startAutoWatch() async {
    if (useNativeWebView) return;
    final stopsAt = _autoWatchStopsAt;
    if (stopsAt != null && !_now().isBefore(stopsAt)) {
      _finishTimedAutoWatch();
      return;
    }
    if (!active ||
        !loginConfirmed ||
        browserCheckOpen ||
        !autoWatchEnabled ||
        !appActive ||
        pageFailure != null) {
      return;
    }
    _startRotateCaptchaMonitor();
    final navigation = navigationId;
    try {
      await _startAutoViewingStats();
      if (!active ||
          !autoWatchEnabled ||
          !appActive ||
          navigation != navigationId) {
        await _stopAutoWatch();
        return;
      }
      if (usesAccessibilityLogin) {
        if (_accessibilityNurtureNavigation != navigation) {
          await _accessibilityNurture?.stop();
          final profile =
              await (nurtureProfileLoader?.call() ??
                  NurtureCoordinateProfile.load());
          if (!active ||
              !appActive ||
              !autoWatchEnabled ||
              navigation != navigationId) {
            return;
          }
          final session = _autoViewingSession;
          final segment = _autoViewingSegment;
          _accessibilityNurtureNavigation = navigation;
          _accessibilityNurture = NurtureAccessibilityRunner(
            accessibility: signupAccessibility,
            profile: profile,
            comments: comments,
            likeRate: configuration.nurtureSettings.likeRate,
            commentRate: configuration.nurtureSettings.commentRate,
            longWatchRate: configuration.nurtureSettings.longWatchRate,
            isActive: () =>
                active &&
                appActive &&
                autoWatchEnabled &&
                navigation == navigationId &&
                pageFailure == null &&
                !browserCheckOpen &&
                (_autoWatchStopsAt == null ||
                    _now().isBefore(_autoWatchStopsAt!)),
            isTikTok: () async {
              final url = await webViewController?.getUrl();
              return url?.scheme == 'https' && url?.host == 'www.tiktok.com';
            },
            onProgress: (totals, sequence) async {
              if (session != null && segment != null) {
                await session.accept({
                  'session': session.id,
                  'segment': segment,
                  'sequence': sequence,
                  ...totals.toMap(),
                });
              }
            },
            onComment: () => notify(
              'Đã gửi bình luận.',
              duration: const Duration(seconds: 2),
            ),
            onCommentSkipped: (message) =>
                notify(message, duration: const Duration(seconds: 2)),
            onLike: () =>
                notify('Đã thả tim.', duration: const Duration(seconds: 2)),
            onLikeSkipped: (message) =>
                notify(message, duration: const Duration(seconds: 2)),
            // A restart after an error falls back to the For You feed.
            searchKeyword:
                _nurturePlan.mode == NurtureMode.search && _nurtureRestarts == 0
                ? _nurturePlan.keyword
                : null,
            now: _now,
          );
        }
        final runner = _accessibilityNurture!;
        unawaited(
          runner.start().catchError((Object error) {
            if (!active || !autoWatchEnabled || navigation != navigationId) {
              return;
            }
            final message = error is StateError
                ? error.message.toString()
                : 'Không thể tiếp tục nuôi qua Accessibility.';
            debugPrint('Accessibility nurture stopped: $message');
            notify(message);
            if (_logsOutAfterNurture) {
              final stopsAt = _autoWatchStopsAt;
              if (_nurtureRestarts < maxNurtureRestarts &&
                  stopsAt != null &&
                  stopsAt.difference(_now()) > const Duration(seconds: 30)) {
                _nurtureRestarts++;
                unawaited(_restartNurture());
                return;
              }
              // The account is already signed in: end the session cleanly.
              _finishTimedAutoWatch();
              return;
            }
            _cancelAutoWatchTimers();
            mutate(() => autoWatchEnabled = false);
            unawaited(stopAutoWatch());
          }),
        );
        return;
      }
      final result = await webViewController?.evaluateJavascript(
        source: buildAutoWatchScript(comments),
      );
      if (result != true) throw StateError('Video watcher did not start');
      // The app may have been paused or the toggle disabled during injection.
      if (!active || !autoWatchEnabled || !appActive) {
        await _stopAutoWatch();
      }
    } catch (_) {
      if (!active || !autoWatchEnabled) return;
      _cancelAutoWatchTimers();
      mutate(() => autoWatchEnabled = false);
      await _stopAutoWatch();
      notify('Không thể bật tự động xem. Hãy thử tải lại TikTok.');
    }
  }

  /// Automatic sessions reopen the feed after a nurture error this many times.
  static const maxNurtureRestarts = 2;
  int _nurtureRestarts = 0;

  /// Reload TikTok Home; the page load starts a fresh nurture runner within
  /// the same deadline.
  Future<void> _restartNurture() async {
    await stopAutoWatch();
    if (!active || !autoWatchEnabled) return;
    _accessibilityNurtureNavigation = null;
    try {
      await webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(tiktokHomeUrl),
          headers: navigationHeaders,
        ),
      );
    } catch (_) {
      if (active && autoWatchEnabled) _finishTimedAutoWatch();
    }
  }

  void _cancelAutoWatchTimers() {
    _stopRotateCaptchaMonitor();
    _nurtureActionEpoch++;
    _autoWatchStopTimer?.cancel();
    _autoWatchStopTimer = null;
    _autoWatchStopsAt = null;
  }

  void _finishTimedAutoWatch() {
    _cancelAutoWatchTimers();
    if (!active || !autoWatchEnabled) return;
    mutate(() => autoWatchEnabled = false);
    _watchCompletionPending = true;
    unawaited(_returnAfterNurture());
  }

  Future<void> _returnAfterNurture() async {
    if (_finishingWatch || !active || !_watchCompletionPending) return;
    _finishingWatch = true;
    try {
      // Stop page automation, retaining TikTok cookies and the login session.
      await stopAutoWatch(finishViewing: true);
      await _autoViewingSession?.finish(completed: true);
      _autoViewingSession = null;
      if (!active || !appActive) return;
      _watchCompletionPending = false;
      if (_logsOutAfterNurture) {
        notify(
          'Đã nuôi xong. Giữ màn hình 1–2 phút rồi đăng xuất.',
          duration: const Duration(seconds: 3),
        );
        _scheduleLogout(TikTokFlowResult.nurtureLoggedOut);
        return;
      }
      if (onFlowFinished != null && !_flowFinished) {
        _flowFinished = true;
        onFlowFinished!(TikTokFlowResult.nurtureCompleted);
      } else {
        notify('Đã nuôi xong.');
      }
    } finally {
      _finishingWatch = false;
    }
  }

  Future<void> _startTimedAutoWatch() async {
    if (!loginConfirmed) return;
    _cancelAutoWatchTimers();
    // Keep one deadline across document reloads and app background/resume.
    final duration =
        minNurtureDuration +
        Duration(
          seconds: _workflowRandom.nextInt(
            (maxNurtureDuration - minNurtureDuration).inSeconds + 1,
          ),
        );
    _autoWatchStopsAt = _now().add(duration);
    _autoWatchStopTimer = Timer(duration, _finishTimedAutoWatch);
    mutate(() => autoWatchEnabled = true);
    await startAutoWatch();
  }

  Future<void> stopAutoWatch({bool finishViewing = false}) =>
      _autoWatchOperations = _autoWatchOperations.then(
        (_) => _stopAutoWatch(finishViewing: finishViewing),
      );

  Future<void> _stopAutoWatch({bool finishViewing = false}) async {
    _stopRotateCaptchaMonitor();
    if (useNativeWebView) return;
    if (usesAccessibilityLogin) {
      await _accessibilityNurture?.stop();
      if (finishViewing) {
        _accessibilityNurture = null;
        _accessibilityNurtureNavigation = null;
        _autoViewingNavigation = null;
        _autoViewingSegment = null;
      }
      await _autoViewingSession?.setForeground(false);
      return;
    }
    try {
      await webViewController?.evaluateJavascript(source: autoWatchStopScript);
    } catch (_) {
      // Navigation/disposal may already have destroyed the old page.
    }
    final session = _autoViewingSession;
    final hadObserver = _autoViewingNavigation != null;
    if (finishViewing) {
      _autoViewingNavigation = null;
      _autoViewingSegment = null;
    }
    if (session == null) return;
    if (hadObserver) {
      try {
        final snapshot = await webViewController?.evaluateJavascript(
          source: finishViewing
              ? 'window.__manualViewing?.stop() ?? null'
              : 'window.__manualViewing?.setActive(false) ?? null',
        );
        await session.accept(snapshot);
      } catch (_) {
        // Event snapshots have already saved every completed view/comment.
      }
    }
    await session.setForeground(false);
  }

  Future<void> _startAutoViewingStats() async {
    final email = configuration.loginUsername.trim();
    if (email.isEmpty) return;
    final navigation = navigationId;
    final session = _autoViewingSession ??= ManualViewingSession(
      repository: nurtureRepository ?? proxyStore.nurture,
      email: email,
      configurationId: configuration.configurationId,
      plan: usesAccessibilityLogin
          ? _nurturePlan
          : const NurturePlan(NurtureMode.feed),
      onError: () => notify('Không thể lưu thống kê nuôi vào tài khoản.'),
    );
    await session.start();
    if (!active ||
        !autoWatchEnabled ||
        !appActive ||
        navigation != navigationId) {
      return;
    }
    if (_autoViewingNavigation != navigation) {
      _autoViewingNavigation = navigation;
      _autoViewingSegment = session.addSegment();
    }
    if (usesAccessibilityLogin) {
      await session.setForeground(true);
      return;
    }
    final ready = await webViewController?.evaluateJavascript(
      source: buildManualViewingScript(
        session.id,
        _autoViewingSegment!,
        handlerName: 'FlutterNurtureStats',
        allowTransparentVideo: true,
      ),
    );
    if (ready != true) throw StateError('Nurture statistics did not start');
    final snapshot = await webViewController?.evaluateJavascript(
      source: 'window.__manualViewing?.setActive(true) ?? null',
    );
    await session.accept(snapshot);
    await session.setForeground(true);
  }

  Future<void> _closeAutoViewing() async {
    await stopAutoWatch(finishViewing: true);
    await _autoViewingSession?.finish(error: pageFailure != null);
  }

  Future<bool> inputCommentText(List<dynamic> args) async {
    if (!active ||
        !autoWatchEnabled ||
        !appActive ||
        inputBusy ||
        args.length != 1 ||
        args.first is! String) {
      return false;
    }
    final text = args.first as String;
    if (!comments.contains(text)) return false;
    inputBusy = true;
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
      if (!_usesKeyboardInput) {
        await Clipboard.setData(ClipboardData(text: text));
      }
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
        if (await commentInputChannel.invokeMethod<bool>(
              _usesKeyboardInput ? 'typeText' : 'paste',
              {'context': 'comment', if (_usesKeyboardInput) 'text': text},
            ) ==
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
      inputBusy = false;
    }
  }

  /// null when no snapshot exposed the WebView at all.
  Future<bool?> _accessibilityAuthenticated() async {
    // The tree can be briefly missing or half-rendered after a page or Flutter
    // semantics update; retry before concluding the account is signed out.
    bool? result;
    for (var attempt = 0; attempt < 10; attempt++) {
      final s = await signupAccessibility.snapshot();
      if (s.ready) {
        result = NurtureAccessibilityRunner.authenticated(s);
        if (result) return true;
      }
      if (!active || !appActive) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return result;
  }

  Future<void> toggleAutoWatch() async {
    if (useNativeWebView) return;
    if (!active ||
        !appActive ||
        pageFailure != null ||
        accountFailure != null ||
        browserCheckOpen ||
        waitingToLogout ||
        logoutBusy ||
        _flowFinished ||
        autoWatchBusy ||
        autoLoginBusy ||
        autoSignupBusy ||
        webViewController == null) {
      return;
    }
    if (!autoWatchEnabled &&
        !loginConfirmed &&
        launchAction != TikTokLaunchAction.browse) {
      notify('Hãy đăng nhập tự động thành công trước khi bật Auto nuôi.');
      return;
    }
    mutate(() => autoWatchBusy = true);
    try {
      if (!autoWatchEnabled && launchAction == TikTokLaunchAction.browse) {
        final navigation = navigationId;
        mutate(() => loginConfirmed = false);
        final authenticated = usesAccessibilityLogin
            ? await _accessibilityAuthenticated()
            : await webViewController?.evaluateJavascript(
                source: checkAuthenticatedSessionScript,
              );
        if (!active ||
            !appActive ||
            navigation != navigationId ||
            browserCheckOpen ||
            pageFailure != null ||
            accountFailure != null) {
          return;
        }
        // A CAPTCHA modal hides the signed-in sidebar. It is not a sign-out:
        // keep the stored login state and let Auto nuôi solve it via the API.
        final captchaShown =
            authenticated != true &&
            usesAccessibilityLogin &&
            _captchaKey.isNotEmpty &&
            await webViewController?.evaluateJavascript(
                  source: rotateCaptchaPresentScript,
                ) ==
                true;
        if (!active || !appActive || navigation != navigationId) return;
        if (authenticated == null && usesAccessibilityLogin && !captchaShown) {
          // Unreadable is not signed out; keep the stored login state.
          notify('Chưa đọc được trang TikTok qua Accessibility; hãy thử lại.');
          return;
        }
        if (captchaShown) {
          notify('TikTok đang hiện CAPTCHA; Auto nuôi sẽ giải bằng API.');
        } else if (authenticated != true) {
          await _persistCurrentAccountLoginState(false);
          notify(
            'Hãy đăng nhập TikTok trên trang hiện tại trước khi bật Auto nuôi.',
          );
          return;
        } else {
          await _persistCurrentAccountLoginState(true);
        }
        mutate(() => loginConfirmed = true);
        if (!active || !appActive || navigation != navigationId) return;
      }
      if (usesAccessibilityLogin && !autoWatchEnabled) {
        await _startTimedAutoWatch();
        return;
      }
      _cancelAutoWatchTimers();
      mutate(() => autoWatchEnabled = !autoWatchEnabled);
      if (autoWatchEnabled) {
        await startAutoWatch();
      } else {
        await stopAutoWatch();
      }
    } catch (_) {
      notify('Không thể kiểm tra phiên đăng nhập. Hãy thử bật Auto nuôi lại.');
    } finally {
      mutate(() => autoWatchBusy = false);
    }
  }

  Future<void> stopAutoLogin(int attempt) async {
    if (useNativeWebView || usesAccessibilityLogin) return;
    try {
      await webViewController?.evaluateJavascript(
        source: buildAutoLoginStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void cancelAutoLogin({bool updateUi = true}) {
    _loginAccessibilityRunner?.cancel();
    loginOtpRequest?.cancel();
    loginOtpRequest = null;
    final attempt = autoLoginAttempt++;
    unawaited(stopAutoLogin(attempt));
    if (updateUi && active) mutate(() => autoLoginBusy = false);
  }

  Future<void> stopAutoSignup(int attempt) async {
    if (useNativeWebView || usesCoordinateSignup) return;
    try {
      await webViewController?.evaluateJavascript(
        source: buildAutoSignupStopScript(attempt),
      );
    } catch (_) {
      // Navigation may have destroyed the previous page.
    }
  }

  void cancelAutoSignup({bool updateUi = true}) {
    _signupCoordinateRunner?.cancel();
    signupOtpRequest?.cancel();
    signupOtpRequest = null;
    final attempt = autoSignupAttempt++;
    unawaited(stopAutoSignup(attempt));
    if (updateUi && active) mutate(() => autoSignupBusy = false);
  }

  Future<bool> inputSignupText(List<dynamic> args) =>
      inputAccountText(args, signup: true);

  Future<bool> inputLoginText(List<dynamic> args) =>
      inputAccountText(args, signup: false);

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
    // Also block late/stale JavaScript bridge calls while manual tapping is on.
    if (signup && _manualSignupButtonTaps) return false;
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
      if (!completed && isActive()) {
        try {
          await const MethodChannel(
            'test_tiktok/send_code_target',
          ).invokeMethod<bool>('invalidateTarget', {
            'id': controller.platform.params.id,
            'context': context,
            'action': action,
          });
        } catch (_) {
          // Keep the original failure; clearing a cache never repeats a tap.
        }
      }
      debugPrint('[$buttonLabel] $context gesture completed: $completed.');
      if (completed && signup && action == 'skip-username' && isActive()) {
        await _markConfigurationRegistered();
      }
      return completed;
    } catch (_) {
      return false;
    }
  }

  Future<bool> inputAccountText(
    List<dynamic> args, {
    required bool signup,
  }) async {
    // Block native typing/paste even if an old page calls the signup bridge.
    if (signup && _manualSignupFieldInput) return false;
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
        inputBusy ||
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
    if (text.isEmpty ||
        field == 'otp' && !RegExp(r'^[0-9]{6}$').hasMatch(text)) {
      return false;
    }
    final useKeyboard = _usesKeyboardInput && field != 'otp';
    final source =
        'window.$stateName?.canPasteFromClipboard('
        '$attempt, ${jsonEncode(field)}, ${jsonEncode(text)}) === true;';
    inputBusy = true;
    try {
      debugPrint('Auto $accountContext: entering $field through native input.');
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
      if (!useKeyboard) {
        await Clipboard.setData(ClipboardData(text: text));
      }
      // DOM focus can arrive before the native editor is ready for input. Retry
      // only rejected native actions, checking the field and attempt each time.
      for (var retry = 0; retry < 6; retry++) {
        if (!isActive() ||
            await controller.evaluateJavascript(source: source) != true ||
            !isActive()) {
          return false;
        }
        final entered = await commentInputChannel.invokeMethod<bool>(
          useKeyboard ? 'typeText' : 'paste',
          {
            'context': accountContext,
            'attempt': attempt,
            if (_usesKeyboardInput) ...{'field': field, 'text': text},
          },
        );
        if (entered == true) return true;
        if (retry < 5) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      debugPrint('Auto $accountContext: native input rejected for $field.');
      return false;
    } catch (_) {
      return false;
    } finally {
      inputBusy = false;
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
    notify('Hãy nhập Data Mail ở màn Cấu hình.');
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
        if (active) {
          notify('Không thể kết nối dịch vụ Trợ năng để bấm Send code.');
        }
        return false;
      } finally {
        _requestingAccessibility = false;
      }
    }
    return true;
  }

  Future<Map<String, dynamic>> _handleSignupCalibration(MethodCall call) async {
    if (!kDebugMode ||
        !usesAccessibilityAccountFlow ||
        call.method != 'calibrate' ||
        !active) {
      return {'ok': false, 'reason': 'accessibility-unavailable'};
    }
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final action = args['action'];
    final url = await webViewController?.getUrl();
    if (url?.scheme != 'https' || url?.host != 'www.tiktok.com') {
      return {'ok': false, 'reason': 'wrong-origin'};
    }
    Map<String, dynamic> result = {'ok': true, 'action': action};
    if (action == 'snapshot') {
      result = await FlutterAccessibilityService.signupSnapshot();
    } else if (action == 'login-profile') {
      result = {
        'ok': true,
        'points': (await LoginCoordinateProfile.load()).points,
      };
    } else if (action == 'nurture-profile') {
      result = {
        'ok': true,
        'points': (await NurtureCoordinateProfile.load()).points,
      };
    } else if (action == 'nurture-layout') {
      final snapshot = await signupAccessibility.snapshot();
      final video = NurtureVideo.read(snapshot);
      if (video == null) return {'ok': false, 'reason': 'video-unavailable'};
      final profile = await NurtureCoordinateProfile.load();
      final kind = video.orientation.name;
      final editors = snapshot.editors
          .where(
            (n) => RegExp(
              'comment|bình luận',
              caseSensitive: false,
            ).hasMatch(n.hint),
          )
          .toList();
      final controls = <String, SignupNode>{
        if (editors.length == 1) ...{
          NurtureCoordinateProfile.panelKey(
            kind,
            'focus-comment',
            snapshot.viewport,
            editors.single,
          ): editors.single,
          if (snapshot.find(
                RegExp(r'^Post$', caseSensitive: false),
                enabled: false,
              )
              case final post?)
            NurtureCoordinateProfile.panelKey(
              kind,
              'post-comment',
              snapshot.viewport,
              post,
            ): post,
          if (snapshot.find(RegExp(r'^exit$', caseSensitive: false))
              case final close?)
            NurtureCoordinateProfile.panelKey(
              kind,
              'close-comments',
              snapshot.viewport,
              close,
            ): close,
        } else ...{
          if (video.comments case final comments?)
            video.commentsKey(snapshot.viewport): comments,
          if (video.like case final like?)
            video.likeKey(snapshot.viewport): like,
          if (video.next case final next?) '$kind/feed/next-video': next,
        },
      };
      for (final entry in controls.entries) {
        await profile.target(entry.key, snapshot.viewport, entry.value);
      }
      final point = video.comments == null
          ? null
          : profile.point(video.commentsKey(snapshot.viewport));
      result = {
        'ok': true,
        'orientation': kind,
        'layout': video.layout(snapshot.viewport),
        'panelOpen': editors.length == 1,
        'points': profile.points,
        if (point != null) 'point': [point.dx, point.dy],
      };
    } else if (action == 'nurture-swipe') {
      final snapshot = await signupAccessibility.snapshot();
      final video = NurtureVideo.read(snapshot);
      if (video == null) return {'ok': false, 'reason': 'video-unavailable'};
      await signupAccessibility.swipe(
        snapshot.viewport,
        snapshot.viewport.fromScreen(
          Offset(
            video.bounds.center.dx,
            video.bounds.top + video.bounds.height * .8,
          ),
        ),
        snapshot.viewport.fromScreen(
          Offset(
            video.bounds.center.dx,
            video.bounds.top + video.bounds.height * .2,
          ),
        ),
      );
    } else if (action == 'submit-comment') {
      result = {'ok': await signupAccessibility.submitComment()};
    } else if (action == 'paste-comment') {
      result = await signupAccessibility.paste(
        '${args['userOtp'] ?? ''}',
        'comment',
      );
    } else if (action == 'select-birthday') {
      result = await calibrateSignupBirthday();
    } else if (action == 'nurture-prepare-input') {
      await signupAccessibility.setKeyboardSuppressed(true);
    } else if (action == 'nurture-release-input') {
      await signupAccessibility.dismissKeyboard();
      await signupAccessibility.setKeyboardSuppressed(false);
    } else if (action == 'back') {
      await signupAccessibility.dismissKeyboard();
    } else if (action == 'tap') {
      final snapshot = await signupAccessibility.snapshot();
      if (!snapshot.ready) return {'ok': false, 'reason': 'no-webview'};
      await signupAccessibility.tap(
        snapshot.viewport,
        Offset((args['x'] as num).toDouble(), (args['y'] as num).toDouble()),
      );
    } else if (action == 'paste-email' || action == 'paste-password') {
      final field = action == 'paste-email' ? 'email' : 'password';
      result = await signupAccessibility.paste(
        '${args['userOtp'] ?? ''}'.isNotEmpty
            ? args['userOtp'] as String
            : field == 'email'
            ? (launchAction == TikTokLaunchAction.signup
                      ? configuration.signupEmail
                      : configuration.loginUsername)
                  .trim()
            : (launchAction == TikTokLaunchAction.signup
                  ? configuration.signupPassword
                  : configuration.loginPassword),
        field,
      );
    } else if (action == 'paste-user-otp') {
      final code = '${args['userOtp'] ?? ''}';
      final snapshot = await signupAccessibility.snapshot();
      if (!RegExp(r'^\d{6}$').hasMatch(code) ||
          !snapshot.contains(
            RegExp(r'^Enter 6-digit code$', caseSensitive: false),
          )) {
        return {'ok': false, 'reason': 'invalid-otp-screen'};
      }
      result = await signupAccessibility.paste(code, 'otp');
    } else if (action == 'paste-otp') {
      final api = configuration.otpApi;
      if (api == null) return {'ok': false, 'reason': 'missing-otp-api'};
      final reader = OtpApiClient(api, logOutput: (_) {});
      try {
        final otp = await reader.fetchCode(
          email: configuration.signupEmail.trim(),
          password: configuration.signupMailboxPassword,
        );
        if (!active) return {'ok': false, 'reason': 'page-closed'};
        final currentUrl = await webViewController?.getUrl();
        if (currentUrl?.host != 'www.tiktok.com' ||
            currentUrl?.scheme != 'https') {
          return {'ok': false, 'reason': 'wrong-origin'};
        }
        result = await signupAccessibility.paste(otp, 'otp');
      } finally {
        reader.close();
      }
    } else {
      return {'ok': false, 'reason': 'unknown-action'};
    }
    return {
      ...result,
      'action': action,
      'configurationId': configuration.configurationId,
    };
  }

  /// Debug-only verification of birthday selection on the current form.
  Future<Map<String, dynamic>> calibrateSignupBirthday() async {
    if (!kDebugMode ||
        !usesCoordinateSignup ||
        !active ||
        !appActive ||
        autoSignupBusy) {
      return {'ok': false, 'reason': 'signup-unavailable'};
    }
    final runner = SignupCoordinateRunner(
      profile: await SignupCoordinateProfile.load(),
      accessibility: signupAccessibility,
      configuration: configuration,
      isActive: () => active && appActive && !autoSignupBusy,
      isTikTok: () async {
        final url = await webViewController?.getUrl();
        return url?.scheme == 'https' && url?.host == 'www.tiktok.com';
      },
      getOtp: () async => throw StateError('Birthday calibration only'),
      onStatus: (status) {
        if (active) mutate(() => signupStatus = status);
      },
      readBirthdayMenu: _readSignupBirthdayMenu,
    );
    try {
      await runner.selectBirthday();
      return {
        'ok': true,
        'birthday': AppConfiguration.formatBirthday(runner.birthday),
      };
    } on StateError catch (error) {
      return {'ok': false, 'reason': error.message.toString()};
    } on SignupCancelled {
      return {'ok': false, 'reason': 'cancelled'};
    }
  }

  Future<SignupBirthdayMenu?> _readSignupBirthdayMenu(String field) async {
    // Read geometry only. Selecting and scrolling still use real gestures.
    final result = await webViewController?.evaluateJavascript(
      source: buildReadSignupBirthdayMenuScript(field),
    );
    return SignupBirthdayMenu.fromResult(result);
  }

  Future<void> autoSignup() async {
    if (useNativeWebView) return;
    if (waitingToLogout || logoutBusy || _flowFinished) return;
    if (usesCoordinateSignup) {
      await _runCoordinateSignup();
      return;
    }
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
    if (!_manualSignupFieldInput &&
        (configuration.signupEmail.trim().isEmpty ||
            configuration.signupPassword.isEmpty)) {
      notify('Hãy nhập email và mật khẩu đăng ký ở màn Cấu hình.');
      return;
    }
    if (!_manualSignupFieldInput && !validateOtpMailbox(signup: true)) return;
    if (!_manualSignupButtonTaps && !await ensureAccountAccessibility()) return;
    _cancelAutoWatchTimers();
    activeSignupOtp = _manualSignupFieldInput
        ? ''
        : configuration.signupOtp.trim();
    final attempt = ++autoSignupAttempt;
    mutate(() {
      autoSignupBusy = true;
      loginConfirmed = false;
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
              : Duration(milliseconds: 2000 + _actionRandom.nextInt(5001)),
        );
        if (!isActive()) return;
        if (otpRequest?.error != null) {
          message = otpRequest!.error;
          break;
        }
        if (activeSignupOtp.isEmpty && otpRequest?.code != null) {
          mutate(() => activeSignupOtp = otpRequest!.code!);
        }
        await _checkRotateCaptcha();
        if (!isActive()) return;
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
              manualAccessibilityButtons: _manualSignupButtonTaps,
              manualFieldInput: _manualSignupFieldInput,
              waitForOtpApi:
                  !_manualSignupFieldInput &&
                  configuration.otpApi != null &&
                  activeSignupOtp.isEmpty,
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
        // Native Skip is persisted only after the gesture acknowledges success.
        if (result == 'username-skipped' && !_usesAccessibility) {
          await _markConfigurationRegistered();
          if (!isActive()) return;
        }
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
          'waiting-home-video' => 'Đang chờ video trên trang chủ…',
          'waiting-home-like' => 'Đang chờ nút tim trên trang chủ…',
          'home-video-liked' => 'Đã bấm tim, đang chờ hộp đăng nhập…',
          'waiting-login-modal' => 'Mạng chậm, đang chờ hộp đăng nhập…',
          'waiting-send-code' => 'Đang chờ 5 giây trước khi bấm Send code…',
          'waiting-manual-send-code' => 'Hãy bấm Send code trên TikTok.',
          'waiting-manual-password-submit' =>
            'Đã nhập mật khẩu. Hãy bấm Sign up trên TikTok.',
          'waiting-manual-username-skip' => 'Hãy bấm Skip trên TikTok.',
          'waiting-manual-email' => 'Hãy nhập email trên TikTok.',
          'waiting-manual-password' => 'Hãy nhập mật khẩu trên TikTok.',
          'waiting-manual-otp' => 'Hãy nhập đủ 6 số OTP trên TikTok.',
          'waiting-manual-birthday' => 'Hãy chọn ngày sinh trên TikTok.',
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
            !_manualSignupFieldInput &&
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
          await _markConfigurationRegistered();
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
          if (_manualSignupFieldInput) {
            message = 'Đã gửi mã. Hãy nhập OTP trực tiếp trên TikTok.';
            continue;
          }
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
        } else if (result == 'home-modal-failed') {
          message =
              'TikTok chưa mở hộp đăng nhập sau khi thử lại. '
              'Hãy kiểm tra mạng hoặc tải lại trang.';
          break;
        } else if (result == 'signup-error') {
          message =
              'TikTok báo lỗi đăng ký. Hãy kiểm tra thông tin trên trang.';
          break;
        } else if (result == 'paste-failed') {
          message =
              'Không thể tự nhập thông tin đăng ký. '
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
    } on StateError catch (error) {
      message = error.message.toString();
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
        if (signupSucceeded) _afterSignupSucceeded();
      }
    }
  }

  Future<void> _runCoordinateSignup() async {
    if (autoSignupBusy) {
      cancelAutoSignup();
      return;
    }
    if (webViewController == null ||
        !active ||
        !appActive ||
        accountFailure != null ||
        autoLoginBusy ||
        autoWatchBusy) {
      return;
    }
    if (configuration.signupEmail.trim().isEmpty ||
        configuration.signupPassword.isEmpty) {
      notify('Hãy chọn cấu hình có email và mật khẩu TikTok.');
      return;
    }
    if (!validateOtpMailbox(signup: true) ||
        !await ensureAccountAccessibility() ||
        !active) {
      return;
    }
    final attempt = ++autoSignupAttempt;
    _cancelAutoWatchTimers();
    mutate(() {
      autoSignupBusy = true;
      loginConfirmed = false;
      autoWatchEnabled = false;
      signupStatus = 'Đang chuẩn bị đăng ký bằng Accessibility…';
    });
    bool isActive() =>
        active && appActive && autoSignupBusy && autoSignupAttempt == attempt;
    OtpCodeRequest? coordinateOtpRequest;
    SignupCoordinateRunner? coordinateRunner;
    var succeeded = false;
    try {
      await stopAutoWatch();
      final profile = await SignupCoordinateProfile.load();
      if (!isActive()) return;
      final runner = SignupCoordinateRunner(
        profile: profile,
        accessibility: signupAccessibility,
        configuration: configuration,
        isActive: isActive,
        onUsernameSkipped: _markConfigurationRegistered,
        isPageReady: () => initialPageLoaded && pageFailure == null,
        readBirthdayMenu: _readSignupBirthdayMenu,
        isTikTok: () async {
          final url = await webViewController?.getUrl();
          return url?.scheme == 'https' && url?.host == 'www.tiktok.com';
        },
        getOtp: () async {
          final configuredOtp = configuration.signupOtp.trim();
          if (configuredOtp.isNotEmpty) return configuredOtp;
          // After Resend code, a fresh API request reads the new mail.
          coordinateOtpRequest?.cancel();
          final request = requestOtp(signup: true);
          coordinateOtpRequest = request;
          signupOtpRequest = request;
          while (isActive() && request.code == null && request.error == null) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          if (!isActive()) throw const SignupCancelled();
          if (request.error != null) {
            if (request.timedOut) throw SignupOtpTimeout(request.error!);
            throw StateError(request.error!);
          }
          return request.code!;
        },
        onStatus: (status) {
          if (isActive()) mutate(() => signupStatus = status);
        },
      );
      _signupCoordinateRunner = runner;
      coordinateRunner = runner;
      await runner.run();
      if (isActive()) {
        await _markConfigurationRegistered();
        notify(
          runner.alreadyLoggedIn
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng ký TikTok thành công.',
        );
        succeeded = isActive();
      }
    } on SignupCancelled {
      // Cancellation keeps the current form without issuing another action.
    } on StateError catch (error) {
      if (isActive()) notify(error.message.toString());
    } catch (error) {
      debugPrint('Coordinate signup stopped (${error.runtimeType}).');
      if (isActive()) {
        notify(
          'Chưa hoàn tất đăng ký bằng Accessibility. Hãy kiểm tra màn TikTok.',
        );
      }
    } finally {
      coordinateOtpRequest?.cancel();
      if (identical(signupOtpRequest, coordinateOtpRequest)) {
        signupOtpRequest = null;
      }
      if (identical(_signupCoordinateRunner, coordinateRunner)) {
        _signupCoordinateRunner = null;
      }
      if (isActive()) {
        mutate(() => autoSignupBusy = false);
        if (succeeded) _afterSignupSucceeded();
      }
    }
  }

  Future<void> autoLogin() async {
    if (useNativeWebView) return;
    if (waitingToLogout || logoutBusy || _flowFinished) return;
    if (usesAccessibilityLogin) {
      await _runAccessibilityLogin();
      return;
    }
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
    _cancelAutoWatchTimers();
    activeLoginOtp = configuration.loginOtp.trim();
    final attempt = ++autoLoginAttempt;
    mutate(() {
      autoLoginBusy = true;
      loginConfirmed = false;
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
        await _checkRotateCaptcha();
        if (!isActive()) return;
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
          mutate(() => loginConfirmed = true);
          await _persistCurrentAccountLoginState(true);
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
              'Không thể tự nhập thông tin đăng nhập. '
              'Đã dừng, bạn có thể nhập thủ công.';
          break;
        } else if (result == 'home-modal-failed') {
          message =
              'TikTok chưa mở hộp đăng nhập sau khi thử lại. '
              'Hãy kiểm tra mạng hoặc tải lại trang.';
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
    } on StateError catch (error) {
      message = error.message.toString();
    } catch (_) {
      // Keep credentials and WebView exception details out of UI messages.
    } finally {
      otpRequest?.cancel();
      if (identical(loginOtpRequest, otpRequest)) loginOtpRequest = null;
      await stopAutoLogin(attempt);
      if (active && isActive()) {
        mutate(() => autoLoginBusy = false);
        notify(message);
        if (loginSucceeded && active && appActive && pageFailure == null) {
          await _startTimedAutoWatch();
        }
      }
    }
  }

  Future<void> _runAccessibilityLogin() async {
    if (autoLoginBusy) {
      cancelAutoLogin();
      return;
    }
    if (webViewController == null ||
        !active ||
        !appActive ||
        autoWatchBusy ||
        autoSignupBusy ||
        accountFailure != null) {
      return;
    }
    if (configuration.loginUsername.trim().isEmpty ||
        configuration.loginPassword.isEmpty) {
      notify('Hãy nhập tài khoản và mật khẩu đăng nhập ở màn Cấu hình.');
      return;
    }
    if (!validateOtpMailbox(signup: false) ||
        !await ensureAccountAccessibility() ||
        !active ||
        !appActive) {
      return;
    }
    final attempt = ++autoLoginAttempt;
    _cancelAutoWatchTimers();
    activeLoginOtp = configuration.loginOtp.trim();
    mutate(() {
      autoLoginBusy = true;
      loginConfirmed = false;
      autoWatchEnabled = false;
      loginStatus = 'Đang chuẩn bị đăng nhập bằng Accessibility…';
    });
    bool isActive() =>
        active &&
        appActive &&
        autoLoginBusy &&
        autoLoginAttempt == attempt &&
        pageFailure == null &&
        accountFailure == null;
    OtpCodeRequest? request;
    LoginAccessibilityRunner? runner;
    var succeeded = false;
    try {
      await stopAutoWatch();
      if (!isActive()) return;
      final profile =
          await (loginProfileLoader ?? LoginCoordinateProfile.load)();
      if (!isActive()) return;
      runner = LoginAccessibilityRunner(
        profile: profile,
        accessibility: signupAccessibility,
        configuration: configuration,
        isActive: isActive,
        isPageReady: () => initialPageLoaded && pageFailure == null,
        isTikTok: () async {
          final url = await webViewController?.getUrl();
          return url?.scheme == 'https' && url?.host == 'www.tiktok.com';
        },
        getOtp: () async {
          if (!isActive()) throw const LoginAccessibilityCancelled();
          if (activeLoginOtp.isNotEmpty) return activeLoginOtp;
          final pending = requestOtp(signup: false);
          request = pending;
          loginOtpRequest = pending;
          while (isActive() &&
              identical(request, pending) &&
              pending.code == null &&
              pending.error == null) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          if (!isActive() || !identical(request, pending)) {
            throw const LoginAccessibilityCancelled();
          }
          if (pending.error != null) {
            if (pending.timedOut) throw LoginOtpTimeout(pending.error!);
            throw StateError(pending.error!);
          }
          mutate(() => activeLoginOtp = pending.code!);
          return pending.code!;
        },
        cancelOtpRequest: () {
          request?.cancel();
          request = null;
          loginOtpRequest = null;
          activeLoginOtp = '';
        },
        onStatus: (status) {
          if (isActive()) mutate(() => loginStatus = status);
        },
        now: _now,
      );
      _loginAccessibilityRunner = runner;
      await runner.run();
      if (!isActive()) return;
      mutate(() => loginConfirmed = true);
      await _persistCurrentAccountLoginState(true);
      if (!isActive()) return;
      succeeded = true;
      notify(
        runner.alreadyLoggedIn
            ? 'Tài khoản TikTok đã đăng nhập.'
            : 'Đăng nhập TikTok thành công.',
      );
    } on LoginAccessibilityCancelled {
      // Keep the current form when stopped, backgrounded or navigated away.
    } on LoginAccessibilityRateLimited {
      if (isActive()) showAccountFailure(TikTokAccountFailure.rateLimited);
    } on StateError catch (error) {
      if (isActive()) notify(error.message.toString());
    } catch (error) {
      debugPrint('Accessibility login stopped (${error.runtimeType}).');
      if (isActive()) {
        notify(
          'Chưa hoàn tất đăng nhập bằng Accessibility. Hãy kiểm tra màn TikTok.',
        );
      }
    } finally {
      request?.cancel();
      if (identical(loginOtpRequest, request)) loginOtpRequest = null;
      if (identical(_loginAccessibilityRunner, runner)) {
        _loginAccessibilityRunner = null;
      }
      // An error overlay may invalidate isActive while this attempt still owns UI.
      if (active && autoLoginAttempt == attempt) {
        mutate(() => autoLoginBusy = false);
        if (succeeded &&
            appActive &&
            pageFailure == null &&
            accountFailure == null) {
          await _startTimedAutoWatch();
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
      'comment-paste-failed' => 'Không thể tự nhập bình luận. Đã dừng tự động.',
      'comment-window-expired' =>
        'Đã quá 70% thời lượng video khi đang nhập bình luận. Đã dừng và giữ bản nháp.',
      _ =>
        'Chưa xác nhận được bình luận đã gửi. Đã dừng, không gửi lại để tránh trùng.',
    };
    if (_logsOutAfterNurture && message != 'login-required') {
      // The account is still signed in: end the session with the usual logout.
      notify(text);
      _finishTimedAutoWatch();
      return;
    }
    _cancelAutoWatchTimers();
    mutate(() {
      autoWatchEnabled = false;
      if (message == 'login-required') loginConfirmed = false;
    });
    unawaited(stopAutoWatch());
    if (message == 'login-required') {
      unawaited(_persistCurrentAccountLoginState(false));
    }
    notify(text);
    if (message == 'login-required') _failAutoFlow();
  }

  Future<void> _startNurtureWithRetainedSession() async {
    mutate(() => autoWatchBusy = true);
    bool canContinue() =>
        active &&
        appActive &&
        !browserCheckOpen &&
        pageFailure == null &&
        accountFailure == null;
    try {
      // A retained cookie is only a hint. Allow TikTok to hydrate and confirm
      // the live signed-in UI before enabling another ten-minute run.
      for (var attempt = 0; attempt < 20 && canContinue(); attempt++) {
        final navigation = navigationId;
        dynamic authenticated;
        try {
          authenticated = usesAccessibilityLogin
              ? NurtureAccessibilityRunner.authenticated(
                  await signupAccessibility.snapshot(),
                )
              : await webViewController?.evaluateJavascript(
                  source: checkAuthenticatedSessionScript,
                );
        } catch (_) {
          // Navigation can briefly replace the JavaScript context.
        }
        if (!canContinue()) return;
        if (navigation == navigationId && authenticated == true) {
          mutate(() => loginConfirmed = true);
          await _persistCurrentAccountLoginState(true);
          if (!canContinue() || navigation != navigationId) return;
          await _startTimedAutoWatch();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (canContinue()) {
        await _persistCurrentAccountLoginState(false);
        mutate(() => autoWatchBusy = false);
        await autoLogin();
      }
    } finally {
      mutate(() => autoWatchBusy = false);
    }
  }

  Future<void> runInitialAction() async {
    if (!active ||
        useNativeWebView ||
        browserCheckOpen ||
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
    if (startWithNurture ||
        (launchAction == TikTokLaunchAction.login &&
            await hasTikTokLoginSession())) {
      await _startNurtureWithRetainedSession();
      return;
    }
    switch (launchAction) {
      case TikTokLaunchAction.browse:
        return;
      case TikTokLaunchAction.login:
        await autoLogin();
      case TikTokLaunchAction.signup:
        await autoSignup();
    }
    if (active && !_flowContinues) _failAutoFlow();
  }

  void cancelAutoActions({bool cancelHandoff = true}) {
    if (cancelHandoff && (waitingToLogout || logoutBusy)) cancelSignupHandoff();
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
    _startRotateCaptchaMonitor();
    await updateNavigationState();
    if (pageFailure != null || browserCheckOpen || useNativeWebView) return;
    if (usesAccessibilityAccountFlow) {
      _startCookieConsentMonitor();
      unawaited(checkProxyIp());
      await runInitialAction();
      await startAutoWatch();
      return;
    }
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
        '[WebView identity] Khớp nhận diện đang dùng: ${agent == effectiveUserAgent}',
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
    _stopRotateCaptchaMonitor();
    cancelSignupHandoff();
    _cancelAutoWatchTimers();
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
    _failAutoFlow(reason: '${failure.title}\n${failure.message}');
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
        userAgent: effectiveUserAgent,
        useInstalledEngine: usesEngineIdentity,
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
    if (useNativeWebView) return;
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
    _startRotateCaptchaMonitor();
    if (usesAccessibilityAccountFlow && kDebugMode) {
      _signupCalibrationChannel.setMethodCallHandler(_handleSignupCalibration);
    }
    if (_manualSession != null) {
      controller.addJavaScriptHandler(
        handlerName: 'FlutterManualViewingStats',
        callback: (args) async {
          if (args.isNotEmpty && active) {
            await _manualSession?.accept(args.first);
          }
        },
      );
    }
    if (!useNativeWebView && !usesCoordinateSignup) {
      controller.addJavaScriptHandler(
        handlerName: 'FlutterNurtureStats',
        callback: (args) async {
          if (args.isNotEmpty) await _autoViewingSession?.accept(args.first);
        },
      );
      controller.addJavaScriptHandler(
        handlerName: 'FlutterCommentPaste',
        callback: inputCommentText,
      );
      if (!usesAccessibilityAccountFlow) {
        controller.addJavaScriptHandler(
          handlerName: 'FlutterLoginPaste',
          callback: inputLoginText,
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
          callback: inputSignupText,
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
      }
      controller.addJavaScriptHandler(
        handlerName: 'FlutterAutoWatch',
        callback: (args) {
          if (args.isNotEmpty) {
            handleAutoWatchMessage(args.first.toString());
          }
        },
      );
    }
    if (needsDesktopIdentity) {
      try {
        final agent = await configureAndroidDesktopIdentity(
          controller,
          userAgent: configuration.userAgent,
          useInstalledEngine: usesEngineIdentity,
          fixedSignupViewport: usesAccessibilityAccountFlow,
          viewportWidth: usesAccessibilityAccountFlow
              ? signupViewportWidth
              : null,
        );
        if (usesAccessibilityAccountFlow) {
          await const MethodChannel(
            'test_tiktok/webview_identity',
          ).invokeMethod<bool>('configureSignupViewport', {
            'id': controller.platform.params.id,
          });
        }
        final timeZone = useNativeWebView
            ? null
            : configuration.webViewTimeZone;
        if (timeZone != null) {
          // Validate in the empty initial document before any external page.
          final ready = await controller.evaluateJavascript(
            source:
                '${webViewTimeZoneScript(timeZone)}\n'
                'Intl.DateTimeFormat().resolvedOptions().timeZone === '
                'Intl.DateTimeFormat("en-US", {timeZone: ${jsonEncode(timeZone)}}).resolvedOptions().timeZone',
          );
          if (ready != true) {
            throw const FormatException(
              'WebView không áp dụng được múi giờ proxy.',
            );
          }
        }
        if (!active) return;
        mutate(() {
          _effectiveUserAgent = agent;
          browserIdentityReady = true;
          if (useNativeWebView) initialActionStarted = true;
        });
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri(initialUrl),
            headers: navigationHeaders,
          ),
        );
      } on FormatException catch (error) {
        if (active) {
          showPageFailure(
            WebViewFailure('Không thể áp dụng múi giờ', error.message),
          );
        }
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
    } else if (active) {
      mutate(() => browserIdentityReady = true);
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
    _stopRotateCaptchaMonitor();
    _ipChecker?.cancel();
    initialPageLoaded = false;
    _autoViewingNavigation = null;
    _autoViewingSegment = null;
    mutate(() {
      final host = url?.host ?? '';
      browserCheckOpen =
          host == 'whatismybrowser.com' ||
          host.endsWith('.whatismybrowser.com') ||
          host == 'whatismyip.com' ||
          host.endsWith('.whatismyip.com');
      navigationId++;
      loadingProgress = 0;
      pageFailure = null;
      accountFailure = null;
      proxyWarning = null;
      proxyWarningIsIpCheck = false;
      checkingIp = false;
      detectedIp = null;
    });
    _startRotateCaptchaMonitor();
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
    final host = url?.host ?? '';
    final session = _manualSession;
    final navigation = navigationId;
    if (session == null ||
        !active ||
        pageFailure != null ||
        manualViewingClosed ||
        !(host == 'tiktok.com' || host.endsWith('.tiktok.com')) ||
        url?.scheme != 'https' ||
        _manualNavigation == navigationId) {
      return;
    }
    _manualNavigation = navigationId;
    await session.start();
    if (!active || manualViewingClosed || navigation != navigationId) return;
    final segment = session.addSegment();
    try {
      final result = await controller.evaluateJavascript(
        source: buildManualViewingScript(session.id, segment),
      );
      if (result != true) throw StateError('Playback observer unavailable');
      await _updateManualForeground();
    } catch (_) {
      if (active) notify('Không thể theo dõi thời gian xem trên trang này.');
    }
  }

  Future<void> _updateManualForeground() async {
    final session = _manualSession;
    if (session == null || manualViewingClosed) return;
    try {
      final snapshot = await webViewController?.evaluateJavascript(
        source:
            'window.__manualViewing?.setActive(${appActive ? 'true' : 'false'}) ?? null',
      );
      await session.accept(snapshot);
    } catch (_) {}
    await session.setForeground(appActive);
  }

  Future<void> closeManualViewing() => _manualClose ??= _finishManualViewing();

  Future<void> _finishManualViewing() async {
    _stopRotateCaptchaMonitor();
    final session = _manualSession;
    if (session != null) {
      try {
        final snapshot = await webViewController?.evaluateJavascript(
          source: 'window.__manualViewing?.stop() ?? null',
        );
        await session.accept(snapshot);
      } catch (_) {}
      await session.finish(error: pageFailure != null);
    }
    if (active) mutate(() => manualViewingClosed = true);
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
    final wasWatching = autoWatchEnabled;
    _cancelAutoWatchTimers();
    mutate(() {
      accountFailure = failure;
      autoWatchEnabled = false;
    });
    if (wasWatching) unawaited(stopAutoWatch());
    notify(
      '${failure.title}\n${failure.message}',
      duration: const Duration(seconds: 6),
      actionLabel: 'Cấu hình',
      onAction: onReturnToConfiguration,
    );
    debugPrint('[TikTok account] ${failure.title}: ${failure.message}');
    _failAutoFlow();
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
    _userTookOver();
    cancelAutoActions();
    unawaited(
      webViewController?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(tiktokHomeUrl),
          headers: navigationHeaders,
        ),
      ),
    );
  }

  Future<void> openBrowserCheck() async {
    final controller = webViewController;
    if (!active || controller == null || !browserIdentityReady) return;
    _userTookOver();
    _cancelAutoWatchTimers();
    cancelAutoActions();
    _ipChecker?.cancel();
    mutate(() {
      browserCheckOpen = true;
      initialPageLoaded = false;
      autoWatchEnabled = false;
    });
    await stopAutoWatch();
    if (!active) return;
    // Navigate the existing WebView: its native proxy, UA, Client Hints and
    // cookie store are the same ones used by TikTok.
    await controller.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(browserCheckUrl),
        headers: navigationHeaders,
      ),
    );
  }

  void reloadPage() {
    cancelAutoActions(cancelHandoff: false);
    unawaited(webViewController?.reload());
  }

  void retryPage() {
    final controller = webViewController;
    if (controller == null) return;
    _cancelAutoFailure();
    unawaited(
      browserIdentityReady ? controller.reload() : onWebViewCreated(controller),
    );
  }

  void retryProxyWarning() {
    if (checkingIp) return;
    if (proxyWarningIsIpCheck) {
      unawaited(checkProxyIp());
    } else {
      reloadPage();
    }
  }
}
