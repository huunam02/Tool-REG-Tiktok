import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const String tiktokHomeUrl = 'https://www.tiktok.com/';
const String tiktokProfileUrl = 'https://www.tiktok.com/profile';

enum _AuthAutomationStep { idle, login, signUp, phoneOrEmail, dateOfBirth }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // // -- Bỏ comment đoạn này nếu bạn muốn set Proxy cho toàn bộ Webview --
  // if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
  //   await ProxyController.instance().setProxyOverride(
  //     settings: ProxySettings(
  //       proxyRules: [ProxyRule(url: "http://192.168.1.1:8888")], // Đổi lại IP của bạn
  //       bypassRules: ["www.google.com"]
  //     )
  //   );
  // }

  runApp(const TikTokApp());
}

class TikTokApp extends StatelessWidget {
  const TikTokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFE2C55),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const TikTokWebViewPage(),
    );
  }
}

class TikTokWebViewPage extends StatefulWidget {
  const TikTokWebViewPage({super.key});

  @override
  State<TikTokWebViewPage> createState() => _TikTokWebViewPageState();
}

class _TikTokWebViewPageState extends State<TikTokWebViewPage> {
  static const Duration _automationDelay = Duration(seconds: 1);

  InAppWebViewController? _webViewController;

  int _loadingProgress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  _AuthAutomationStep _authAutomationStep = _AuthAutomationStep.idle;
  String? _pageError;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openProfileAndLogin() async {
    _authAutomationStep = _AuthAutomationStep.login;
    await _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(tiktokProfileUrl)),
    );
  }

  void _handleAuthAutomationMessage(String message) {
    if (message == 'login-clicked' &&
        _authAutomationStep == _AuthAutomationStep.login) {
      _authAutomationStep = _AuthAutomationStep.signUp;
      _clickAuthButtonWhenReady();
      return;
    }

    if (message == 'signup-clicked' &&
        _authAutomationStep == _AuthAutomationStep.signUp) {
      _authAutomationStep = _AuthAutomationStep.phoneOrEmail;
      _clickAuthButtonWhenReady();
      return;
    }

    if (message == 'phone-or-email-clicked' &&
        _authAutomationStep == _AuthAutomationStep.phoneOrEmail) {
      _authAutomationStep = _AuthAutomationStep.dateOfBirth;
      _clickAuthButtonWhenReady();
      return;
    }

    if (message == 'date-of-birth-clicked' &&
        _authAutomationStep == _AuthAutomationStep.dateOfBirth) {
      _authAutomationStep = _AuthAutomationStep.idle;
      return;
    }

    _authAutomationStep = _AuthAutomationStep.idle;
  }

  Future<void> _clickAuthButtonWhenReady() async {
    if (_authAutomationStep == _AuthAutomationStep.idle) return;

    final scheduledStep = _authAutomationStep;
    await Future<void>.delayed(_automationDelay);

    if (_authAutomationStep != scheduledStep) return;

    late final String selectors;
    late final String textPattern;
    late final String successMessage;
    late final String timeoutMessage;
    String? customScript;

    switch (scheduledStep) {
      case _AuthAutomationStep.login:
        selectors = '''
              '[data-e2e="top-login-button"]',
              '[data-e2e="login-button"]',
              'button[data-e2e*="login"]',
              'a[data-e2e*="login"]'
            ''';
        textPattern = r'^(log in|login|đăng nhập)$';
        successMessage = 'login-clicked';
        timeoutMessage = 'login-timeout';
        break;
      case _AuthAutomationStep.signUp:
        selectors = '''
              '[data-e2e="signup-button"]',
              '[data-e2e="login-modal-signup"]',
              'button[data-e2e*="signup"]',
              'a[data-e2e*="signup"]',
              'a[href*="/signup"]'
            ''';
        textPattern = r'^(sign up|signup|register|đăng ký)$';
        successMessage = 'signup-clicked';
        timeoutMessage = 'signup-timeout';
        break;
      case _AuthAutomationStep.phoneOrEmail:
        selectors = '''
              '[data-e2e="phone-or-email"]',
              '[data-e2e="login-phone-or-email"]',
              '[data-e2e*="phone-email"]',
              '[data-e2e*="phone-or-email"]'
            ''';
        textPattern =
            r'^(use phone or email|phone or email|sử dụng số điện thoại hoặc email)$';
        successMessage = 'phone-or-email-clicked';
        timeoutMessage = 'phone-or-email-timeout';
        break;
      case _AuthAutomationStep.dateOfBirth:
        selectors = '''
              '[data-e2e="next-button"]',
              'button[type="submit"]',
              'button[data-e2e*="next"]'
            ''';
        textPattern = r'^(next|tiếp|tiếp tục)$';
        successMessage = 'date-of-birth-clicked';
        timeoutMessage = 'date-of-birth-timeout';
        customScript = r'''
            let isScrollingWheel = false;
            const selects = document.querySelectorAll('select');
            if (selects.length >= 3) {
              const trigger = (el) => {
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new Event('input', { bubbles: true }));
              };
              const getRandomInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

              if (selects[0].selectedIndex <= 0) { 
                const maxMonth = Math.max(1, Math.min(12, selects[0].options.length - 1));
                selects[0].selectedIndex = getRandomInt(1, maxMonth); 
                trigger(selects[0]); 
              }
              
              if (selects[1].selectedIndex <= 0) { 
                const maxDay = Math.max(1, Math.min(28, selects[1].options.length - 1));
                selects[1].selectedIndex = getRandomInt(1, maxDay); 
                trigger(selects[1]); 
              }
              
              if (selects[2].selectedIndex <= 0) {
                const validYearIndices = [];
                for (let i = 0; i < selects[2].options.length; i++) {
                  const yearStr = selects[2].options[i].text || selects[2].options[i].value;
                  const year = parseInt(yearStr, 10);
                  if (!isNaN(year) && year <= 2010 && year >= 1970) {
                    validYearIndices.push(i);
                  }
                }
                
                if (validYearIndices.length > 0) {
                  const randomIdx = validYearIndices[getRandomInt(0, validYearIndices.length - 1)];
                  selects[2].selectedIndex = randomIdx;
                  trigger(selects[2]);
                } else if (selects[2].options.length > 20) {
                   selects[2].selectedIndex = 25; // fallback
                   trigger(selects[2]);
                }
              }
            } else {
              window._wheelScrolls = window._wheelScrolls || { year: 0, month: 0, day: 0 };
              
              const swipeWheel = (regex, deltaY) => {
                const els = Array.from(document.querySelectorAll('*')).filter(el => el.children.length === 0 && regex.test(el.textContent.trim()));
                if (els.length > 0) {
                  const el = els[Math.floor(els.length / 2)];
                  const rect = el.getBoundingClientRect();
                  const x = rect.left + rect.width / 2;
                  const y = rect.top + rect.height / 2;
                  
                  try {
                    let e1 = new Event('touchstart', { bubbles: true }); e1.touches = [{clientX: x, clientY: y}]; el.dispatchEvent(e1);
                    let e2 = new Event('touchmove', { bubbles: true }); e2.touches = [{clientX: x, clientY: y + deltaY}]; el.dispatchEvent(e2);
                    let e3 = new Event('touchend', { bubbles: true }); e3.changedTouches = [{clientX: x, clientY: y + deltaY}]; el.dispatchEvent(e3);
                  } catch (e) {}
                  
                  el.dispatchEvent(new WheelEvent('wheel', { bubbles: true, deltaY: -deltaY }));
                }
              };

              let currentYear = 9999;
              const display = Array.from(document.querySelectorAll('div, span, p, input')).find(el => {
                const text = el.value || el.textContent;
                return /^\d{4}[-/]\d{2}[-/]\d{2}$/.test(text.trim());
              });
              
              if (display) {
                const text = display.value || display.textContent;
                currentYear = parseInt(text.trim().split(/[-/]/)[0], 10);
              }

              if (currentYear > 2010 || window._wheelScrolls.year < 8) {
                 swipeWheel(/^(19|20)\d{2}$/, 100);
                 window._wheelScrolls.year++;
                 isScrollingWheel = true;
              }
              
              if (window._wheelScrolls.month < 3) {
                 swipeWheel(/^(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Tháng \d{1,2})$/i, Math.random() > 0.5 ? 80 : -80);
                 window._wheelScrolls.month++;
                 isScrollingWheel = true;
              }
              
              if (window._wheelScrolls.day < 2) {
                 swipeWheel(/^([1-9]|[12]\d|3[01])$/, Math.random() > 0.5 ? 80 : -80);
                 window._wheelScrolls.day++;
                 isScrollingWheel = true;
              }
              
              window.__isScrollingWheel = isScrollingWheel;
            }
        ''';
        break;
      case _AuthAutomationStep.idle:
        return;
    }

    try {
      await _webViewController?.evaluateJavascript(
        source: '''
        (() => {
          if (window.__flutterAuthAutomationRunning) return;
          window.__flutterAuthAutomationRunning = true;

          const notifyFlutter = (result) => {
            window.__flutterAuthAutomationRunning = false;
            window.flutter_inappwebview.callHandler('FlutterLogin', result);
          };

          const isVisible = (element) => {
            if (!element) return false;
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              rect.width > 0 && rect.height > 0;
          };

          const findButton = () => {
            const selectors = [
              $selectors
            ];

            for (const selector of selectors) {
              const element = document.querySelector(selector);
              if (isVisible(element)) return element;
            }

            const elements = document.querySelectorAll(
              'button, a, [role="button"], [data-e2e="channel-item"]'
            );
            return Array.from(elements).find((element) => {
              const text = (element.innerText || element.textContent || '')
                .trim()
                .replace(/\\s+/g, ' ');
              return isVisible(element) &&
                /$textPattern/i.test(text);
            });
          };

          let attempts = 0;
          const doAction = () => {
            ${customScript ?? ''}
            if (window.__isScrollingWheel) return;

            const target = findButton();
            if (target) {
              const isDisabled = target.disabled || 
                                 target.hasAttribute('disabled') || 
                                 target.getAttribute('aria-disabled') === 'true';
              if (!isDisabled) {
                clearInterval(timer);
                notifyFlutter('$successMessage');
                target.click();
                return;
              }
            }

            attempts += 1;
            if (attempts >= 30) {
              clearInterval(timer);
              notifyFlutter('$timeoutMessage');
            }
          };

          const timer = setInterval(doAction, 500);
          doAction();
        })();
      ''',
      );
    } catch (_) {
      // A redirect can replace the page while JavaScript is being injected.
      // The next onPageFinished callback will try again on the final page.
    }
  }

  Future<void> _updateNavigationState() async {
    final canGoBack = await _webViewController?.canGoBack() ?? false;
    final canGoForward = await _webViewController?.canGoForward() ?? false;

    if (!mounted) return;
    setState(() {
      _loadingProgress = 100;
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _handleSystemBack() async {
    if (await _webViewController?.canGoBack() ?? false) {
      await _webViewController?.goBack();
      await _updateNavigationState();
      return;
    }

    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleSystemBack();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          titleSpacing: 16,
          title: const Text(
            'Tool REG TikTok',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
          ),
          actions: [
            IconButton(
              tooltip: 'Trang chủ TikTok',
              onPressed: () => _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(tiktokHomeUrl)),
              ),
              icon: const Icon(Icons.home_outlined, color: Colors.black),
            ),
            IconButton(
              tooltip: 'Tải lại',
              onPressed: () => _webViewController?.reload(),
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
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(tiktokHomeUrl)),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'FlutterLogin',
                    callback: (args) {
                      _handleAuthAutomationMessage(args[0].toString());
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  if (!mounted) return;
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
                  await _updateNavigationState();
                  await _clickAuthButtonWhenReady();
                },
                onReceivedError: (controller, request, error) {
                  if (error.description.contains('net::ERR_ABORTED')) return;
                  if (!mounted) return;
                  setState(() => _pageError = error.description);
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final url = navigationAction.request.url.toString();
                  if (!url.startsWith('http://') &&
                      !url.startsWith('https://')) {
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
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Hồ sơ TikTok',
          backgroundColor: const Color(0xFFFE2C55),
          foregroundColor: Colors.white,
          onPressed: _openProfileAndLogin,
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: ColoredBox(
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Quay lại',
                  onPressed: _canGoBack
                      ? () async {
                          await _webViewController?.goBack();
                          await _updateNavigationState();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_ios_new),
                ),
                IconButton(
                  tooltip: 'Đi tới',
                  onPressed: _canGoForward
                      ? () async {
                          await _webViewController?.goForward();
                          await _updateNavigationState();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_ios),
                ),
              ],
            ),
          ),
        ),
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
