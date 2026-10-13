import 'package:flutter/material.dart';

import '../../core/proxy_store.dart';
import '../../core/app_configuration.dart';
import '../../controller/proxy_form_controller.dart';
import 'controller_scope.dart';
import 'proxy_widgets.dart';

export '../../core/proxy_draft.dart';

class ProxyForm extends StatelessWidget {
  const ProxyForm({
    super.key,
    this.entry,
    required this.title,
    required this.submitLabel,
    required this.randomizeOnOpen,
    required this.generateUserAgent,
  });

  final SavedProxy? entry;
  final String title;
  final String submitLabel;
  final bool randomizeOnOpen;
  final Future<String> Function() generateUserAgent;

  @override
  Widget build(BuildContext context) => ControllerScope<ProxyFormController>(
        controller: ProxyFormController(
            entry: entry,
            randomizeOnOpen: randomizeOnOpen,
            selectUserAgent: generateUserAgent),
        builder: (logic) => _ProxyFormView(
            logic: logic,
            title: title,
            submitLabel: submitLabel,
            randomizeOnOpen: randomizeOnOpen),
      );
}

class _ProxyFormView extends StatelessWidget {
  const _ProxyFormView(
      {required this.logic,
      required this.title,
      required this.submitLabel,
      required this.randomizeOnOpen});
  final ProxyFormController logic;
  final String title;
  final String submitLabel;
  final bool randomizeOnOpen;

  Future<void> _save(BuildContext context) async {
    final draft = await logic.save();
    if (draft != null && context.mounted) Navigator.pop(context, draft);
  }

  Widget _section(
          String title, String helper, IconData icon, List<Widget> children) =>
      ProxyPanel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: ProxyColors.cyan.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 19, color: ProxyColors.cyan)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(helper,
                    style: const TextStyle(
                        fontSize: 12, height: 1.5, color: ProxyColors.muted)),
              ])),
        ]),
        const SizedBox(height: 20),
        ...children,
      ]));

  @override
  Widget build(BuildContext context) => Theme(
      data: ProxyColors.theme(context),
      child: Scaffold(
        appBar: AppBar(
            title: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700))),
        body: Form(
            key: logic.form,
            child: SingleChildScrollView(
              key: const Key('proxyEditorScroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('Thông tin kết nối',
                          'Nhập địa chỉ HTTP/HTTPS có cổng.', Icons.public, [
                        TextFormField(
                          key: const Key('savedProxyName'),
                          controller: logic.name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Tên proxy (không bắt buộc)',
                              hintText: 'Ví dụ: Việt Nam · Residential',
                              prefixIcon: Icon(Icons.label_outline, size: 20)),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('savedProxyUrl'),
                          controller: logic.url,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Địa chỉ proxy',
                              hintText: 'http://host:port',
                              prefixIcon: Icon(Icons.link, size: 20)),
                          validator: (value) {
                            try {
                              return WebViewProxy.parse(value ?? '') == null
                                  ? 'Nhập địa chỉ proxy.'
                                  : null;
                            } on FormatException catch (error) {
                              return error.message;
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('savedProxyUsername'),
                          controller: logic.username,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Tên đăng nhập (không bắt buộc)',
                              prefixIcon: Icon(Icons.person_outline, size: 20)),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('savedProxyPassword'),
                          controller: logic.password,
                          obscureText: logic.hidden,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu (không bắt buộc)',
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              tooltip: logic.hidden
                                  ? 'Hiện mật khẩu'
                                  : 'Ẩn mật khẩu',
                              onPressed: () => logic.togglePassword(),
                              icon: Icon(logic.hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _section(
                          'User-Agent',
                          randomizeOnOpen
                              ? 'Tự random khi tạo mới. Bạn có thể tạo lại hoặc nhập riêng.'
                              : 'Giữ User-Agent đã lưu. Bạn có thể tạo lại hoặc nhập riêng.',
                          Icons.computer_outlined,
                          [
                            TextFormField(
                              key: const Key('savedProxyUserAgent'),
                              controller: logic.userAgent,
                              onChanged: (_) => logic.update(),
                              enabled: !logic.generating,
                              autocorrect: false,
                              enableSuggestions: false,
                              minLines: 3,
                              maxLines: 6,
                              style: const TextStyle(fontSize: 12, height: 1.6),
                              decoration: const InputDecoration(
                                  labelText: 'User-Agent'),
                              validator: (value) => value == null ||
                                      value.trim().isEmpty ||
                                      RegExp(r'[\r\n]').hasMatch(value.trim())
                                  ? 'Nhập User-Agent hợp lệ trên một dòng.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              key: const Key('generateProxyUserAgent'),
                              onPressed: logic.generating
                                  ? null
                                  : logic.generateUserAgent,
                              child: Text(
                                logic.generating
                                    ? 'Đang tạo User-Agent…'
                                    : 'Tạo User-Agent mới',
                              ),
                            ),
                            if (logic.generationFailed)
                              const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(
                                      'Không thể tạo User-Agent. Nhấn nút để thử lại.',
                                      style: TextStyle(
                                          color: ProxyColors.amber,
                                          fontSize: 12))),
                          ]),
                    ]),
              )),
            )),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
              color: ProxyColors.background,
              border: Border(top: BorderSide(color: ProxyColors.border))),
          child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                    key: const Key('saveProxyEntry'),
                    onPressed:
                        logic.generating || logic.userAgent.text.trim().isEmpty
                            ? null
                            : () => _save(context),
                    child: Text(submitLabel)),
              )),
        ),
      ));
}
