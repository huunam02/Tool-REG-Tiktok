import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../core/app_configuration.dart';
import '../core/desktop_user_agents.dart';
import '../core/otp_api.dart';
import '../core/otp_settings_store.dart';
import '../core/proxy_store.dart';
import '../core/webview_proxy.dart';
import '../core/webview_user_agent.dart';
import '../core/tiktok_launch_action.dart';
import 'app_controller.dart';

class HomeController extends AppController
    with GetSingleTickerProviderStateMixin {
  HomeController({
    required this.initialUserAgent,
    required this.initialOtpSettings,
    ProxyStore? store,
    OtpSettingsStore? otpSettingsStore,
  })  : store = store ?? ProxyStore.instance,
        otpSettingsStore = otpSettingsStore ?? OtpSettingsStore.instance;

  final String initialUserAgent;
  final OtpApiSettings initialOtpSettings;
  final ProxyStore store;
  final OtpSettingsStore otpSettingsStore;

  final formKey = GlobalKey<FormState>();
  final signupFormKey = GlobalKey<FormState>();
  final loginFormKey = GlobalKey<FormState>();
  late final TabController tabs;
  int selectedTab = 0;
  late String userAgent;
  late String directUserAgent;
  late OtpApiSettings otpSettings;
  ProxyProfile? currentProxy;
  late final TextEditingController comments;
  late final TextEditingController signupEmail;
  late final TextEditingController signupPassword;
  late final TextEditingController loginUsername;
  late final TextEditingController loginPassword;
  late final signupMailboxPassword = TextEditingController();
  late final loginMailboxPassword = TextEditingController();
  late final signupImportData = TextEditingController();
  late final loginImportData = TextEditingController();
  String? signupImportError;
  String? loginImportError;
  bool opening = false;
  bool loadingProxy = true;
  bool proxyLoadFailed = false;
  bool managingProxies = false;
  late final ProxyStore proxyStore;
  bool get busy => opening || loadingProxy || managingProxies;
  TikTokLaunchAction requestedAction = TikTokLaunchAction.browse;

  @override
  void onInit() {
    super.onInit();
    tabs = TabController(length: 3, vsync: this)..addListener(tabChanged);
    userAgent = initialUserAgent;
    directUserAgent = initialUserAgent;
    otpSettings = initialOtpSettings;
    final defaults = AppConfiguration.defaults(userAgent);
    comments = TextEditingController(text: defaults.comments.join('\n'));
    signupEmail = TextEditingController(text: defaults.signupEmail);
    signupPassword = TextEditingController(text: defaults.signupPassword);
    loginUsername = TextEditingController(text: defaults.loginUsername);
    loginPassword = TextEditingController(text: defaults.loginPassword);
    proxyStore = store;
    unawaited(restoreProxy());
  }

  Future<void> restoreProxy() async {
    mutate(() => loadingProxy = true);
    try {
      final profile = await proxyStore.getCurrentProfile();
      final restoredDirectUserAgent = profile == null && currentProxy != null
          ? await loadDirectDesktopUserAgent()
          : directUserAgent;
      if (!active) return;
      mutate(() {
        currentProxy = profile;
        directUserAgent = restoredDirectUserAgent;
        userAgent = profile?.userAgent ?? restoredDirectUserAgent;
        proxyLoadFailed = false;
      });
    } catch (_) {
      if (active) mutate(() => proxyLoadFailed = true);
    } finally {
      if (active) mutate(() => loadingProxy = false);
    }
  }

  Future<void> manageProxies(Future<void> Function() navigate) async {
    if (busy) return;
    mutate(() => managingProxies = true);
    try {
      await navigate();
      if (active) await restoreProxy();
    } finally {
      if (active) mutate(() => managingProxies = false);
    }
  }

  @override
  void onClose() {
    tabs.removeListener(tabChanged);
    tabs.dispose();
    for (final controller in [
      comments,
      signupEmail,
      signupPassword,
      loginUsername,
      loginPassword,
      signupMailboxPassword,
      loginMailboxPassword,
      signupImportData,
      loginImportData,
    ]) {
      controller.dispose();
    }
    super.onClose();
  }

  void tabChanged() {
    if (tabs.index == selectedTab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    mutate(() => selectedTab = tabs.index);
  }

  void updateOtpSettings(OtpApiSettings settings) =>
      mutate(() => otpSettings = settings);

  void clearImportError({required bool signup}) => mutate(() {
        if (signup) {
          signupImportError = null;
        } else {
          loginImportError = null;
        }
      });

  Future<void> pasteImportData({required bool signup}) async {
    if (!active || busy) return;
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!active || busy) return;
      final text = clipboard?.text;
      if (text == null || text.isEmpty) {
        notify('Clipboard không có dữ liệu để dán.');
        return;
      }
      final input = signup ? signupImportData : loginImportData;
      mutate(() {
        input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        if (signup) {
          signupImportError = null;
        } else {
          loginImportError = null;
        }
      });
      importAccountData(signup: signup);
    } catch (_) {
      if (active) notify('Không thể đọc dữ liệu từ clipboard.');
    }
  }

  void importAccountData({required bool signup}) {
    if (!active || busy) return;
    final input = signup ? signupImportData : loginImportData;
    // Strip copied line endings, while preserving password characters exactly.
    final line = input.text.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final parts = line.split('|');
    String? error;
    if (line.contains('\n') || line.contains('\r') || parts.length != 3) {
      error = 'Nhập một dòng: email|mật khẩu TikTok|mật khẩu email OTP.';
    } else if (!OtpApiConfiguration.isEmail(parts[0].trim())) {
      error = 'Email trong dữ liệu import không hợp lệ.';
    } else if (parts[1].trim().isEmpty || parts[2].trim().isEmpty) {
      error = 'Nhập đủ mật khẩu TikTok và mật khẩu email OTP.';
    }
    mutate(() {
      if (signup) {
        signupImportError = error;
      } else {
        loginImportError = error;
      }
      if (error != null) return;
      (signup ? signupEmail : loginUsername).text = parts[0].trim();
      (signup ? signupPassword : loginPassword).text = parts[1];
      (signup ? signupMailboxPassword : loginMailboxPassword).text = parts[2];
      input.clear();
    });
    if (error == null) {
      FocusManager.instance.primaryFocus?.unfocus();
      notify('Đã import thông tin ${signup ? 'đăng ký' : 'đăng nhập'}.');
    }
  }

  Future<void> openTikTok(
      TikTokLaunchAction action,
      Future<void> Function(
              AppConfiguration configuration, TikTokLaunchAction action)
          navigate) async {
    if (busy || proxyLoadFailed) return;
    mutate(() => requestedAction = action);
    final forms = [
      (0, formKey),
      if (action == TikTokLaunchAction.signup) (1, signupFormKey),
      if (action == TikTokLaunchAction.login) (2, loginFormKey),
    ];
    for (final (tab, form) in forms) {
      final invalidFields = form.currentState!.validateGranularly();
      if (invalidFields.isEmpty) continue;
      tabs.index = tab;
      // The invalid setting may live in another tab. Lay it out before scrolling.
      final fieldContext = invalidFields.first.context;
      await WidgetsBinding.instance.endOfFrame;
      if (!active || !fieldContext.mounted) return;
      await Scrollable.ensureVisible(fieldContext,
          duration: const Duration(milliseconds: 250), alignment: 0.2);
      return;
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
            currentProxy = ProxyProfile(
              proxy: profile.proxy,
              userAgent: browserUserAgent,
              name: profile.name,
              hasBeenUsed: profile.hasBeenUsed,
            );
          }
        });
      }
      final configuration = AppConfiguration(
        userAgent: browserUserAgent,
        proxy: currentProxy?.proxy,
        comments: AppConfiguration.parseComments(comments.text),
        signupEmail: signupEmail.text.trim(),
        signupPassword: signupPassword.text,
        loginUsername: loginUsername.text.trim(),
        loginPassword: loginPassword.text,
        signupMailboxPassword: signupMailboxPassword.text,
        loginMailboxPassword: loginMailboxPassword.text,
        otpApi: otpApiFor(action),
        birthday: action == TikTokLaunchAction.signup
            ? AppConfiguration.randomSignupBirthday()
            : null,
      );
      await configureWebViewProxy(configuration.proxy);
      if (!active) return;
      await navigate(configuration, action);
    } on FormatException catch (error) {
      if (!active) return;
      notify(error.message);
    } on PlatformException catch (error) {
      if (!active) return;
      notify(error.code == 'proxy_unsupported'
          ? error.message ?? 'Thiết bị không hỗ trợ proxy.'
          : 'Không thể áp dụng proxy. Hãy kiểm tra cấu hình rồi thử lại.');
    } catch (_) {
      if (!active) return;
      notify('Không thể mở TikTok. Hãy thử lại.');
    } finally {
      if (active) mutate(() => opening = false);
    }
  }

  OtpApiConfiguration? otpApiFor(TikTokLaunchAction action) {
    if (action == TikTokLaunchAction.browse) return null;
    if (otpSettings.token.trim().isEmpty) {
      throw const FormatException('Hãy cấu hình token OTP API trong Cài đặt.');
    }
    try {
      return otpSettings.toConfiguration();
    } on FormatException {
      throw const FormatException(
          'Hãy cấu hình URL OTP API HTTPS hợp lệ trong Cài đặt.');
    }
  }
}
