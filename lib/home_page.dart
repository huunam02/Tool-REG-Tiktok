import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_configuration.dart';
import 'tiktok_page.dart';
import 'webview_proxy.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.userAgent});

  final String userAgent;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _proxy = TextEditingController();
  final _proxyUsername = TextEditingController();
  final _proxyPassword = TextEditingController();
  late final TextEditingController _comments;
  late final TextEditingController _signupEmail;
  late final TextEditingController _signupPassword;
  final _signupOtp = TextEditingController();
  late final TextEditingController _loginUsername;
  late final TextEditingController _loginPassword;
  final _loginOtp = TextEditingController();
  DateTime? _birthday;
  bool _opening = false;
  TikTokLaunchAction _requestedAction = TikTokLaunchAction.browse;

  @override
  void initState() {
    super.initState();
    final defaults = AppConfiguration.defaults(widget.userAgent);
    _comments = TextEditingController(text: defaults.comments.join('\n'));
    _signupEmail = TextEditingController(text: defaults.signupEmail);
    _signupPassword = TextEditingController(text: defaults.signupPassword);
    _loginUsername = TextEditingController(text: defaults.loginUsername);
    _loginPassword = TextEditingController(text: defaults.loginPassword);
    _birthday = defaults.birthday;
  }

  @override
  void dispose() {
    for (final controller in [
      _proxy,
      _proxyUsername,
      _proxyPassword,
      _comments,
      _signupEmail,
      _signupPassword,
      _signupOtp,
      _loginUsername,
      _loginPassword,
      _loginOtp,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final birthday = await showDatePicker(
      context: context,
      initialDate: _birthday,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      helpText: 'Chọn ngày sinh thật của bạn',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (context, child) => Theme(
        data: _HomeStyle.theme(context),
        child: child!,
      ),
    );
    if (mounted && birthday != null) setState(() => _birthday = birthday);
  }

  Future<void> _openTikTok(TikTokLaunchAction action) async {
    if (_opening) return;
    setState(() => _requestedAction = action);
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      await Scrollable.ensureVisible(invalidFields.first.context,
          duration: const Duration(milliseconds: 250), alignment: 0.2);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _opening = true);
    try {
      if (action == TikTokLaunchAction.signup && _birthday == null) {
        await _pickBirthday();
        if (!mounted || _birthday == null) return;
      }
      final configuration = AppConfiguration(
        userAgent: widget.userAgent,
        proxy: WebViewProxy.parse(_proxy.text,
            username: _proxyUsername.text, password: _proxyPassword.text),
        comments: AppConfiguration.parseComments(_comments.text),
        signupEmail: _signupEmail.text.trim(),
        signupPassword: _signupPassword.text,
        signupOtp: _signupOtp.text.trim(),
        loginUsername: _loginUsername.text.trim(),
        loginPassword: _loginPassword.text,
        loginOtp: _loginOtp.text.trim(),
        birthday: _birthday,
      );
      await configureWebViewProxy(configuration.proxy);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            TikTokPage(configuration: configuration, launchAction: action),
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
                const _StatusChip(
                    icon: Icons.desktop_windows_outlined,
                    label: 'Trình duyệt desktop'),
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
                child: Text('TikTok Studio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          body: SafeArea(
            bottom: false,
            child: Form(
              key: _formKey,
              child: AbsorbPointer(
                absorbing: _opening,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                          wide ? 28 : 16, 8, wide ? 28 : 16, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _hero(),
                              const SizedBox(height: 26),
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 12),
                                child: Text('THIẾT LẬP CHUNG',
                                    style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1.6,
                                        fontWeight: FontWeight.w700,
                                        color: _HomeStyle.muted)),
                              ),
                              _pair(_proxySection(), _commentsSection(), wide),
                              const SizedBox(height: 26),
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 12),
                                child: Text('TÀI KHOẢN',
                                    style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1.6,
                                        fontWeight: FontWeight.w700,
                                        color: _HomeStyle.muted)),
                              ),
                              _pair(_signupSection(), _loginSection(), wide),
                              const SizedBox(height: 18),
                              _userAgentSection(),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          bottomNavigationBar: _actionBar(context),
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
                child: LayoutBuilder(builder: (context, constraints) {
                  final buttons = [
                    FilledButton.icon(
                      key: const Key('runAutoLogin'),
                      onPressed: _opening
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
                    FilledButton.icon(
                      key: const Key('runAutoSignup'),
                      onPressed: _opening
                          ? null
                          : () => _openTikTok(TikTokLaunchAction.signup),
                      style: FilledButton.styleFrom(
                          backgroundColor: _HomeStyle.pink,
                          foregroundColor: _HomeStyle.background),
                      icon: _launchIcon(
                          TikTokLaunchAction.signup, Icons.person_add_alt_1),
                      label: const Text('Chạy đăng ký tự động',
                          textAlign: TextAlign.center),
                    ),
                    OutlinedButton.icon(
                      key: const Key('openTikTok'),
                      onPressed: _opening
                          ? null
                          : () => _openTikTok(TikTokLaunchAction.browse),
                      icon: _launchIcon(
                          TikTokLaunchAction.browse, Icons.open_in_new_rounded),
                      label:
                          const Text('Mở TikTok', textAlign: TextAlign.center),
                    ),
                  ];
                  // Stack actions for large text so every label stays readable.
                  if (constraints.maxWidth < 340 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buttons[0],
                        const SizedBox(height: 8),
                        buttons[1],
                        const SizedBox(height: 8),
                        buttons[2]
                      ],
                    );
                  }
                  if (constraints.maxWidth >= 700) {
                    return Row(children: [
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 12),
                      Expanded(child: buttons[1]),
                      const SizedBox(width: 12),
                      Expanded(child: buttons[2]),
                    ]);
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: buttons[0]),
                              const SizedBox(width: 10),
                              Expanded(child: buttons[1])
                            ]),
                      ),
                      const SizedBox(height: 8),
                      buttons[2],
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      );

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
            return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
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
        const SizedBox(height: 16),
        ListTile(
          key: const Key('signupBirthday'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          tileColor: _HomeStyle.input,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _HomeStyle.border),
          ),
          leading: const Icon(Icons.cake_outlined),
          title: const Text('Ngày sinh',
              style: TextStyle(fontSize: 13, color: _HomeStyle.muted)),
          subtitle: Text(_birthday == null
              ? 'Chọn ngày sinh'
              : AppConfiguration.formatBirthday(_birthday!)),
          onTap: _pickBirthday,
          trailing: _birthday == null
              ? const Icon(Icons.calendar_month_outlined)
              : IconButton(
                  tooltip: 'Xoá ngày sinh',
                  onPressed: () => setState(() => _birthday = null),
                  icon: const Icon(Icons.close),
                ),
        ),
        const SizedBox(height: 16),
        _otpField('signupOtp', _signupOtp, 'Mã OTP đăng ký'),
      ]);

  Widget _loginSection() =>
      _section('Đăng nhập', 'Sử dụng tài khoản TikTok hiện có.', Icons.login, [
        TextFormField(
          key: const Key('loginUsername'),
          controller: _loginUsername,
          autocorrect: false,
          decoration: _decoration('Email / username đăng nhập',
              icon: Icons.person_outline),
          validator: (value) => _requestedAction == TikTokLaunchAction.login &&
                  (value == null || value.trim().isEmpty)
              ? 'Nhập tài khoản đăng nhập.'
              : null,
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
        const SizedBox(height: 16),
        _otpField('loginOtp', _loginOtp, 'Mã OTP đăng nhập'),
      ]);

  Widget _userAgentSection() => _section('User Agent',
          'Thông tin trình duyệt của phiên hiện tại.', Icons.computer, [
        SelectableText(widget.userAgent,
            key: const Key('userAgent'),
            style: const TextStyle(
                fontSize: 12,
                height: 1.7,
                color: _HomeStyle.muted,
                fontFamily: 'monospace')),
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

  Widget _otpField(
          String key, TextEditingController controller, String label) =>
      TextFormField(
        key: Key(key),
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autocorrect: false,
        enableSuggestions: false,
        decoration: _decoration(label,
            icon: Icons.pin_outlined,
            helper: 'Tự nhập sau khoảng 5 giây khi yêu cầu mã. '
                'Để trống để nhập thủ công.'),
      );
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
