import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../controller/tiktok_controller.dart';
import '../core/scripts/auto_cookie_script.dart';
import '../core/scripts/auto_interest_script.dart';
import '../core/scripts/auto_watch_script.dart';
import '../core/app_configuration.dart';
import '../core/app_action_theme.dart';
import '../core/otp_api.dart';
import '../core/tiktok_launch_action.dart';
import '../core/webview_failure.dart';
import '../core/webview_user_agent.dart';
import 'widgets/controller_scope.dart';

export '../core/tiktok_launch_action.dart';

class TikTokPage extends StatelessWidget {
  const TikTokPage(
      {super.key,
      required this.configuration,
      this.launchAction = TikTokLaunchAction.browse,
      this.otpReaderFactory});

  final AppConfiguration configuration;
  final TikTokLaunchAction launchAction;
  final OtpCodeReader Function(OtpApiConfiguration)? otpReaderFactory;
  String get initialUrl => launchAction.initialUrl;

  @override
  Widget build(BuildContext context) => ControllerScope<TikTokController>(
        controller: TikTokController(
            configuration: configuration,
            launchAction: launchAction,
            otpReaderFactory: otpReaderFactory),
        builder: (logic) => _TikTokView(logic),
      );
}

class _TikTokView extends StatelessWidget {
  const _TikTokView(this.logic);
  final TikTokController logic;

  Widget _accountFailureBanner(BuildContext context) => Container(
        key: const Key('accountFailureBanner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF342027),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(logic.accountFailure!.title,
                style: const TextStyle(
                    color: Color(0xFFFFADB7), fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(logic.accountFailure!.message,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('returnAccountConfiguration'),
              onPressed: () {
                logic.cancelAutoActions();
                Navigator.of(context).maybePop();
              },
              child: const Text('Quay về cấu hình'),
            ),
          ],
        ),
      );

  Widget _proxyWarningBanner() => Container(
        key: const Key('proxyWarningBanner'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            color: Color(0xFF20251C),
            border: Border(bottom: BorderSide(color: Color(0xFF655936)))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(logic.proxyWarning!.title,
                style: const TextStyle(
                    color: Color(0xFFFFCD78),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(logic.proxyWarning!.message,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('retryProxyWarning'),
                onPressed: logic.checkingIp ? null : logic.retryProxyWarning,
                child: Text(logic.checkingIp ? 'Đang kiểm tra…' : 'Thử lại'),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: AppActionTheme.apply(Theme.of(context)),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black),
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TikTok',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black),
                ),
                if (logic.detectedIp != null)
                  Text(
                    'IP: ${logic.detectedIp}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Trang chủ TikTok',
                onPressed: logic.goHome,
                icon: const Icon(Icons.home_outlined, color: Colors.black),
              ),
              IconButton(
                tooltip: 'Tải lại',
                onPressed: logic.reloadPage,
                icon: const Icon(Icons.refresh, color: Colors.black),
              ),
            ],
            bottom: logic.loadingProgress < 100
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(2),
                    child: LinearProgressIndicator(
                      value: logic.loadingProgress / 100,
                      minHeight: 2,
                      backgroundColor: Colors.white12,
                      color: AppActionTheme.primary,
                    ),
                  )
                : null,
          ),
          bottomNavigationBar: logic.autoLoginBusy || logic.autoSignupBusy
              ? SafeArea(
                  child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Expanded(
                        child: Text((logic.autoLoginBusy &&
                                    logic.loginOtpRequest != null &&
                                    logic.activeLoginOtp.isEmpty) ||
                                (logic.autoSignupBusy &&
                                    logic.signupOtpRequest != null &&
                                    logic.activeSignupOtp.isEmpty)
                            ? 'Đang chờ API lấy OTP… (tối đa ${logic.configuration.otpApi?.waitSeconds ?? 180} giây)'
                            : logic.autoLoginBusy
                                ? 'Đang đăng nhập tự động…'
                                : logic.signupStatus)),
                    OutlinedButton(
                        onPressed: logic.cancelAutoActions,
                        child: const Text('Dừng')),
                  ]),
                ))
              : null,
          body: Column(children: [
            if (logic.accountFailure != null) _accountFailureBanner(context),
            if (logic.proxyWarning != null && logic.pageFailure == null)
              _proxyWarningBanner(),
            Expanded(
                child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: needsAndroidDesktopIdentity
                      ? null
                      : URLRequest(
                          url: WebUri(logic.initialUrl),
                        ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: inlineVideoScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                    UserScript(
                      source: autoAcceptCookieScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                      forMainFrameOnly: true,
                    ),
                    UserScript(
                      source: autoSelectInterestScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                      forMainFrameOnly: true,
                    ),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    userAgent: logic.configuration.userAgent,
                    preferredContentMode: UserPreferredContentMode.DESKTOP,
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    incognito: false,
                    cacheEnabled: true,
                  ),
                  onWebViewCreated: logic.onWebViewCreated,
                  onReceivedHttpAuthRequest: logic.onReceivedHttpAuthRequest,
                  onLoadStart: logic.onLoadStart,
                  onProgressChanged: logic.onProgressChanged,
                  onLoadStop: logic.onLoadStop,
                  onReceivedError: logic.onReceivedError,
                  onReceivedHttpError: logic.onReceivedHttpError,
                  onConsoleMessage: logic.onConsoleMessage,
                  shouldOverrideUrlLoading: logic.shouldOverrideUrlLoading,
                ),
                if (logic.pageFailure != null)
                  _ErrorView(
                    failure: logic.pageFailure!,
                    onRetry: logic.retryPage,
                  ),
              ],
            )),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('autoWatch'),
            heroTag: 'autoWatch',
            tooltip: logic.autoWatchEnabled
                ? 'Dừng tự động xem video và bình luận'
                : 'Bật tự động xem video và bình luận',
            backgroundColor: AppActionTheme.primary,
            foregroundColor: AppActionTheme.onPrimary,
            onPressed: logic.webViewController == null ||
                    logic.autoWatchBusy ||
                    logic.autoLoginBusy ||
                    logic.autoSignupBusy ||
                    logic.loadingProgress < 100 ||
                    logic.pageFailure != null ||
                    (!logic.initialActionStarted &&
                        logic.launchAction != TikTokLaunchAction.browse)
                ? null
                : logic.toggleAutoWatch,
            label: Text(logic.autoWatchEnabled
                ? 'Dừng tự động'
                : 'Bật auto xem và bình luận'),
          ),
        ));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});

  final WebViewFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('webViewFailure'),
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                failure.title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              if (failure.code != null) ...[
                const SizedBox(height: 10),
                Text(failure.code!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('retryWebViewFailure'),
                onPressed: onRetry,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        )),
      ),
    );
  }
}
