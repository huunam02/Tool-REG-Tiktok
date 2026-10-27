import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../app_configuration.dart';
import '../services/remote_config_service.dart';
import '../app_session.dart';
import '../account_sessions.dart';
import '../account_proxy.dart';
import '../gecko_browser.dart';
import '../nurture_data.dart';
import '../proxy_geolocation.dart';
import '../configuration_data.dart';
import '../desktop_user_agents.dart';
import '../otp_api.dart';
import '../otp_settings_store.dart';
import '../proxy_store.dart';
import '../signup_failure.dart';
import '../webview_proxy.dart';
import '../webview_proxy_ip.dart';
import '../webview_user_agent.dart';
import '../tiktok_flow_result.dart';
import '../tiktok_launch_action.dart';
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
  /// [firstId] runs first when eligible; otherwise the selected
  /// configuration. The rest follow [order] (the list a tab shows), then
  /// the Quản lý cấu hình order.
  Future<void> startAutoRun(
    AutoRunMode mode,
    Future<TikTokFlowResult?> Function(
      AppConfiguration configuration,
      TikTokLaunchAction action,
    )
    navigate, {
    int? firstId,
    List<int> order = const [],
    int? onlyId,
  }) async {
    if (busy || proxyLoadFailed) return;
    final generation = ++_autoRunGeneration;
    final visited = <int>{};
    final preferredId = firstId ?? currentProxy?.configurationId;
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
      final eligible = await _autoRunCandidates(mode, visited, onlyId);
      if (!_autoRunCurrent(generation)) return;
      mutate(() => autoRunTotal = eligible.length);
      var first = true;
      while (_autoRunCurrent(generation)) {
        final candidates = _inOrder(
          await _autoRunCandidates(mode, visited, onlyId),
          order,
        );
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
        if (_autoRunCurrent(generation)) await loadSignupConfigurations();
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
        if (active) await loadSignupConfigurations();
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

  /// [onlyId] limits the run to that one configuration (Đăng ký on a card).
  Future<List<SavedProxy>> _autoRunCandidates(
    AutoRunMode mode,
    Set<int> visited, [
    int? onlyId,
  ]) async {
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
              (onlyId == null || entry.id == onlyId) &&
              !visited.contains(entry.id),
        )
        .toList()
      ..sort((first, second) => second.id.compareTo(first.id));
  }

  /// Stable: configurations missing from [order] keep their place after it.
  static List<SavedProxy> _inOrder(List<SavedProxy> entries, List<int> order) {
    if (order.isEmpty) return entries;
    int rank(SavedProxy entry) {
      final index = order.indexOf(entry.id);
      return index < 0 ? order.length : index;
    }

    final ranked = [for (var i = 0; i < entries.length; i++) (i, entries[i])]
      ..sort((a, b) {
        final byRank = rank(a.$2).compareTo(rank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final (_, entry) in ranked) entry];
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

  /// Mount only this configuration’s cookie jar before opening its WebView.
  Future<bool> _selectAutoRunConfiguration(
    SavedProxy next,
    int generation,
  ) async {
    final email = next.account?.email ?? '';
    try {
      if (autoRun?.signsUp == true) {
        validateSignupProxy(next, await store.list());
      }
      await _saveCurrentSession();
      if (!_autoRunCurrent(generation)) return false;
      await AccountSessions.activate(
        next.id,
        email,
        clear: _clearSession,
        fresh: autoRun?.signsUp == true,
      );
      if (!_autoRunCurrent(generation)) return false;
      await store.useSaved(next.id);
      await store.setCurrentAccountLoggedIn(
        next.id,
        email,
        await _readLoginSession(),
      );
      if (!_autoRunCurrent(generation)) return false;
      await restoreProxy();
      if (!_autoRunCurrent(generation)) return false;
      if (proxyLoadFailed ||
          currentProxy?.configurationId != next.id ||
          currentProxy?.account?.email != email) {
        throw StateError('Configuration changed');
      }
      return true;
    } catch (error) {
      if (_autoRunCurrent(generation)) {
        notify(
          error is FormatException
              ? error.message
              : 'Không thể chuyển sang cấu hình $email. Bỏ qua cấu hình này.',
        );
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

  /// Đăng ký tab: unregistered configurations with an account and no failed
  /// signup, in the order an automatic signup run walks them.
  List<SavedProxy> signupConfigurations = [];
  bool loadingSignups = false;
  bool signupsLoadFailed = false;
  int? _signupPriorityId;

  /// The configuration the signup run starts with: the one tapped, else the
  /// top of the list.
  SavedProxy? get signupPriority =>
      signupConfigurations
          .where((entry) => entry.id == _signupPriorityId)
          .firstOrNull ??
      signupConfigurations.firstOrNull;

  void selectSignupPriority(int id) {
    if (busy) return;
    mutate(() => _signupPriorityId = id);
  }

  int? _nurturePriorityId, _failedPriorityId;

  /// Nuôi tab: the account nurtured first, the tapped one or the top one.
  NurtureAccount? get nurturePriority {
    final runnable = nurtureAccounts.where((a) => a.configurationId != null);
    return runnable
            .where((a) => a.configurationId == _nurturePriorityId)
            .firstOrNull ??
        runnable.firstOrNull;
  }

  void selectNurturePriority(int configurationId) {
    if (busy) return;
    mutate(() => _nurturePriorityId = configurationId);
  }

  /// Cấu hình lỗi tab: the configuration signed up again first.
  FailedConfiguration? get failedPriority =>
      failedConfigurations
          .where((f) => f.configuration.id == _failedPriorityId)
          .firstOrNull ??
      failedConfigurations.firstOrNull;

  void selectFailedPriority(int configurationId) {
    if (busy) return;
    mutate(() => _failedPriorityId = configurationId);
  }

  Future<void> loadSignupConfigurations() async {
    if (loadingSignups) return;
    mutate(() => loadingSignups = true);
    try {
      final pending = await _autoRunCandidates(AutoRunMode.signup, const {});
      if (active) {
        mutate(() {
          signupConfigurations = pending;
          signupsLoadFailed = false;
        });
      }
    } catch (_) {
      if (active) mutate(() => signupsLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingSignups = false);
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
    // A dismissed failure is eligible for the normal signup run again.
    if (active) await loadSignupConfigurations();
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
  static const configurationTab = 0, signupTab = 1, nurtureTab = 2;
  static const failedTab = 3;
  List<NurtureAccount> nurtureAccounts = [];
  int registeredAccountCount = 0;
  bool loadingAccounts = false;
  bool accountsLoadFailed = false;
  bool opening = false;
  bool loadingProxy = true;
  bool proxyLoadFailed = false;
  bool managingProxies = false;
  ProxyGeolocationLookup? _timeZoneLookup;
  WebViewProxyIpChecker? _proxyProbe;
  late final ProxyStore proxyStore;
  bool get _actionBusy => opening || loadingProxy || managingProxies;
  bool selectingNurture = false;
  bool get busy => _actionBusy || autoRunning || selectingNurture;
  TikTokLaunchAction get accountAction => hasCurrentAccountSession
      ? TikTokLaunchAction.browse
      : currentProxy?.statusAccount == AccountStatus.registered
      ? TikTokLaunchAction.login
      : TikTokLaunchAction.signup;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    userAgent = initialUserAgent;
    directUserAgent = initialUserAgent;
    otpSettings = initialOtpSettings;
    tabs = TabController(length: 4, vsync: this);
    tabs.addListener(() {
      if (tabIndex == tabs.index) return;
      mutate(() => tabIndex = tabs.index);
      if (tabIndex == signupTab) unawaited(loadSignupConfigurations());
      if (tabIndex == nurtureTab) unawaited(loadNurtureAccounts());
      if (tabIndex == failedTab) unawaited(loadFailedConfigurations());
    });
    proxyStore = store;
    unawaited(restoreProxy());
    unawaited(loadNurtureAccounts());
    unawaited(loadFailedConfigurations());
    unawaited(loadSignupConfigurations());
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
      if (active) await loadSignupConfigurations();
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
  }

  @override
  void onClose() {
    _autoRunGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timeZoneLookup?.cancel();
    _proxyProbe?.cancel();
    tabs.dispose();
    super.onClose();
  }

  /// Quản lý cấu hình > Kiểm tra IP: load [entry] in a fresh session (proxy,
  /// User-Agent, time zone, GPU), then open WhatIsMyBrowser with it. A check
  /// leaves the configuration's Đã dùng state unchanged.
  Future<void> checkConfiguration(
    SavedProxy entry,
    Future<void> Function(AppConfiguration configuration) navigate,
  ) async {
    if (opening || loadingProxy || autoRunning || checkingConfiguration) {
      return;
    }
    mutate(() => checkingConfiguration = true);
    try {
      await _saveCurrentSession();
      await AccountSessions.activate(
        entry.id,
        entry.account?.email ?? '',
        clear: _clearSession,
      );
      await store.useSaved(entry.id);
      await store.setCurrentAccountLoggedIn(
        entry.id,
        entry.account?.email ?? '',
        await _readLoginSession(),
      );
      if (!entry.hasBeenUsed) await store.setUsed(entry.id, false);
      await restoreProxy();
      if (!active) return;
      if (proxyLoadFailed || currentProxy?.configurationId != entry.id) {
        throw StateError('Configuration changed');
      }
      await openTikTok(
        TikTokLaunchAction.browse,
        (configuration, _) => navigate(configuration),
        checking: true,
      );
    } catch (_) {
      if (active) {
        notify('Không thể nạp cấu hình ${entry.name}. Hãy thử lại.');
      }
    } finally {
      if (active) mutate(() => checkingConfiguration = false);
    }
  }

  bool checkingConfiguration = false;

  Future<void> _saveCurrentSession() async {
    final profile = currentProxy;
    final id = profile?.configurationId;
    if (id != null) {
      if (await store.canReuseCurrentAccountSession() &&
          await _readLoginSession()) {
        await AccountSessions.save(id, profile?.account?.email ?? '');
      }
    }
  }

  /// Open one account from Nuôi, mounting its saved cookies and proxy first.
  Future<void> nurtureAccount(
    int configurationId,
    Future<void> Function(AppConfiguration, TikTokLaunchAction) navigate,
  ) async {
    if (busy || proxyLoadFailed) return;
    mutate(() => selectingNurture = true);
    try {
      final entries = await store.list();
      final next = entries
          .where((entry) => entry.id == configurationId)
          .firstOrNull;
      if (next == null ||
          next.account == null ||
          next.statusAccount != AccountStatus.registered) {
        throw const FormatException(
          'Tài khoản này chưa đăng ký hoặc cấu hình đã bị xóa.',
        );
      }
      await _saveCurrentSession();
      if (!active) return;
      final email = next.account!.email;
      await AccountSessions.activate(next.id, email, clear: _clearSession);
      if (!active) return;
      await store.useSaved(next.id);
      await store.setCurrentAccountLoggedIn(
        next.id,
        email,
        await _readLoginSession(),
      );
      await restoreProxy();
      if (!active) return;
      if (proxyLoadFailed ||
          currentProxy?.configurationId != next.id ||
          currentProxy?.account?.email != email) {
        throw StateError('Configuration changed');
      }
      await openTikTok(TikTokLaunchAction.login, navigate, automatic: true);
    } on FormatException catch (error) {
      if (active) notify(error.message);
    } catch (_) {
      if (active) notify('Không thể mở tài khoản để nuôi. Hãy thử lại.');
    } finally {
      if (active) {
        await restoreProxy();
        await loadNurtureAccounts();
        mutate(() => selectingNurture = false);
      }
    }
  }

  Future<void> openTikTok(
    TikTokLaunchAction action,
    Future<void> Function(
      AppConfiguration configuration,
      TikTokLaunchAction action,
    )
    navigate, {
    bool automatic = false,
    bool checking = false,
  }) async {
    // A check runs from Quản lý cấu hình, which keeps managingProxies set.
    final blocked = checking
        ? opening || loadingProxy || autoRunning
        : automatic
        ? _actionBusy
        : busy;
    if (blocked || proxyLoadFailed) return;
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
          'Bổ sung email, mật khẩu TikTok và Data Mail trong Quản lý cấu hình.',
        );
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => opening = true);
    var vpnStarted = false;
    try {
      final profileId = currentProxy?.configurationId;
      if (action == TikTokLaunchAction.signup && profileId != null) {
        validateSignupProxy(currentProxy!, await store.list());
      }
      if (!automatic && !checking && profileId != null) {
        await AccountSessions.activate(
          profileId,
          account?.email ?? '',
          clear: _clearSession,
          fresh: action == TikTokLaunchAction.signup,
          adoptLegacy: await store.canReuseCurrentAccountSession(),
        );
      }
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
      vpnStarted = proxy != null;
      await configureWebViewProxy(
        proxy,
        profileId: profileId?.toString() ?? 'default',
        label: currentProxy?.name ?? '',
      );
      if (!active) return;
      if (proxy != null) {
        // Open the browser only once the proxy answers through the tunnel; a
        // dead proxy or wrong credentials stop here instead of in TikTok.
        final probe = WebViewProxyIpChecker();
        _proxyProbe = probe;
        final ip = await probe.check(userAgent: browserUserAgent);
        if (!active) return;
        if (ip == null) {
          throw const FormatException(
            'Proxy không kết nối được. Hãy kiểm tra lại proxy của cấu hình.',
          );
        }
      }
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
      if (proxy != null) {
        await ProfileVpn.requireRunning(profileId?.toString() ?? 'default');
        if (!active) return;
      }
      final configuration = AppConfiguration(
        configurationId: currentProxy?.configurationId,
        userAgent: browserUserAgent,
        proxy: proxy,
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
        signupMailboxPassword: account?.dataMail ?? '',
        loginMailboxPassword: account?.dataMail ?? '',
        otpApi: otpApi,
        nurtureAfterSignup: currentProxy?.nurtureAfterSignup ?? false,
        nurtureSettings:
            currentProxy?.nurtureSettings ?? NurtureSettings.defaults,
        birthday: action == TikTokLaunchAction.signup
            ? AppConfiguration.randomSignupBirthday()
            : null,
      );
      await navigate(configuration, action);
      await _saveCurrentSession();
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
            : error.code.startsWith('vpn_') && error.message != null
            ? error.message!
            : 'Không thể áp dụng proxy. Hãy kiểm tra cấu hình rồi thử lại.',
      );
    } catch (_) {
      if (!active) return;
      notify('Không thể mở TikTok. Hãy thử lại.');
    } finally {
      _timeZoneLookup?.cancel();
      _timeZoneLookup = null;
      _proxyProbe?.cancel();
      _proxyProbe = null;
      // The VPN only serves the browser; Home and the pause between automatic
      // runs use the device network, and the next open starts it again.
      if (vpnStarted) {
        try {
          await configureWebViewProxy(null);
        } catch (_) {
          // The next open replaces the tunnel anyway.
        }
      }
      if (active) mutate(() => opening = false);
    }
  }

  OtpApiConfiguration? otpApiFor(TikTokLaunchAction action) {
    if (action == TikTokLaunchAction.browse) return null;
    try {
      return otpSettings.toConfiguration();
    } on FormatException {
      throw const FormatException(
        'URL OTP API trong Remote Config phải là HTTP/HTTPS hợp lệ.',
      );
    }
  }
}
