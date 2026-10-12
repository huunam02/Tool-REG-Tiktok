import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_configuration.dart';
import 'app_session.dart';
import 'config.dart' as config;
import 'otp_api.dart';
import 'tiktok_page.dart';
import 'webview_proxy.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.userAgent});

  final String userAgent;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();
  final _loginFormKey = GlobalKey<FormState>();
  late final TabController _tabs;
  int _selectedTab = 0;
  late String _userAgent;
  bool _resettingSession = false;
  final _proxy = TextEditingController();
  final _proxyUsername = TextEditingController();
  final _proxyPassword = TextEditingController();
  late final TextEditingController _comments;
  late final TextEditingController _signupEmail;
  late final TextEditingController _signupPassword;
  late final TextEditingController _loginUsername;
  late final TextEditingController _loginPassword;
  final _signupMailboxPassword = TextEditingController();
  final _loginMailboxPassword = TextEditingController();
  bool _opening = false;
  bool get _busy => _opening || _resettingSession;
  TikTokLaunchAction _requestedAction = TikTokLaunchAction.browse;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);
    _userAgent = widget.userAgent;
    final defaults = AppConfiguration.defaults(_userAgent);
    _comments = TextEditingController(text: defaults.comments.join('\n'));
    _signupEmail = TextEditingController(text: defaults.signupEmail);
    _signupPassword = TextEditingController(text: defaults.signupPassword);
    _loginUsername = TextEditingController(text: defaults.loginUsername);
    _loginPassword = TextEditingController(text: defaults.loginPassword);
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    for (final controller in [
      _proxy,
      _proxyUsername,
      _proxyPassword,
      _comments,
      _signupEmail,
      _signupPassword,
      _loginUsername,
      _loginPassword,
      _signupMailboxPassword,
      _loginMailboxPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.index == _selectedTab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedTab = _tabs.index);
  }

  Future<void> _openTikTok(TikTokLaunchAction action) async {
    if (_busy) return;
    setState(() => _requestedAction = action);
    final forms = [
      (0, _formKey),
      if (action == TikTokLaunchAction.signup) (1, _signupFormKey),
      if (action == TikTokLaunchAction.login) (2, _loginFormKey),
    ];
    for (final (tab, form) in forms) {
      final invalidFields = form.currentState!.validateGranularly();
      if (invalidFields.isEmpty) continue;
      _tabs.index = tab;
      // The invalid setting may live in another tab. Lay it out before scrolling.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await Scrollable.ensureVisible(invalidFields.first.context,
          duration: const Duration(milliseconds: 250), alignment: 0.2);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _opening = true);
    try {
      final configuration = AppConfiguration(
        userAgent: _userAgent,
        proxy: WebViewProxy.parse(_proxy.text,
            username: _proxyUsername.text, password: _proxyPassword.text),
        comments: AppConfiguration.parseComments(_comments.text),
        signupEmail: _signupEmail.text.trim(),
        signupPassword: _signupPassword.text,
        loginUsername: _loginUsername.text.trim(),
        loginPassword: _loginPassword.text,
        signupMailboxPassword: _signupMailboxPassword.text,
        loginMailboxPassword: _loginMailboxPassword.text,
        otpApi: _otpApiFor(action),
        birthday: action == TikTokLaunchAction.signup
            ? AppConfiguration.randomSignupBirthday()
            : null,
      );
      await configureWebViewProxy(configuration.proxy);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            TikTokPage(configuration: configuration, launchAction: action),
      ));
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message),
      ));
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.code == 'proxy_unsupported'
            ? error.message ?? 'Thiết bị không hỗ trợ proxy.'
            : 'Không thể áp dụng proxy. Hãy kiểm tra cấu hình rồi thử lại.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không thể mở TikTok. Hãy thử lại.'),
      ));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _resetSession() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _resettingSession = true);
    try {
      final userAgent = await prepareAppSession();
      if (!mounted) return;
      setState(() => _userAgent = userAgent);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã xóa phiên và đổi User-Agent.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không thể xóa phiên. Hãy thử lại.'),
      ));
    } finally {
      if (mounted) setState(() => _resettingSession = false);
    }
  }

  OtpApiConfiguration? _otpApiFor(TikTokLaunchAction action) {
    if (action == TikTokLaunchAction.browse) return null;
    if (config.otpApiToken.trim().isEmpty) {
      throw const FormatException('Điền otpApiToken trong lib/config.dart.');
    }
    final Uri url;
    try {
      url = OtpApiConfiguration.parseUrl(config.otpApiUrl);
    } on FormatException {
      throw const FormatException(
          'Cấu hình otpApiUrl HTTPS hợp lệ trong lib/config.dart.');
    }
    return OtpApiConfiguration(
      url: url,
      readerToken: config.otpApiToken.trim(),
    );
  }

  InputDecoration _decoration(String label,
          {String? hint, String? helper, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      );

  Widget _section(String title, String description, IconData icon,
          List<Widget> fields) =>
      Material(
        color: _HomeStyle.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _HomeStyle.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _HomeStyle.cyan.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 22, color: _HomeStyle.cyan),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(description,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: _HomeStyle.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ...fields,
            ],
          ),
        ),
      );

  Widget _hero() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17363F), Color(0xFF172131), Color(0xFF2C1D32)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF29424C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('KHÔNG GIAN LÀM VIỆC',
                style: TextStyle(
                    color: _HomeStyle.cyan,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('Cấu hình TikTok',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8)),
            const SizedBox(height: 8),
            const Text('Thiết lập một lần. Bắt đầu theo cách của bạn.',
                style: TextStyle(color: Color(0xFFB8C8D2), height: 1.5)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _proxy,
                  builder: (context, value, _) {
                    String label;
                    try {
                      label = WebViewProxy.parse(value.text) == null
                          ? 'Kết nối trực tiếp'
                          : 'Đã cấu hình proxy';
                    } on FormatException {
                      label = 'Proxy chưa hợp lệ';
                    }
                    return _StatusChip(icon: Icons.public, label: label);
                  },
                ),
              ],
            ),
          ],
        ),
      );

  Widget _pair(Widget first, Widget second, bool wide) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 18),
            Expanded(child: second),
          ],
        )
      : Column(children: [first, const SizedBox(height: 16), second]);

  @override
  Widget build(BuildContext context) => Theme(
        data: _HomeStyle.theme(context),
        child: Scaffold(
          backgroundColor: _HomeStyle.background,
          appBar: AppBar(
            backgroundColor: _HomeStyle.background,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            toolbarHeight: 72,
            titleSpacing: 20,
            title: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _HomeStyle.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _HomeStyle.border),
                ),
                child: const Icon(Icons.music_note_rounded,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: _HomeStyle.cyan, offset: Offset(-2, -1)),
                      Shadow(color: _HomeStyle.pink, offset: Offset(2, 1))
                    ]),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Tool TikTok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ]),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: AbsorbPointer(
                absorbing: _busy,
                child: TabBar(
                  key: const Key('homeTabs'),
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: _HomeStyle.cyan,
                  unselectedLabelColor: _HomeStyle.muted,
                  indicatorColor: _HomeStyle.cyan,
                  dividerColor: _HomeStyle.border,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(key: Key('generalTab'), text: 'Thiết lập chung'),
                    Tab(key: Key('signupTab'), text: 'Đăng ký'),
                    Tab(key: Key('loginTab'), text: 'Đăng nhập'),
                  ],
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: AbsorbPointer(
              absorbing: _busy,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  return IndexedStack(
                    index: _selectedTab,
                    children: [
                      _tabPage(_formKey, 'general', wide, [
                        _hero(),
                        const SizedBox(height: 26),
                        _pair(_proxySection(), _commentsSection(), wide),
                        const SizedBox(height: 18),
                        _userAgentSection(),
                      ]),
                      _tabPage(_signupFormKey, 'signup', wide, [
                        _signupSection(),
                        const SizedBox(height: 20),
                        _otpApiSection(signup: true),
                      ]),
                      _tabPage(_loginFormKey, 'login', wide, [
                        _loginSection(),
                        const SizedBox(height: 20),
                        _otpApiSection(signup: false),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar: _actionBar(context),
        ),
      );

  Widget _tabPage(GlobalKey<FormState> formKey, String name, bool wide,
          List<Widget> sections) =>
      Form(
        key: formKey,
        child: SingleChildScrollView(
          key: PageStorageKey('home-$name'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sections),
            ),
          ),
        ),
      );

  Widget _actionBar(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: _HomeStyle.background,
          border: Border(top: BorderSide(color: _HomeStyle.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: SizedBox(
                    width: double.infinity,
                    child: switch (_selectedTab) {
                      2 => FilledButton.icon(
                          key: const Key('runAutoLogin'),
                          onPressed: _busy
                              ? null
                              : () => _openTikTok(TikTokLaunchAction.login),
                          style: FilledButton.styleFrom(
                              backgroundColor: _HomeStyle.cyan,
                              foregroundColor: _HomeStyle.background),
                          icon: _launchIcon(
                              TikTokLaunchAction.login, Icons.login_rounded),
                          label: const Text('Chạy đăng nhập tự động',
                              textAlign: TextAlign.center),
                        ),
                      1 => FilledButton.icon(
                          key: const Key('runAutoSignup'),
                          onPressed: _busy
                              ? null
                              : () => _openTikTok(TikTokLaunchAction.signup),
                          style: FilledButton.styleFrom(
                              backgroundColor: _HomeStyle.pink,
                              foregroundColor: _HomeStyle.background),
                          icon: _launchIcon(TikTokLaunchAction.signup,
                              Icons.person_add_alt_1),
                          label: const Text('Chạy đăng ký tự động',
                              textAlign: TextAlign.center),
                        ),
                      _ => OutlinedButton.icon(
                          key: const Key('openTikTok'),
                          onPressed: _busy
                              ? null
                              : () => _openTikTok(TikTokLaunchAction.browse),
                          icon: _launchIcon(TikTokLaunchAction.browse,
                              Icons.open_in_new_rounded),
                          label: const Text('Mở TikTok',
                              textAlign: TextAlign.center),
                        ),
                    }),
              ),
            ),
          ),
        ),
      );

  Widget _otpApiSection({required bool signup}) {
    return _section(
        'API lấy OTP',
        'Tự lấy mã từ hộp thư sau khi TikTok yêu cầu OTP. Chờ tối đa 180 giây.',
        Icons.mark_email_read_outlined, [
      _mailboxPasswordField(signup: signup),
    ]);
  }

  Widget _proxySection() =>
      _section('Proxy', 'Kết nối mạng cho phiên TikTok.', Icons.public, [
        TextFormField(
          key: const Key('proxyUrl'),
          controller: _proxy,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: _decoration('Proxy HTTP/HTTPS',
              icon: Icons.link,
              hint: 'http://host:port',
              helper: 'Để trống để không dùng proxy.'),
          validator: (value) {
            try {
              WebViewProxy.parse(value ?? '');
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('proxyUsername'),
          controller: _proxyUsername,
          autocorrect: false,
          decoration: _decoration('Tên đăng nhập proxy',
              icon: Icons.person_outline,
              helper: 'Tuỳ chọn, nếu proxy yêu cầu xác thực.'),
        ),
        const SizedBox(height: 16),
        _PasswordField(
          fieldKey: const Key('proxyPassword'),
          controller: _proxyPassword,
          label: 'Mật khẩu proxy (tuỳ chọn)',
        ),
      ]);

  Widget _commentsSection() => _section('Bình luận',
          'Chuẩn bị nội dung tương tác của bạn.', Icons.chat_bubble_outline, [
        TextFormField(
          key: const Key('comments'),
          controller: _comments,
          minLines: 4,
          maxLines: 6,
          decoration: _decoration('Nội dung bình luận',
              helper: 'Mỗi dòng là một bình luận.'),
        ),
      ]);

  Widget _signupSection() => _section('Đăng ký tài khoản',
          'Thông tin dùng để tạo tài khoản mới.', Icons.person_add_alt_1, [
        TextFormField(
          key: const Key('signupEmail'),
          controller: _signupEmail,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration('Email đăng ký', icon: Icons.alternate_email),
          validator: (value) {
            if (_requestedAction != TikTokLaunchAction.signup) {
              return null;
            }
            return RegExp(r'^[^\s@|]+@[^\s@|]+\.[^\s@|]+$')
                    .hasMatch(value?.trim() ?? '')
                ? null
                : 'Nhập email đăng ký hợp lệ.';
          },
        ),
        const SizedBox(height: 16),
        _PasswordField(
          fieldKey: const Key('signupPassword'),
          controller: _signupPassword,
          label: 'Mật khẩu đăng ký',
          validator: (value) => _requestedAction == TikTokLaunchAction.signup &&
                  (value == null || value.isEmpty)
              ? 'Nhập mật khẩu đăng ký.'
              : null,
        ),
      ]);

  Widget _loginSection() =>
      _section('Đăng nhập', 'Sử dụng tài khoản TikTok hiện có.', Icons.login, [
        TextFormField(
          key: const Key('loginUsername'),
          controller: _loginUsername,
          autocorrect: false,
          decoration: _decoration('Email / username đăng nhập',
              icon: Icons.person_outline),
          validator: (value) {
            if (_requestedAction != TikTokLaunchAction.login) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Nhập tài khoản đăng nhập.';
            }
            if (!OtpApiConfiguration.isEmail(value)) {
              return 'Dùng email đăng nhập khi lấy OTP qua API.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _PasswordField(
          fieldKey: const Key('loginPassword'),
          controller: _loginPassword,
          label: 'Mật khẩu đăng nhập',
          validator: (value) => _requestedAction == TikTokLaunchAction.login &&
                  (value == null || value.isEmpty)
              ? 'Nhập mật khẩu đăng nhập.'
              : null,
        ),
      ]);

  Widget _mailboxPasswordField({required bool signup}) => _PasswordField(
        fieldKey:
            Key(signup ? 'signupMailboxPassword' : 'loginMailboxPassword'),
        controller: signup ? _signupMailboxPassword : _loginMailboxPassword,
        label: 'Mật khẩu hộp thư lấy OTP',
        validator: (value) {
          final action =
              signup ? TikTokLaunchAction.signup : TikTokLaunchAction.login;
          if (_requestedAction == action && (value == null || value.isEmpty)) {
            return 'Nhập mật khẩu hộp thư của email ${signup ? 'đăng ký' : 'đăng nhập'}.';
          }
          return null;
        },
      );

  Widget _userAgentSection() => _section('User-Agent',
          'Thông tin trình duyệt của phiên hiện tại.', Icons.computer, [
        SelectableText(
          _userAgent,
          key: const Key('userAgent'),
          style: const TextStyle(
              fontSize: 12, height: 1.7, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('resetSession'),
          onPressed: _busy ? null : _resetSession,
          icon: _resettingSession
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restart_alt),
          label: Text(
              _resettingSession
                  ? 'Đang xóa phiên…'
                  : 'Xóa phiên và đổi User-Agent',
              textAlign: TextAlign.center),
        ),
      ]);

  Widget _launchIcon(TikTokLaunchAction action, IconData icon) =>
      _opening && _requestedAction == action
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: action == TikTokLaunchAction.browse
                    ? _HomeStyle.cyan
                    : _HomeStyle.background,
              ))
          : Icon(icon);
}

