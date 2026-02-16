import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/tasks/tasks_controller.dart';
import 'package:lazynote_flutter/features/tasks/tasks_style.dart';

/// Section variant for card header styling and row rendering.
enum TasksSectionType { inbox, today, upcoming }

/// Reusable card widget for one section (Inbox / Today / Upcoming).
///
/// Renders a card with:
/// - Header row: icon + title + optional trailing action
/// - List body: section-specific row styles
/// - Loading / error / empty states
class TasksSectionCard extends StatelessWidget {
  const TasksSectionCard({
    super.key,
    required this.section,
    required this.phase,
    required this.items,
    this.error,
    this.onToggleStatus,
    this.headerTrailing,
    this.listHeader,
  });

  final TasksSectionType section;
  final TasksPhase phase;
  final List<rust_api.AtomListItem> items;
  final String? error;
  final Future<void> Function(String atomId, String? currentStatus)?
  onToggleStatus;

  /// Optional trailing widget in the header (e.g. add button for Inbox).
  final Widget? headerTrailing;

  /// Optional widget inserted before the item list (e.g. inline text input).
  final Widget? listHeader;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: kTasksCardElevation,
      color: tasksCardBackground(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kTasksCardRadius),
      ),
      child: Padding(
        padding: kTasksCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const SizedBox(height: kTasksHeaderBodyGap),
            if (listHeader != null) ...[
              listHeader!,
              const SizedBox(height: kTasksRowGap),
            ],
            _buildBody(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          _sectionIcon,
          size: kTasksHeaderIconSize,
          color: tasksSecondaryTextColor(context),
        ),
        const SizedBox(width: 8),
        Text(
          _sectionTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: tasksHeaderTextColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (headerTrailing != null) ...[const Spacer(), headerTrailing!],
      ],
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    return switch (phase) {
      TasksPhase.idle || TasksPhase.loading => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      TasksPhase.error => _buildError(context),
      TasksPhase.success =>
        items.isEmpty ? _buildEmpty(context) : _buildList(context),
    };
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        error ?? 'Unknown error',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No items',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tasksSecondaryTextColor(context),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: kTasksRowGap),
          _buildRow(context, items[i]),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, rust_api.AtomListItem item) {
    return switch (section) {
      TasksSectionType.inbox => _InboxRow(item: item),
      TasksSectionType.today => _TodayRow(
        item: item,
        onToggle: onToggleStatus != null
            ? () async => onToggleStatus!(item.atomId, item.taskStatus)
            : null,
      ),
      TasksSectionType.upcoming => _UpcomingRow(item: item),
    };
  }

  String get _sectionTitle => switch (section) {
    TasksSectionType.inbox => 'Inbox',
    TasksSectionType.today => 'Today',
    TasksSectionType.upcoming => 'Upcoming',
  };

  IconData get _sectionIcon => switch (section) {
    TasksSectionType.inbox => Icons.inbox_outlined,
    TasksSectionType.today => Icons.wb_sunny_outlined,
    TasksSectionType.upcoming => Icons.calendar_month_outlined,
  };
}

/// Inbox row: bullet + content text.
class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item});
  final rust_api.AtomListItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '•',
            style: TextStyle(
              fontSize: kTasksRowIconSize,
              color: tasksSecondaryTextColor(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _displayText(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tasksHeaderTextColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Today row: checkbox + content text.
class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.item, this.onToggle});
  final rust_api.AtomListItem item;
  final Future<void> Function()? onToggle;

  @override
  Widget build(BuildContext context) {
    final isDone = item.taskStatus == 'done';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: kTasksRowIconSize,
          height: kTasksRowIconSize,
          child: Checkbox(
            value: isDone,
            onChanged: onToggle != null
                ? (_) {
                    onToggle!();
                  }
                : null,
            activeColor: tasksCheckboxActiveColor(context),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _displayText(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tasksHeaderTextColor(context),
              decoration: isDone ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Upcoming row: content text + date badge on the right.
class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.item});
  final rust_api.AtomListItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _displayText(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tasksHeaderTextColor(context),
            ),
          ),
        ),
        if (_dateBadge(item) case final badge?) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tasksDateBadgeColor(context),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tasksSecondaryTextColor(context),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _dateBadge(rust_api.AtomListItem item) {
    final ms = item.startAt ?? item.endAt;
    if (ms == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return _shortWeekday(date.weekday);
  }

  String _shortWeekday(int weekday) => switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '',
  };
}

/// Extracts display text from an atom list item.
///
/// Prefers preview_text over raw content, falls back to first line.
String _displayText(rust_api.AtomListItem item) {
  if (item.previewText case final preview? when preview.trim().isNotEmpty) {
    return preview;
  }
  final firstLine = item.content
      .split(RegExp(r'\r?\n'))
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => 'Untitled');
  return firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
}
