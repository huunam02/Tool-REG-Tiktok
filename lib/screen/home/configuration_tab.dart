import 'package:flutter/material.dart';

import '../../controller/home_controller.dart';
import '../../core/services/remote_config_service.dart';
import 'home_style.dart';
import 'remote_entries_page.dart';

/// Cấu hình tab: the configuration list entry point, and the search
/// keywords and comments that nurture uses (from Remote Config).
class ConfigurationTab extends StatelessWidget {
  const ConfigurationTab({
    super.key,
    required this.logic,
    required this.onManageProxies,
  });

  final HomeController logic;
  final VoidCallback onManageProxies;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final keywords = RemoteConfig.searchKeywords;
      final comments = RemoteConfig.autoComments;
      return SingleChildScrollView(
        key: const PageStorageKey('home-general'),
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeSection(
                  title: 'Cấu hình',
                  description: 'Thêm, sửa hoặc xóa proxy và tài khoản.',
                  icon: Icons.public,
                  children: [
                    // Runs stay disabled until the configuration loads.
                    if (logic.proxyLoadFailed) ...[
                      const Text('Không thể tải cấu hình. Hãy thử lại.'),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('retryProxyCache'),
                        onPressed: logic.busy ? null : logic.restoreProxy,
                        child: const Text('Tải lại cấu hình'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                      key: const Key('manageProxies'),
                      onPressed: logic.busy ? null : onManageProxies,
                      child: const Text('Quản lý cấu hình'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                HomeSection(
                  title: 'Keyword search (${keywords.length})',
                  description:
                      'Nuôi bằng tìm kiếm chọn ngẫu nhiên một từ khóa.',
                  icon: Icons.search,
                  children: [
                    _Entries(
                      keywords,
                      key: const Key('searchKeywordList'),
                      title: 'Keyword search',
                      viewAllKey: const Key('viewAllSearchKeywords'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                HomeSection(
                  title: 'Danh sách comment (${comments.length})',
                  description: 'Bình luận được chọn ngẫu nhiên khi nuôi.',
                  icon: Icons.chat_bubble_outline,
                  children: [
                    _Entries(
                      comments,
                      key: const Key('commentList'),
                      title: 'Danh sách comment',
                      viewAllKey: const Key('viewAllComments'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A read-only list; the values are managed in Remote Config.
class _Entries extends StatelessWidget {
  const _Entries(
    this.values, {
    super.key,
    required this.title,
    required this.viewAllKey,
  });

  final List<String> values;
  final String title;
  final Key viewAllKey;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text(
        'Chưa có dữ liệu trong Remote Config.',
        style: TextStyle(fontSize: 13, color: HomeStyle.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length && i < 3; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: RemoteEntryTile(value: values[i], index: i),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: viewAllKey,
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => RemoteEntriesPage(title: title, values: values),
            ),
          ),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Xem tất cả'),
        ),
      ],
    );
  }
}