class _PasswordField extends StatefulWidget {
  const _PasswordField(
      {required this.fieldKey,
      required this.controller,
      required this.label,
      this.validator});

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        validator: widget.validator,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(_hidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          ),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: _HomeStyle.cyan),
          const SizedBox(width: 7),
          Flexible(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFD4E2E8)))),
        ]),
      );
}

abstract final class _HomeStyle {
  static const background = Color(0xFF0B101B);
  static const surface = Color(0xFF141C2A);
  static const input = Color(0xFF0F1623);
  static const border = Color(0xFF283346);
  static const muted = Color(0xFFA0AEC0);
  static const cyan = Color(0xFF47E4DE);
  static const pink = Color(0xFFFF7293);

  static ThemeData theme(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
      surface: surface,
    );
    final base = Theme.of(context);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final text = base.textTheme.labelLarge?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(
          bodyColor: const Color(0xFFF0F4FA),
          displayColor: const Color(0xFFF0F4FA)),
      iconTheme: const IconThemeData(color: muted),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        labelStyle: const TextStyle(color: muted, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF718096), fontSize: 14),
        helperStyle: const TextStyle(color: muted, fontSize: 12, height: 1.5),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: cyan, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: shape,
        textStyle: text,
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFDBE4F0),
        side: const BorderSide(color: border),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: shape,
        textStyle: text,
      )),
    );
  }
}
