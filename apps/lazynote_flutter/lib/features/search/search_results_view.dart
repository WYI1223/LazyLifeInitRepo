import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;

/// Search results section for the Single Entry panel.
class SearchResultsView extends StatelessWidget {
  const SearchResultsView({
    super.key,
    required this.visible,
    required this.isLoading,
    required this.errorMessage,
    required this.items,
    required this.appliedLimit,
  });

  final bool visible;
  final bool isLoading;
  final String? errorMessage;
  final List<rust_api.EntrySearchItem> items;
  final int? appliedLimit;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    if (isLoading) {
      return const Card(
        key: Key('single_entry_search_loading'),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Searching...'),
        ),
      );
    }

    if (errorMessage != null) {
      return Card(
        key: const Key('single_entry_search_error'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Card(
        key: Key('single_entry_search_empty'),
        child: Padding(padding: EdgeInsets.all(12), child: Text('No results.')),
      );
    }

    return Card(
      key: const Key('single_entry_search_results'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search Results (${items.length})',
              style: theme.textTheme.titleSmall,
            ),
            if (appliedLimit != null) ...[
              const SizedBox(height: 4),
              Text(
                'Applied limit: $appliedLimit',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            for (var index = 0; index < items.length; index++) ...[
              _SearchResultRow(item: items[index], index: index),
              if (index != items.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.item, required this.index});

  final rust_api.EntrySearchItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('single_entry_search_item_$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '[${item.kind}] ${item.atomId}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Text(item.snippet, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
