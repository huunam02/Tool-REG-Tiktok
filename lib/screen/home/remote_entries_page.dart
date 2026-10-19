import 'package:flutter/material.dart';

import 'home_style.dart';

/// Full read-only list of the keywords or comments shown on Home.
class RemoteEntriesPage extends StatelessWidget {
  const RemoteEntriesPage({
    super.key,
    required this.title,
    required this.values,
  });

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Theme(
    data: HomeStyle.theme(context),
    child: Scaffold(
      backgroundColor: HomeStyle.background,
      appBar: AppBar(
        backgroundColor: HomeStyle.background,
        surfaceTintColor: Colors.transparent,
        title: Text('$title (${values.length})'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView.separated(
              key: const Key('remoteEntriesList'),
              padding: const EdgeInsets.all(16),
              itemCount: values.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) =>
                  RemoteEntryTile(value: values[index], index: index),
            ),
          ),
        ),
      ),
    ),
  );
}

class RemoteEntryTile extends StatelessWidget {
  const RemoteEntryTile({super.key, required this.value, required this.index});

  final String value;
  final int index;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: HomeStyle.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HomeStyle.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            '${index + 1}.',
            style: const TextStyle(fontSize: 13, color: HomeStyle.muted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
