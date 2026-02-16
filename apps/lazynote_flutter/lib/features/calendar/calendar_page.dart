import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/calendar/calendar_controller.dart';
import 'package:lazynote_flutter/features/calendar/calendar_event_dialog.dart';
import 'package:lazynote_flutter/features/calendar/calendar_sidebar.dart';
import 'package:lazynote_flutter/features/calendar/calendar_style.dart';
import 'package:lazynote_flutter/features/calendar/week_grid_view.dart';

/// Calendar feature page mounted in Workbench left pane (PR-0012B).
///
/// Unified floating card with sidebar (mini month) and main content area.
/// Week navigation via `< >` arrows in the header.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.controller, this.onBackToWorkbench});

  /// Optional external controller for tests.
  final CalendarController? controller;

  /// Optional callback that returns to Workbench home section.
  final VoidCallback? onBackToWorkbench;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late final CalendarController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CalendarController();
    _ownsController = widget.controller == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.loadWeek();
    });
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          key: const Key('calendar_page_root'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            SizedBox(height: 600, child: _buildCard(context)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          key: const Key('calendar_back_to_workbench_button'),
          onPressed: widget.onBackToWorkbench,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to Workbench'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Calendar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: calendarHeaderTextColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          key: const Key('calendar_prev_week_button'),
          tooltip: 'Previous week',
          onPressed: _controller.previousWeek,
          icon: Icon(
            Icons.chevron_left,
            color: calendarHeaderTextColor(context),
          ),
        ),
        Text(
          _weekLabel(),
          key: const Key('calendar_week_label'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: calendarHeaderTextColor(context),
          ),
        ),
        IconButton(
          key: const Key('calendar_next_week_button'),
          tooltip: 'Next week',
          onPressed: _controller.nextWeek,
          icon: Icon(
            Icons.chevron_right,
            color: calendarHeaderTextColor(context),
          ),
        ),
        IconButton(
          key: const Key('calendar_reload_button'),
          tooltip: 'Reload calendar',
          onPressed: _controller.reload,
          icon: Icon(Icons.refresh, color: calendarHeaderTextColor(context)),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(kCalendarCardMargin),
      decoration: BoxDecoration(
        color: calendarCardBackground(context),
        borderRadius: BorderRadius.circular(kCalendarCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: kCalendarCardShadowOpacity),
            blurRadius: kCalendarCardShadowBlur,
            offset: kCalendarCardShadowOffset,
          ),
        ],
      ),
      child: Row(
        children: [
          CalendarSidebar(
            selectedDay: _controller.weekStart,
            onDaySelected: _controller.goToWeekOf,
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Colors.grey.withValues(alpha: 0.2),
            indent: kCalendarDividerIndent,
            endIndent: kCalendarDividerIndent,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(kCalendarCardRadius),
                bottomRight: Radius.circular(kCalendarCardRadius),
              ),
              child: _buildMainContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    if (_controller.phase == CalendarPhase.error) {
      return Center(
        key: const Key('calendar_error_state'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _controller.error ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return WeekGridView(
      key: const Key('calendar_week_grid'),
      weekStart: _controller.weekStart,
      events: _controller.events,
      onEmptySlotTap: (date, hour) => _showCreateDialog(date, hour),
      onEventTap: (item) => _showEditDialog(item),
    );
  }

  Future<void> _showCreateDialog(DateTime date, int hour) async {
    final result = await showDialog<CalendarEventResult>(
      context: context,
      builder: (_) => CalendarEventDialog(initialDate: date, initialHour: hour),
    );
    if (result != null) {
      await _controller.createEvent(result.title, result.startMs, result.endMs);
    }
  }

  Future<void> _showEditDialog(rust_api.AtomListItem item) async {
    if (item.startAt == null || item.endAt == null) return;
    final startDt = DateTime.fromMillisecondsSinceEpoch(item.startAt!.toInt());
    final result = await showDialog<CalendarEventResult>(
      context: context,
      builder: (_) => CalendarEventDialog(
        existingItem: item,
        initialDate: DateTime(startDt.year, startDt.month, startDt.day),
      ),
    );
    if (result != null) {
      await _controller.updateEvent(item.atomId, result.startMs, result.endMs);
    }
  }

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _weekLabel() {
    final start = _controller.weekStart;
    final end = _controller.weekEnd;
    final startMonth = _monthNames[start.month - 1];
    final endMonth = _monthNames[end.month - 1];
    final endPart = start.month == end.month
        ? '${end.day}, ${end.year}'
        : '$endMonth ${end.day}, ${end.year}';
    return '$startMonth ${start.day} – $endPart';
  }
}
