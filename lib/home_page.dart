import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'auto_login_script.dart';
import 'auto_watch_script.dart';
import 'config.dart';

const String tiktokHomeUrl = 'https://www.tiktok.com/';
const String tiktokProfileUrl = 'https://www.tiktok.com/profile';
const String tiktokLoginUrl =
    'https://www.tiktok.com/login/phone-or-email/email';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.userAgent});

  final String userAgent;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _commentInputChannel =
      MethodChannel('test_tiktok/comment_input');
  InAppWebViewController? _webViewController;
  final _autoFabKey = GlobalKey<ExpandableFabState>();
  bool _autoLoginBusy = false;
  int _autoLoginAttempt = 0;

  int _loadingProgress = 0;

  String? _pageError;
  bool _autoWatchEnabled = false;
  bool _autoWatchBusy = false;
  bool _appActive = true;
  String _commentDraft = defaultAutoComments.join('\n');
  List<String> _comments = List.of(defaultAutoComments);
  bool _pasteBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autoLoginAttempt++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopAutoWatch());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive && _autoLoginBusy) _cancelAutoLogin();
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
        source: buildAutoWatchScript(
          _comments,
          useClipboard: defaultTargetPlatform == TargetPlatform.iOS,
        ),
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
      return await _commentInputChannel.invokeMethod<bool>('paste') ?? false;
    } catch (_) {
      return false;
    } finally {
      _pasteBusy = false;
    }
  }

  Future<void> _toggleAutoWatch() async {
    if (_autoWatchBusy || _autoLoginBusy || _webViewController == null) return;
    _autoFabKey.currentState?.close();
    if (!_autoWatchEnabled && !await _configureComments()) return;
    if (!mounted) return;
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

  void _cancelAutoLogin() {
    _autoLoginAttempt++;
    if (mounted) setState(() => _autoLoginBusy = false);
  }

  Future<void> _autoLogin() async {
    _autoFabKey.currentState?.close();
    if (_autoLoginBusy) {
      _cancelAutoLogin();
      return;
    }
    final controller = _webViewController;
    if (controller == null || _autoWatchBusy || !_appActive) return;
    if (email.trim().isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Hãy nhập email và mật khẩu trong config.dart.')),
      );
      return;
    }
    final attempt = ++_autoLoginAttempt;
    setState(() {
      _autoLoginBusy = true;
      _autoWatchEnabled = false;
    });
    bool isActive() => mounted && _appActive && attempt == _autoLoginAttempt;
    var submitted = false;
    var message = 'Không thể mở trang đăng nhập. Hãy thử tải lại TikTok.';
    try {
      await _stopAutoWatch();
      if (!isActive()) return;
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(tiktokLoginUrl)),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      message =
          'Không tìm thấy biểu mẫu đăng nhập. Bạn có thể đăng nhập thủ công.';
      while (isActive() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!isActive()) return;
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
              email: email.trim(),
              password: password,
              allowSubmit: !submitted,
              attempt: attempt,
            ),
          );
        } catch (_) {
          continue;
        }
        if (!isActive()) return;
        if (result == 'submitted') {
          submitted = true;
          message = 'Đã gửi đăng nhập nhưng chưa xác nhận được kết quả. '
              'Hãy kiểm tra trên TikTok.';
        } else if (result == 'already-logged-in' || result == 'login-success') {
          message = result == 'already-logged-in'
              ? 'Tài khoản TikTok đã đăng nhập.'
              : 'Đăng nhập TikTok thành công.';
          break;
        } else if (result == 'verification-required') {
          message = 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. '
              'Hãy hoàn tất trên trang đăng nhập.';
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
      if (mounted && isActive()) {
        setState(() => _autoLoginBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<bool> _configureComments() async {
    final draft = await showDialog<String>(
      context: context,
      builder: (_) => _CommentConfigDialog(
        initialText: _commentDraft.isEmpty
            ? defaultAutoComments.join('\n')
            : _commentDraft,
      ),
    );
    if (draft == null || !mounted) return false;
    _commentDraft = draft;
    _comments = draft
        .split('\n')
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    return true;
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

  Future<void> _handlePageLoadComplete(WebUri? url) async {
    await _updateNavigationState();
    await _injectAutoCloseCountryModal();
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

  Future<void> _handleSystemBack() async {
    if (_autoFabKey.currentState?.isOpen ?? false) {
      _autoFabKey.currentState?.close();
      return;
    }
    if (_autoLoginBusy) _cancelAutoLogin();
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
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.white,
          titleSpacing: 16,
          title: const Text(
            'Tool TikTok',
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
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(tiktokHomeUrl)),
              initialUserScripts: UnmodifiableListView([
                UserScript(
                  source: inlineVideoScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              ]),
              initialSettings: InAppWebViewSettings(
                userAgent: widget.userAgent,
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
        floatingActionButtonLocation: ExpandableFab.location,
        floatingActionButton: ExpandableFab(
          key: _autoFabKey,
          type: ExpandableFabType.up,
          distance: 70,
          childrenAnimation: ExpandableFabAnimation.none,
          overlayStyle: const ExpandableFabOverlayStyle(color: Colors.black54),
          openButtonBuilder: RotateFloatingActionButtonBuilder(
            foregroundColor: Colors.black,
            backgroundColor: const Color(0xFF25F4EE),
            child: const Icon(Icons.auto_awesome),
          ),
          closeButtonBuilder: DefaultFloatingActionButtonBuilder(
            foregroundColor: Colors.black,
            backgroundColor: Colors.white,
            child: const Icon(Icons.close),
          ),
          children: [
            FloatingActionButton.extended(
              heroTag: 'autoWatch',
              tooltip: _autoWatchEnabled
                  ? 'Dừng tự động xem video'
                  : 'Tự xem, bình luận theo danh sách rồi chuyển khi xem hết',
              backgroundColor:
                  _autoWatchEnabled ? const Color(0xFF25F4EE) : Colors.white,
              foregroundColor: Colors.black,
              onPressed: _webViewController == null ||
                      _autoWatchBusy ||
                      _autoLoginBusy ||
                      _loadingProgress < 100
                  ? null
                  : _toggleAutoWatch,
              icon: Icon(
                _autoWatchEnabled ? Icons.stop : Icons.play_arrow,
              ),
              label: Text(
                  _autoWatchEnabled ? 'Dừng tự động' : 'Tự xem và bình luận'),
            ),
            FloatingActionButton.extended(
              heroTag: 'autoLogin',
              tooltip: 'Đăng nhập bằng tài khoản trong config.dart',
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              onPressed: _webViewController == null || _autoWatchBusy
                  ? null
                  : _autoLogin,
              icon: Icon(_autoLoginBusy ? Icons.stop : Icons.login),
              label:
                  Text(_autoLoginBusy ? 'Dừng đăng nhập' : 'Tự động đăng nhập'),
            ),
          ],
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

class _CommentConfigDialog extends StatefulWidget {
  const _CommentConfigDialog({required this.initialText});

  final String initialText;

  @override
  State<_CommentConfigDialog> createState() => _CommentConfigDialogState();
}

class _CommentConfigDialogState extends State<_CommentConfigDialog> {
  late final TextEditingController _input;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tự động bình luận'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mỗi dòng là một bình luận. Ứng dụng chọn ngẫu nhiên một câu '
              'cho mỗi video, tránh lặp câu liên tiếp. Bạn có thể sửa danh sách bên dưới.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Danh sách bình luận',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () {
            if (!_input.text
                .split('\n')
                .any((text) => text.trim().isNotEmpty)) {
              setState(() => _error = 'Nhập ít nhất một bình luận.');
              return;
            }
            Navigator.pop(context, _input.text);
          },
          child: const Text('Bắt đầu'),
        ),
      ],
    );
  }
}
