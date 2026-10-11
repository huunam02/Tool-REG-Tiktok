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

  InputDecoration _decoration(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      );

  Widget _section(String title, IconData icon, List<Widget> fields) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, size: 22, color: const Color(0xFF25F4EE)),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 20),
              ...fields,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình TikTok')),
      body: SafeArea(
        bottom: false,
        child: Form(
          key: _formKey,
          child: AbsorbPointer(
            absorbing: _opening,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('Thiết lập thông tin bên dưới rồi mở TikTok.',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  _section('Proxy', Icons.public, [
                    TextFormField(
                      key: const Key('proxyUrl'),
                      controller: _proxy,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: _decoration('Proxy HTTP/HTTPS',
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
                      decoration: _decoration('Tên đăng nhập proxy (tuỳ chọn)'),
                    ),
                    const SizedBox(height: 16),
                    _PasswordField(
                      fieldKey: const Key('proxyPassword'),
                      controller: _proxyPassword,
                      label: 'Mật khẩu proxy (tuỳ chọn)',
                    ),
                  ]),
                  _section('Bình luận', Icons.chat_bubble_outline, [
                    TextFormField(
                      key: const Key('comments'),
                      controller: _comments,
                      minLines: 3,
                      maxLines: 6,
                      decoration: _decoration('Nội dung comment',
                          helper: 'Mỗi dòng là một bình luận.'),
                    ),
                  ]),
                  _section('Đăng ký tài khoản', Icons.person_add_alt_1, [
                    TextFormField(
                      key: const Key('signupEmail'),
                      controller: _signupEmail,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _decoration('Email đăng ký'),
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
                      validator: (value) =>
                          _requestedAction == TikTokLaunchAction.signup &&
                                  (value == null || value.isEmpty)
                              ? 'Nhập mật khẩu đăng ký.'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      key: const Key('signupBirthday'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cake_outlined),
                      title: const Text('Ngày sinh đăng ký (Date of birth)'),
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
                  ]),
                  _section('Đăng nhập', Icons.login, [
                    TextFormField(
                      key: const Key('loginUsername'),
                      controller: _loginUsername,
                      autocorrect: false,
                      decoration: _decoration('Email / username đăng nhập'),
                      validator: (value) =>
                          _requestedAction == TikTokLaunchAction.login &&
                                  (value == null || value.trim().isEmpty)
                              ? 'Nhập tài khoản đăng nhập.'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    _PasswordField(
                      fieldKey: const Key('loginPassword'),
                      controller: _loginPassword,
                      label: 'Mật khẩu đăng nhập',
                      validator: (value) =>
                          _requestedAction == TikTokLaunchAction.login &&
                                  (value == null || value.isEmpty)
                              ? 'Nhập mật khẩu đăng nhập.'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    _otpField('loginOtp', _loginOtp, 'Mã OTP đăng nhập'),
                  ]),
                  _section('User Agent', Icons.computer, [
                    SelectableText(widget.userAgent,
                        key: const Key('userAgent'),
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const Key('runAutoLogin'),
                onPressed: _opening
                    ? null
                    : () => _openTikTok(TikTokLaunchAction.login),
                icon: _launchIcon(TikTokLaunchAction.login, Icons.login),
                label: const Text('Chạy đăng nhập tự động'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('runAutoSignup'),
                onPressed: _opening
                    ? null
                    : () => _openTikTok(TikTokLaunchAction.signup),
                icon: _launchIcon(
                    TikTokLaunchAction.signup, Icons.person_add_alt_1),
                label: const Text('Chạy đăng ký tự động'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('openTikTok'),
                onPressed: _opening
                    ? null
                    : () => _openTikTok(TikTokLaunchAction.browse),
                icon: _launchIcon(TikTokLaunchAction.browse, Icons.open_in_new),
                label: const Text('Mở TikTok'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _launchIcon(TikTokLaunchAction action, IconData icon) =>
      _opening && _requestedAction == action
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
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
          border: const OutlineInputBorder(),
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
