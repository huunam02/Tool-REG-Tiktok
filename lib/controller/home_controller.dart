import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../core/app_configuration.dart';
import '../core/services/remote_config_service.dart';
import '../core/app_session.dart';
import '../core/nurture_data.dart';
import '../core/proxy_geolocation.dart';
import '../core/proxy_local_ip.dart';
import '../core/configuration_data.dart';
import '../core/desktop_user_agents.dart';
import '../core/otp_api.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/signup_failure.dart';
import '../core/webview_proxy.dart';
import '../core/webview_user_agent.dart';
import '../core/tiktok_flow_result.dart';
import '../core/tiktok_launch_action.dart';
import 'app_controller.dart';

/// What an automatic run does with each eligible configuration.
enum AutoRunMode {
  /// Sign up every unregistered configuration that has not failed.
  signup,

  /// Log in to and nurture every registered configuration.
  nurture,

  /// Sign up again every configuration listed in Cấu hình lỗi.
  retryFailed;

  bool get signsUp => this != nurture;
}

class HomeController extends AppController
    with GetSingleTickerProviderStateMixin, WidgetsBindingObserver {
  HomeController({
    required this.initialUserAgent,
    required this.initialOtpSettings,
    ProxyStore? store,
    OtpSettingsStore? otpSettingsStore,
    DateTime Function()? now,
    Random? workflowRandom,
    Future<bool> Function()? readLoginSession,
    Future<void> Function()? clearSession,
  }) : store = store ?? ProxyStore.instance,
       _clearSession = clearSession ?? clearAppSession,
       _now = now ?? DateTime.now,
       _workflowRandom = workflowRandom ?? Random(),
       _readLoginSession = readLoginSession ?? hasTikTokLoginSession,
       otpSettingsStore = otpSettingsStore ?? OtpSettingsStore.instance;

  final String initialUserAgent;
  final OtpApiSettings initialOtpSettings;
  final ProxyStore store;
  final OtpSettingsStore otpSettingsStore;
  final DateTime Function() _now;
  final Random _workflowRandom;
  final Future<bool> Function() _readLoginSession;
  final Future<void> Function() _clearSession;
  int _profileLoadGeneration = 0;
  bool hasCurrentAccountSession = false;
  bool _appActive = true;

  /// The automatic run over configurations, or null when idle.
  AutoRunMode? autoRun;
  int autoRunTotal = 0;
  int autoRunSucceeded = 0;
  int autoRunFailed = 0;
  String autoRunEmail = '';

  /// When the run opens its next configuration; null while one is open.
  DateTime? autoRunNextAt;
  int _autoRunGeneration = 0;
  bool get autoRunning => autoRun != null;
  int get autoRunFinished => autoRunSucceeded + autoRunFailed;

  /// Pause between two configurations of an automatic run.
  static const minAutoRunPause = Duration(seconds: 5);
  static const maxAutoRunPause = Duration(seconds: 15);

  bool _autoRunCurrent(int generation) =>
      active && autoRunning && generation == _autoRunGeneration;

  /// Run every eligible configuration in turn: signup runs the unregistered
  /// ones, nurture logs in to each registered one. Each screen returns a
  /// [TikTokFlowResult]; closing a screen (no result) stops the run.
  Future<void> startAutoRun(
    AutoRunMode mode,
    Future<TikTokFlowResult?> Function(
      AppConfiguration configuration,
      TikTokLaunchAction action,
    )
    navigate,
  ) async {
    if (busy || proxyLoadFailed) return;
    final generation = ++_autoRunGeneration;
    final visited = <int>{};
    final preferredId = currentProxy?.configurationId;
    mutate(() {
      autoRun = mode;
      autoRunTotal = 0;
      autoRunSucceeded = 0;
      autoRunFailed = 0;
      autoRunEmail = '';
      autoRunNextAt = null;
    });
    var stoppedByScreen = false;
    try {
      final eligible = await _autoRunCandidates(mode, visited);
      if (!_autoRunCurrent(generation)) return;
      mutate(() => autoRunTotal = eligible.length);
      var first = true;
      while (_autoRunCurrent(generation)) {
        final candidates = await _autoRunCandidates(mode, visited);
        if (!_autoRunCurrent(generation)) return;
        if (candidates.isEmpty) break;
        final next = first
            ? candidates.firstWhere(
                (entry) => entry.id == preferredId,
                orElse: () => candidates.first,
              )
            : candidates.first;
        if (!first && !await _pauseBeforeNextConfiguration(generation)) {
          return;
        }
        first = false;
        visited.add(next.id);
        mutate(() {
          autoRunEmail = next.account?.email ?? '';
          if (autoRunTotal < autoRunFinished + 1) {
            autoRunTotal = autoRunFinished + 1;
          }
        });
        if (!await _selectAutoRunConfiguration(next, generation)) {
          if (!_autoRunCurrent(generation)) return;
          mutate(() => autoRunFailed++);
          if (mode.signsUp) await _recordOpenFailure(next);
          continue;
        }
        var opened = false;
        TikTokFlowResult? result;
        _lastNotice = null;
        await openTikTok(
          mode.signsUp ? TikTokLaunchAction.signup : TikTokLaunchAction.login,
          (configuration, action) async {
            opened = true;
            result = await navigate(configuration, action);
          },
          automatic: true,
        );
        if (!_autoRunCurrent(generation)) return;
        if (opened && result == null) {
          stoppedByScreen = true;
          break;
        }
        mutate(() {
          if (!opened || result == TikTokFlowResult.failed) {
            autoRunFailed++;
          } else {
            autoRunSucceeded++;
          }
        });
        if (!opened && mode.signsUp) await _recordOpenFailure(next);
        // Show the finished account's new status during the pause.
        await restoreProxy();
        if (_autoRunCurrent(generation)) await loadNurtureAccounts();
        if (_autoRunCurrent(generation)) await loadFailedConfigurations();
      }
    } catch (_) {
      if (_autoRunCurrent(generation)) {
        notify('Tự chạy gặp lỗi khi đọc cấu hình. Đã dừng.');
      }
    } finally {
      if (active && generation == _autoRunGeneration) {
        final finished = autoRunFinished;
        final succeeded = autoRunSucceeded;
        final failed = autoRunFailed;
        mutate(() {
          autoRun = null;
          autoRunNextAt = null;
          autoRunEmail = '';
        });
        final what = switch (mode) {
          AutoRunMode.signup => 'đăng ký',
          AutoRunMode.nurture => 'nuôi',
          AutoRunMode.retryFailed => 'đăng ký lại',
        };
        notify(
          stoppedByScreen
              ? 'Đã dừng tự $what sau $finished cấu hình ($succeeded xong, $failed lỗi).'
              : finished == 0
              ? switch (mode) {
                  AutoRunMode.signup =>
                    'Không còn cấu hình chưa đăng ký có tài khoản.',
                  AutoRunMode.nurture =>
                    'Chưa có tài khoản đã đăng ký để nuôi.',
                  AutoRunMode.retryFailed =>
                    'Không có cấu hình lỗi để chạy lại.',
                }
              : 'Đã tự $what $finished cấu hình: $succeeded xong, $failed lỗi.',
          duration: const Duration(seconds: 6),
        );
        await restoreProxy();
        if (active) await loadNurtureAccounts();
        if (active) await loadFailedConfigurations();
      }
    }
  }

  void stopAutoRun() {
    if (!autoRunning) return;
    _autoRunGeneration++;
    final finished = autoRunFinished;
    mutate(() {
      autoRun = null;
      autoRunNextAt = null;
      autoRunEmail = '';
    });
    notify('Đã dừng tự chạy sau $finished cấu hình.');
    unawaited(restoreProxy());
  }

  Future<List<SavedProxy>> _autoRunCandidates(
    AutoRunMode mode,
    Set<int> visited,
  ) async {
    final wanted = mode.signsUp
        ? AccountStatus.unregistered
        : AccountStatus.registered;
    // Same order as the Quản lý cấu hình list (newest first). Failed
    // configurations wait for Cấu hình lỗi > Đăng ký lại.
    return (await store.list())
        .where(
          (entry) =>
              entry.account != null &&
              entry.statusAccount == wanted &&
              (!mode.signsUp ||
                  entry.signupFailed == (mode == AutoRunMode.retryFailed)) &&
              !visited.contains(entry.id),
        )
        .toList()
      ..sort((first, second) => second.id.compareTo(first.id));
  }

  Future<bool> _pauseBeforeNextConfiguration(int generation) async {
    final range = (maxAutoRunPause - minAutoRunPause).inMilliseconds;
    final pause =
        minAutoRunPause +
        Duration(milliseconds: _workflowRandom.nextInt(range + 1));
    mutate(() => autoRunNextAt = _now().add(pause));
    // Accessibility automation needs the app in the foreground.
    while (_autoRunCurrent(generation) &&
        (!_appActive || _now().isBefore(autoRunNextAt!))) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!_autoRunCurrent(generation)) return false;
    mutate(() => autoRunNextAt = null);
    return true;
  }

  /// Each account starts from an empty WebView session on its own proxy.
  Future<bool> _selectAutoRunConfiguration(
    SavedProxy next,
    int generation,
  ) async {
    final email = next.account?.email ?? '';
    try {
      await _clearSession();
      if (!_autoRunCurrent(generation)) return false;
      await store.useSaved(next.id);
      await store.setCurrentAccountLoggedIn(next.id, email, false);
      if (!_autoRunCurrent(generation)) return false;
      await restoreProxy();
      if (!_autoRunCurrent(generation)) return false;
      if (proxyLoadFailed ||
          currentProxy?.configurationId != next.id ||
          currentProxy?.account?.email != email) {
        throw StateError('Configuration changed');
      }
      return true;
    } catch (_) {
      if (_autoRunCurrent(generation)) {
        notify('Không thể chuyển sang cấu hình $email. Bỏ qua cấu hình này.');
      }
      return false;
    }
  }

  /// The latest message shown on Home: why a configuration could not open.
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

  Future<void> _recordOpenFailure(SavedProxy entry) async {
    final email = entry.account?.email ?? '';
    try {
      await store.recordSignupFailure(
        entry.id,
        email,
        message: _lastNotice ?? 'Không mở được TikTok cho cấu hình này.',
        step: 'Mở cấu hình',
      );
    } catch (_) {
      // The run continues; the summary still counts this configuration.
    }
  }

  List<FailedConfiguration> failedConfigurations = [];
  bool loadingFailures = false;
  bool failuresLoadFailed = false;

  Future<void> loadFailedConfigurations() async {
    if (loadingFailures) return;
    mutate(() => loadingFailures = true);
    try {
      final failed = await store.listFailedConfigurations();
      if (active) {
        mutate(() {
          failedConfigurations = failed;
          failuresLoadFailed = false;
        });
      }
    } catch (_) {
      if (active) mutate(() => failuresLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingFailures = false);
    }
  }

  /// Take a configuration out of Cấu hình lỗi; its log is kept.
  Future<void> dismissFailure(int configurationId) async {
    if (busy) return;
    try {
      await store.clearSignupFailure(configurationId);
    } catch (_) {
      if (active) notify('Không thể cập nhật cấu hình lỗi. Hãy thử lại.');
    }
    if (active) await loadFailedConfigurations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && !opening && !managingProxies && !autoRunning) {
      unawaited(refreshCurrentAccountSession());
    }
  }

  late String userAgent;
  late String directUserAgent;
  late OtpApiSettings otpSettings;
  ProxyProfile? currentProxy;
  late final TabController tabs;
  int tabIndex = 0;
  List<NurtureAccount> nurtureAccounts = [];
  int registeredAccountCount = 0;
  bool loadingAccounts = false;
  bool accountsLoadFailed = false;
  bool opening = false;
  bool loadingProxy = true;
  bool proxyLoadFailed = false;
  bool managingProxies = false;
  ProxyGeolocationLookup? _timeZoneLookup;
  late final ProxyStore proxyStore;
  bool get _actionBusy => opening || loadingProxy || managingProxies;
  bool get busy => _actionBusy || autoRunning;
  TikTokLaunchAction get accountAction => hasCurrentAccountSession
      ? TikTokLaunchAction.browse
      : currentProxy?.statusAccount == AccountStatus.registered
      ? TikTokLaunchAction.login
      : TikTokLaunchAction.signup;
  String get accountActionLabel => hasCurrentAccountSession
      ? 'Nuôi tiếp Account'
      : accountAction == TikTokLaunchAction.login
      ? 'Đăng nhập và nuôi Account'
      : 'Đăng ký tự động';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    userAgent = initialUserAgent;
    directUserAgent = initialUserAgent;
    otpSettings = initialOtpSettings;
    tabs = TabController(length: 3, vsync: this);
    tabs.addListener(() {
      if (tabIndex == tabs.index) return;
      mutate(() => tabIndex = tabs.index);
      if (tabIndex == 1) unawaited(loadNurtureAccounts());
      if (tabIndex == 2) unawaited(loadFailedConfigurations());
    });
    proxyStore = store;
    unawaited(restoreProxy());
    unawaited(loadNurtureAccounts());
    unawaited(loadFailedConfigurations());
  }

  Future<void> loadNurtureAccounts() async {
    if (loadingAccounts) return;
    mutate(() => loadingAccounts = true);
    try {
      final accounts = await store.nurture.listAccounts();
      final registered = (await store.list())
          .where(
            (entry) =>
                entry.account != null &&
                entry.statusAccount == AccountStatus.registered,
          )
          .toList();
      // Only registered accounts can be nurtured; others stay in Cấu hình.
      final registeredKeys = {
        for (final entry in registered) nurtureAccountKey(entry.account!.email),
      };
      if (active) {
        mutate(() {
          nurtureAccounts = accounts
              .where((account) => registeredKeys.contains(account.key))
              .toList();
          registeredAccountCount = registered.length;
          accountsLoadFailed = false;
        });
      }
    } catch (_) {
      if (active) mutate(() => accountsLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingAccounts = false);
    }
  }

  Future<void> openManualViewing(
    NurtureAccount account,
    Future<void> Function(AppConfiguration, NurturePlan) navigate,
  ) async {
    if (busy || account.configurationId == null) return;
    mutate(() => managingProxies = true);
    try {
      final configurations = await store.list();
      final selected = configurations
          .where((row) => row.id == account.configurationId)
          .firstOrNull;
      if (selected == null) throw StateError('Configuration deleted');
      final current = await store.getCurrentProfile();
      if (!sameProfile(current, selected)) await clearAppSession();
      if (!active) return;
      await store.useSaved(selected.id);
      await restoreProxy();
    } catch (_) {
      if (active) notify('Không thể chọn cấu hình của tài khoản. Hãy thử lại.');
      return;
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
    if (!active) {
      return;
    }
    final plan = NurturePlan.choose(RemoteConfig.searchKeywords);
    await openTikTok(
      TikTokLaunchAction.browse,
      (configuration, _) => navigate(configuration, plan),
    );
  }

  Future<void> restoreProxy() async {
    final generation = ++_profileLoadGeneration;
    mutate(() => loadingProxy = true);
    try {
      final profile = await proxyStore.getCurrentProfile();
      final restoredDirectUserAgent = profile == null && currentProxy != null
          ? await loadDirectDesktopUserAgent()
          : directUserAgent;
      final hasSession =
          profile?.account?.email.trim().isNotEmpty == true &&
          await proxyStore.canReuseCurrentAccountSession() &&
          await _readLoginSession();
      if (!active || generation != _profileLoadGeneration) return;
      mutate(() {
        currentProxy = profile;
        hasCurrentAccountSession = hasSession;
        directUserAgent = restoredDirectUserAgent;
        userAgent = profile?.userAgent ?? restoredDirectUserAgent;
        proxyLoadFailed = false;
      });
    } catch (_) {
      if (active && generation == _profileLoadGeneration) {
        mutate(() {
          proxyLoadFailed = true;
          hasCurrentAccountSession = false;
        });
      }
    } finally {
      if (active && generation == _profileLoadGeneration) {
        mutate(() => loadingProxy = false);
      }
    }
  }

  Future<void> refreshCurrentAccountSession() async {
    final profile = currentProxy;
    var hasSession = false;
    if (profile?.account?.email.trim().isNotEmpty == true) {
      try {
        hasSession =
            await proxyStore.canReuseCurrentAccountSession() &&
            await _readLoginSession();
      } catch (_) {
        // A failed session check must not block the existing login action.
      }
    }
    if (active && identical(profile, currentProxy)) {
      mutate(() => hasCurrentAccountSession = hasSession);
    }
  }

  Future<void> manageProxies(Future<void> Function() navigate) async {
    if (busy) return;
    mutate(() => managingProxies = true);
    try {
      await navigate();
      if (active) await restoreProxy();
      if (active) await loadNurtureAccounts();
      if (active) await loadFailedConfigurations();
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
  }

  @override
  void onClose() {
    _autoRunGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timeZoneLookup?.cancel();
    tabs.dispose();
    super.onClose();
  }

  Future<void> openTikTok(
    TikTokLaunchAction action,
    Future<void> Function(
      AppConfiguration configuration,
      TikTokLaunchAction action,
    )
    navigate, {
    bool automatic = false,
  }) async {
    if ((automatic ? _actionBusy : busy) || proxyLoadFailed) return;
    final account = currentProxy?.account;
    if (action != TikTokLaunchAction.browse) {
      if (account == null) {
        notify(
          'Chọn cấu hình có tài khoản trong Quản lý cấu hình trước khi chạy.',
        );
        return;
      }
      try {
        account.validate();
      } on FormatException {
        notify(
          'Bổ sung email, mật khẩu TikTok và mật khẩu email OTP trong Quản lý cấu hình.',
        );
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => opening = true);
    try {
      final browserUserAgent = await resolveWebViewUserAgent(userAgent);
      if (!active) return;
      if (needsAndroidDesktopIdentity) {
        final profile = currentProxy;
        mutate(() {
          userAgent = browserUserAgent;
          if (profile != null) {
            currentProxy = profile.copyWith(userAgent: browserUserAgent);
          }
        });
      }
      final proxy = currentProxy?.proxy;
      final otpApi = otpApiFor(action);
      await configureWebViewProxy(proxy);
      if (!active) return;
      var timeZone = currentProxy?.timeZoneId ?? '';
      if (needsAndroidDesktopIdentity && proxy != null && timeZone.isEmpty) {
        final lookup = ProxyGeolocationLookup();
        _timeZoneLookup = lookup;
        final location = await lookup.lookup(
          proxy: proxy,
          userAgent: browserUserAgent,
        );
        if (!active) return;
        timeZone = location.timeZoneId;
        final profile = currentProxy;
        if (profile?.configurationId != null) {
          final cached = await store.cacheCurrentTimeZone(
            profile!.configurationId!,
            proxy,
            timeZone,
          );
          if (!cached) throw StateError('Cấu hình đang dùng đã thay đổi.');
        }
        if (!active) return;
        if (profile != null) {
          mutate(() => currentProxy = profile.copyWith(timeZoneId: timeZone));
        }
      }
      // Stable per proxy endpoint; WebRTC stays disabled, so it never reaches pages.
      final localIp = await loadProxyLocalIp(proxy);
      if (!active) return;
      final configuration = AppConfiguration(
        configurationId: currentProxy?.configurationId,
        userAgent: browserUserAgent,
        proxy: proxy,
        webViewLocalIp: localIp,
        webViewTimeZone:
            needsAndroidDesktopIdentity && proxy != null && timeZone.isNotEmpty
            ? timeZone
            : null,
        comments: RemoteConfig.autoComments,
        searchKeywords: RemoteConfig.searchKeywords,
        signupEmail: account?.email ?? '',
        signupPassword: account?.password ?? '',
        loginUsername: account?.email ?? '',
        loginPassword: account?.password ?? '',
        signupMailboxPassword: account?.mailboxPassword ?? '',
        loginMailboxPassword: account?.mailboxPassword ?? '',
        otpApi: otpApi,
        nurtureAfterSignup: currentProxy?.nurtureAfterSignup ?? false,
        birthday: action == TikTokLaunchAction.signup
            ? AppConfiguration.randomSignupBirthday()
            : null,
      );
      await navigate(configuration, action);
      if (automatic) return;
      if (active && action == TikTokLaunchAction.signup) {
        await restoreProxy();
      } else if (active) {
        await refreshCurrentAccountSession();
      }
      if (active) await loadNurtureAccounts();
    } on FormatException catch (error) {
      if (!active) return;
      notify(error.message);
    } on PlatformException catch (error) {
      if (!active) return;
      notify(
        error.code == 'proxy_unsupported'
            ? error.message ?? 'Thiết bị không hỗ trợ proxy.'
            : 'Không thể áp dụng proxy. Hãy kiểm tra cấu hình rồi thử lại.',
      );
    } catch (_) {
      if (!active) return;
      notify('Không thể mở TikTok. Hãy thử lại.');
    } finally {
      _timeZoneLookup?.cancel();
      _timeZoneLookup = null;
      if (active) mutate(() => opening = false);
    }
  }

  OtpApiConfiguration? otpApiFor(TikTokLaunchAction action) {
    if (action == TikTokLaunchAction.browse) return null;
    if (otpSettings.token.trim().isEmpty) {
      throw const FormatException(
        'Token OTP API chưa được cấu hình trong Remote Config.',
      );
    }
    try {
      return otpSettings.toConfiguration();
    } on FormatException {
      throw const FormatException(
        'URL OTP API trong Remote Config phải là HTTP/HTTPS hợp lệ.',
      );
    }
  }
}
