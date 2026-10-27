import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

import '../scripts/rotate_captcha_script.dart';
import '../rotate_captcha.dart';
import '../captcha_settings_store.dart';
import '../send_code_accessibility.dart';
import '../cookie_consent_accessibility.dart';
import '../privacy_notice_accessibility.dart';
import '../signup_accessibility.dart';
import '../signup_coordinate_runner.dart';
import '../login_accessibility_runner.dart';
import '../login_coordinate_profile.dart';
import '../nurture_accessibility_runner.dart';
import '../nurture_coordinate_profile.dart';
import '../scripts/manual_viewing_script.dart';
import '../manual_viewing_session.dart';
import '../nurture_data.dart';
import '../nurture_store.dart';
import '../webview_proxy_ip.dart';
import '../webview_user_agent.dart';
import '../app_configuration.dart';
import '../account_sessions.dart';
import '../app_session.dart';
import '../otp_api.dart';
import '../proxy_store.dart';
import '../webview_failure.dart';
import '../gecko_browser.dart';
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
  bool _signupHandoffStarted = false;
  bool _signupNeedsLogin = false;
  bool _flowFinished = false;
  bool _watchCompletionPending = false;
  bool _finishingWatch = false;

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
    await _persistCurrentAccountLoginState(!_signupNeedsLogin);
    if (!active || _flowFinished) return;
    _flowFinished = true;
    _autoFlowWatchdog?.cancel();
    onFlowFinished?.call(TikTokFlowResult.signupCompleted);
  }

  /// Warm up the new account for the configured time in the session that
  /// created it.
  Future<void> _nurtureAfterSignup() async {
    if (_signupNeedsLogin) {
      await _startNurtureWithRetainedSession();
      if (active && !loginConfirmed && !_flowFinished) _failAutoFlow();
      return;
    }
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

  void _stopFailedConfiguration(String reason) {
    if (!active || !autoAdvance || _stoppedByUser || autoRunFailing) return;
    _cancelAutoWatchTimers();
    if (autoLoginBusy) cancelAutoLogin();
    if (autoSignupBusy) cancelAutoSignup();
    mutate(() {
      autoWatchEnabled = false;
      _watchCompletionPending = false;
    });
    unawaited(() async {
      await stopAutoWatch(finishViewing: true);
      await _saveNurtureScreenTime();
      await _autoViewingSession?.finish(error: true);
      _autoViewingSession = null;
    }());
    notify(reason);
    _failAutoFlow(reason: reason);
  }

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
    debugPrint('[Diag notice] ${message.replaceAll('\n', ' | ')}');
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
  Future<void>? _nurtureRun;
  Timer? _nurtureRecoveryTimer;
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

  /// Quản lý cấu hình › Kiểm tra IP opens this with the configuration loaded.
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

  /// Width of the desktop frame in dp; fixes the page scale to the frame,
  /// which is narrower than the screen on most phones and tablets.
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
  String? _rotateCaptchaFailure, _rotateCaptchaFailureKey;
  bool verificationPaused = false;
  static const verificationPausedMessage =
      'Đã tạm dừng nuôi để kiểm tra CAPTCHA và giữ trang hiện tại.';

  /// Manual runs retain the page; queued runs skip an unusable configuration.
  void pauseForVerification({String? reason}) {
    if (!active || verificationPaused) return;
    if (autoAdvance && !_stoppedByUser) {
      _stopFailedConfiguration(
        '${reason ?? 'Không xử lý được CAPTCHA.'} Chuyển cấu hình tiếp theo.',
      );
      return;
    }
    _userTookOver();
    _cancelAutoWatchTimers();
    if (autoLoginBusy) cancelAutoLogin();
    if (autoSignupBusy) cancelAutoSignup();
    mutate(() {
      verificationPaused = true;
      autoWatchEnabled = false;
      _watchCompletionPending = false;
    });
    unawaited(stopAutoWatch());
    notify(
      reason == null
          ? verificationPausedMessage
          : '$reason $verificationPausedMessage',
    );
  }

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
  late final _privacyNotice = PrivacyNoticeAccessibility(
    accessibility: SignupAccessibility(),
    now: _now,
  );
  Timer? _cookieConsentTimer;

  /// The JS auto-accept is off in Accessibility mode, so the banner is
  /// accepted with a gesture while no signup/login runner is acting (both
  /// accept it themselves) and no other Accessibility action is in flight.
  /// TikTok's one-time privacy notice is closed the same way, e.g. when a
  /// nurtured account opens it.
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
            !verificationPaused &&
            _rotateCaptchaWork == null &&
            !signupAccessibility.actionBusy) {
          if (await _cookieConsent.check()) {
            debugPrint('[Cookie] Tapped Allow all.');
          } else if (await _privacyNotice.check()) {
            debugPrint('[Privacy notice] Tapped Got it.');
          }
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
    final navigation = navigationId, epoch = _rotateCaptchaEpoch;
    // Share the handled future: concurrent snapshots must not receive the
    // original failure and restart navigation before the pause wins.
    final work = _inspectRotateCaptcha().catchError((Object error) {
      if (error is RotateCaptchaCancelled) throw error;
      if (_canCheckRotateCaptcha &&
          navigationId == navigation &&
          _rotateCaptchaEpoch == epoch) {
        if (error is _RotateCaptchaFailure) {
          pauseForVerification(reason: error.message);
        } else {
          // A page/bridge read failure does not prove a CAPTCHA is present.
          debugPrint(
            '[CAPTCHA] Inspection unavailable (${error.runtimeType}); will retry.',
          );
          return;
        }
      }
      throw RotateCaptchaCancelled();
    });
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
    Future<bool> isPresent() async {
      final result = await controller.evaluateJavascript(
        source: rotateCaptchaPresentScript,
      );
      await guard();
      // Hidden/loading documents and unavailable bridge results are unknown.
      if (result is! bool) throw _RotateCaptchaInspectionUnavailable();
      return result;
    }

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
      throw _RotateCaptchaFailure(_rotateCaptchaFailure!);
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
        attempts: 3,
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
    } on _RotateCaptchaInspectionUnavailable {
      rethrow;
    } catch (error) {
      if (!current()) throw RotateCaptchaCancelled();
      if (!await isPresent()) {
        _clearRotateCaptchaFailure();
        return;
      }
      final message = error is StateError
          ? error.message.toString()
          : 'Không xử lý được CAPTCHA xoay. Hãy kiểm tra API key, mạng và màn hiện tại.';
      _failedRotateCaptcha = challenge;
      _rotateCaptchaFailure = message;
      _rotateCaptchaFailureKey = key;
      throw _RotateCaptchaFailure(message);
    } finally {
      if (identical(_rotateCaptchaSolver, solver)) _rotateCaptchaSolver = null;
    }
  }

  SignupCoordinateRunner? _signupCoordinateRunner;
  LoginAccessibilityRunner? _loginAccessibilityRunner;
  static const _signupCalibrationChannel = MethodChannel(
    'test_tiktok/signup_calibration',
  );
  GeckoController? webViewController;
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
      if (selected) {
        await AccountSessions.save(id, email, loggedIn: loggedIn);
      }
    } catch (_) {
      // Session persistence must not interrupt browser controls.
    }
  }

  SendCodeAccessibility? _sendCodeAccessibility;
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

  /// Nurture time is time on this screen during a timed nurture, whether or
  /// not a video loads or plays; only time in the background is left out.
  Duration _nurtureScreenTime = Duration.zero;
  DateTime? _nurtureScreenSince;
  Timer? _nurtureScreenTicker;
  bool appActive = true;

  /// Hidden or paused; a shade or system dialog only makes the app inactive.
  bool appInBackground = false;
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
    appInBackground =
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (!appActive) {
      _stopRotateCaptchaMonitor();
    } else {
      _startRotateCaptchaMonitor();
    }
    if (appInBackground) {
      _pauseNurtureClock();
    } else if (autoWatchEnabled) {
      _resumeNurtureClock();
    }
    if (manualViewingPlan != null) {
      unawaited(_updateManualForeground());
      return;
    }
    if (!appActive && autoLoginBusy) cancelAutoLogin();
    // Coordinate signup waits while the app is only covered (notification
    // shade, system dialog); see _runCoordinateSignup.
    if (autoSignupBusy &&
        (usesCoordinateSignup ? appInBackground : !appActive)) {
      if (appInBackground) {
        notify('Đã dừng đăng ký vì ứng dụng bị chuyển sang nền.');
      }
      cancelAutoSignup();
    }
    if (appActive) {
      if (_watchCompletionPending) {
        unawaited(_returnAfterNurture());
        return;
      }
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
    if (useNativeWebView || !usesAccessibilityLogin) return;
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
          onComment: () =>
              notify('Đã gửi bình luận.', duration: const Duration(seconds: 2)),
          onCommentSkipped: (message) =>
              notify(message, duration: const Duration(seconds: 2)),
          onLike: () =>
              notify('Đã thả tim.', duration: const Duration(seconds: 2)),
          onLikeSkipped: (message) =>
              notify(message, duration: const Duration(seconds: 2)),
          searchKeyword: _nurturePlan.mode == NurtureMode.search
              ? _nurturePlan.keyword
              : null,
          now: _now,
        );
      }
      final runner = _accessibilityNurture!;
      final running = runner.start();
      if (identical(_nurtureRun, running)) return;
      _nurtureRun = running;
      unawaited(
        running.catchError((Object error) async {
          if (!active ||
              !autoWatchEnabled ||
              navigation != navigationId ||
              !identical(_nurtureRun, running)) {
            return;
          }
          final message = error is StateError
              ? error.message.toString()
              : 'Không thể tiếp tục nuôi qua Accessibility.';
          if (autoAdvance ||
              error is NurturePlaybackUnavailable ||
              error is NurtureDialogOpen) {
            debugPrint('Nurture transient error: $message');
            notify(
              '$message Đang chờ đọc lại trạng thái trên trang hiện tại; '
              'giữ nguyên thời hạn nuôi.',
            );
            _scheduleNurtureRecovery(navigation);
            return;
          }
          debugPrint('Accessibility nurture stopped: $message');
          notify(message);
          _cancelAutoWatchTimers();
          mutate(() => autoWatchEnabled = false);
          unawaited(stopAutoWatch());
        }),
      );
    } catch (_) {
      if (!active || !autoWatchEnabled) return;
      if (autoAdvance) {
        notify(
          'Chưa bật được thao tác nuôi; sẽ thử lại trong thời gian còn lại.',
        );
        _scheduleNurtureRecovery(navigation);
        return;
      }
      _cancelAutoWatchTimers();
      mutate(() => autoWatchEnabled = false);
      await _stopAutoWatch();
      notify('Không thể bật tự động xem. Hãy thử tải lại TikTok.');
    }
  }

  /// Retry the existing runner on the existing document. Its statistics,
  /// action ledger, search mode and draft state survive transient failures.
  /// Page navigation is reserved for explicit user actions.
  void _scheduleNurtureRecovery(int navigation) {
    if (_nurtureRecoveryTimer != null || !autoWatchEnabled) return;
    _nurtureRecoveryTimer = Timer(const Duration(seconds: 5), () async {
      _nurtureRecoveryTimer = null;
      if (!active ||
          !autoWatchEnabled ||
          autoRunFailing ||
          navigation != navigationId) {
        return;
      }
      if (!appActive || !_tikTokScreenVisible || verificationPaused) {
        _scheduleNurtureRecovery(navigation);
        return;
      }
      await startAutoWatch();
    });
  }

  void _resumeNurtureClock() {
    if (_nurtureScreenSince != null || _autoWatchStopsAt == null) return;
    _nurtureScreenSince = _now();
    _nurtureScreenTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_saveNurtureScreenTime()),
    );
  }

  void _pauseNurtureClock() {
    final since = _nurtureScreenSince;
    if (since == null) return;
    _nurtureScreenTime += _now().difference(since);
    _nurtureScreenSince = null;
    _nurtureScreenTicker?.cancel();
    _nurtureScreenTicker = null;
  }

  Future<void> _saveNurtureScreenTime() async {
    final since = _nurtureScreenSince;
    await _autoViewingSession?.recordScreenTime(
      _nurtureScreenTime +
          (since == null ? Duration.zero : _now().difference(since)),
    );
  }

  void _cancelAutoWatchTimers() {
    _pauseNurtureClock();
    _nurtureRecoveryTimer?.cancel();
    _nurtureRecoveryTimer = null;
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
      await _saveNurtureScreenTime();
      await _autoViewingSession?.finish(completed: true);
      _autoViewingSession = null;
      if (!active || !appActive) return;
      _watchCompletionPending = false;
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
    if (!appInBackground) _resumeNurtureClock();
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
    await _accessibilityNurture?.stop();
    if (finishViewing) {
      _accessibilityNurture = null;
      _accessibilityNurtureNavigation = null;
      _autoViewingNavigation = null;
      _autoViewingSegment = null;
    }
    await _autoViewingSession?.setForeground(false);
  }

  Future<void> _startAutoViewingStats() async {
    final email = configuration.loginUsername.trim();
    if (email.isEmpty) return;
    final navigation = navigationId;
    final session = _autoViewingSession ??= ManualViewingSession(
      repository: nurtureRepository ?? proxyStore.nurture,
      email: email,
      configurationId: configuration.configurationId,
      plan: _nurturePlan,
      onError: () => notify('Không thể lưu thống kê nuôi vào tài khoản.'),
      countsScreenTime: true,
    );
    await _saveNurtureScreenTime();
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
    await session.setForeground(true);
  }

  Future<void> _closeAutoViewing() async {
    _pauseNurtureClock();
    await stopAutoWatch(finishViewing: true);
    await _saveNurtureScreenTime();
    await _autoViewingSession?.finish(error: pageFailure != null);
  }

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
    mutate(() {
      autoWatchBusy = true;
      verificationPaused = false;
    });
    try {
      if (!autoWatchEnabled && launchAction == TikTokLaunchAction.browse) {
        final navigation = navigationId;
        mutate(() => loginConfirmed = false);
        final authenticated = await _accessibilityAuthenticated();
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

  void cancelAutoLogin({bool updateUi = true}) {
    _loginAccessibilityRunner?.cancel();
    loginOtpRequest?.cancel();
    loginOtpRequest = null;
    autoLoginAttempt++;
    if (updateUi && active) mutate(() => autoLoginBusy = false);
  }

  void cancelAutoSignup({bool updateUi = true}) {
    _signupCoordinateRunner?.cancel();
    signupOtpRequest?.cancel();
    signupOtpRequest = null;
    autoSignupAttempt++;
    if (updateUi && active) mutate(() => autoSignupBusy = false);
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

  OtpCodeRequest requestOtp({
    required bool signup,
    DateTime? notBefore,
    Set<String> rejectedCodes = const {},
  }) {
    final api = configuration.otpApi!;
    final reader =
        otpReaderFactory?.call(api) ??
        OtpApiClient(
          api,
          notBefore: signup
              ? null
              : notBefore ?? _now().subtract(const Duration(seconds: 30)),
          rejectedCodes: rejectedCodes,
        );
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
        // The setting can stay on while Android has not bound the service
        // (Samsung after an app update); nothing could be read or tapped.
        var running =
            await FlutterAccessibilityService.isAccessibilityServiceRunning();
        for (var i = 0; !running && i < 6 && active; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          running =
              await FlutterAccessibilityService.isAccessibilityServiceRunning();
        }
        if (!running) {
          await FlutterAccessibilityService.requestAccessibilityPermission();
          if (active) {
            notify(
              'Trợ năng đang bật nhưng dịch vụ chưa chạy. Hãy tắt rồi bật lại '
              'Trợ năng cho Tool TikTok; nếu vẫn không chạy, khởi động lại '
              'điện thoại rồi chạy lại.',
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
    } else if (action == 'captcha-layout') {
      // Read-only ADB diagnosis: no API request, refresh or gesture. Image
      // URLs and account data are deliberately omitted from the report.
      final challenge = RotateCaptchaChallenge.fromResult(
        await webViewController!.evaluateJavascript(
          source: readRotateCaptchaScript,
        ),
      );
      final snapshot = await SignupAccessibility().snapshot();
      final bounds = snapshot.viewport.bounds;
      if (challenge == null || !snapshot.ready || bounds.isEmpty) {
        return {'ok': false, 'reason': 'captcha-geometry-unavailable'};
      }
      List<double> point(double angle) {
        final p = challenge.screenPoint(bounds, angle);
        return [p.dx, p.dy];
      }

      result = {
        'ok': true,
        'viewport': [challenge.viewportWidth, challenge.viewportHeight],
        'webBounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
        'handle': [challenge.x, challenge.y],
        'travel': challenge.travel,
        'from': point(0),
        'mid': point(180),
        'end': point(360),
      };
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
    } else if (action == 'diagnose-web') {
      result = {
        'ok': true,
        'diagnosis': await signupAccessibility.diagnoseWeb(),
      };
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

  Future<void> autoSignup() async {
    if (useNativeWebView || _flowFinished || !usesCoordinateSignup) return;
    await _runCoordinateSignup();
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
        active &&
        !appInBackground &&
        autoSignupBusy &&
        autoSignupAttempt == attempt;
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
        isForeground: () => appActive,
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
        _signupNeedsLogin = runner.requiresLogin;
        await _markConfigurationRegistered();
        notify(
          runner.alreadyLoggedIn
              ? 'Tài khoản TikTok đã đăng nhập.'
              : runner.requiresLogin
              ? 'Đã tạo tài khoản TikTok. TikTok yêu cầu đăng nhập lại.'
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
    if (useNativeWebView || _flowFinished || !usesAccessibilityLogin) return;
    await _runAccessibilityLogin();
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
    final rejectedOtps = <String>{};
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
          final pending = requestOtp(
            signup: false,
            notBefore: runner?.otpRequestedAt?.subtract(
              const Duration(seconds: 5),
            ),
            rejectedCodes: rejectedOtps,
          );
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
        onOtpRejected: rejectedOtps.add,
        // Same GeckoSession: proxy, identity and the login attempt remain.
        reloadBlankPage: () async => webViewController?.reload(),
        cancelOtpRequest: () {
          request?.cancel();
          request = null;
          loginOtpRequest = null;
          activeLoginOtp = '';
        },
        onStatus: (status) {
          debugPrint('[Diag login] $status');
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
        bool? authenticated;
        try {
          authenticated = NurtureAccessibilityRunner.authenticated(
            await signupAccessibility.snapshot(),
          );
        } catch (_) {
          // The accessibility tree can be briefly unavailable on navigation.
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
      // A revoked session falls back to login; a failed one must not wait
      // for the watchdog before the run moves on.
      if (active && !_flowContinues) _failAutoFlow();
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

  void cancelAutoActions() {
    initialActionStarted = true;
    if (autoLoginBusy) cancelAutoLogin();
    if (autoSignupBusy) cancelAutoSignup();
  }

  Future<void> handlePageLoadComplete(Uri? url) async {
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
    notify(
      '${failure.title}\n${failure.message}',
      actionLabel: 'Thử lại',
      onAction: retryProxyWarning,
    );
    // An unavailable IP lookup alone is not evidence of a broken proxy.
    if (!ipCheck &&
        failure.isConnectionFailure &&
        (failure.code == 'HTTP 407' ||
            failure.code?.startsWith('ERR_PROXY_') == true ||
            failure.code == 'ERR_TUNNEL_CONNECTION_FAILED' ||
            failure.code == 'ERR_HTTPS_PROXY_TUNNEL_RESPONSE')) {
      _stopFailedConfiguration(
        'Proxy không kết nối được. Chuyển cấu hình tiếp theo.',
      );
    }
  }

  void showPageFailure(WebViewFailure failure) {
    if (!active) return;
    if (autoAdvance && autoWatchEnabled && !failure.isConnectionFailure) {
      notify('${failure.message} Sẽ thử lại và nuôi đến hết thời gian.');
      _scheduleNurtureRecovery(navigationId);
      return;
    }
    if (failure.isConnectionFailure) {
      _stopFailedConfiguration('${failure.title}. Chuyển cấu hình tiếp theo.');
    }
    _stopRotateCaptchaMonitor();
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
      final ip = await checker.check(userAgent: effectiveUserAgent);
      receiveProxyIp([checkNavigationId, ip ?? 'Không xác định']);
    } catch (_) {
      if (active && checkNavigationId == navigationId) {
        receiveProxyIp([checkNavigationId, 'Không xác định']);
      }
    } finally {
      if (identical(_ipChecker, checker)) _ipChecker = null;
    }
  }

  Future<void> updateNavigationState() async {
    if (!active) return;
    mutate(() {
      loadingProgress = 100;
    });
  }

  Future<void> onWebViewCreated(GeckoController controller) async {
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
    if (active) {
      mutate(() {
        _effectiveUserAgent = configuration.userAgent;
        browserIdentityReady = true;
        if (useNativeWebView) initialActionStarted = true;
      });
    }
  }

  void onLoadStart(GeckoController controller, Uri? url) {
    if (!active) return;
    _nurtureRecoveryTimer?.cancel();
    _nurtureRecoveryTimer = null;
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

  void onProgressChanged(GeckoController controller, int progress) {
    if (!active) return;
    mutate(() {
      loadingProgress = progress;
    });
  }

  Future<void> onLoadStop(GeckoController controller, Uri? url) async {
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
    GeckoController controller,
    GeckoWebResourceRequest request,
    GeckoWebResourceError error,
  ) {
    if (error.description.contains('net::ERR_ABORTED') ||
        error.type == GeckoWebResourceErrorType.cancelled) {
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

  void goHome() {
    _userTookOver();
    cancelAutoActions();
    unawaited(
      webViewController?.loadUrl(
        urlRequest: GeckoUrlRequest(
          url: Uri.parse(tiktokHomeUrl),
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
    // Navigate the existing GeckoSession: proxy, UA and context remain intact.
    await controller.loadUrl(
      urlRequest: GeckoUrlRequest(
        url: Uri.parse(browserCheckUrl),
        headers: navigationHeaders,
      ),
    );
  }

  void reloadPage() {
    cancelAutoActions();
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

class _RotateCaptchaFailure implements Exception {
  const _RotateCaptchaFailure(this.message);
  final String message;
}

class _RotateCaptchaInspectionUnavailable implements Exception {}
