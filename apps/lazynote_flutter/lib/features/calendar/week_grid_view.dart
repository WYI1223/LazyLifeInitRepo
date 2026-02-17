import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/calendar/calendar_style.dart';
import 'package:lazynote_flutter/features/calendar/event_block.dart';

/// Day header abbreviations (Mon–Sun).
const _dayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Self-built weekly calendar grid with time axis and event positioning.
///
/// Layout: day header row → scrollable hour grid (0:00–23:00) with
/// event blocks placed via Stack + Positioned.
class WeekGridView extends StatelessWidget {
  const WeekGridView({
    super.key,
    required this.weekStart,
    required this.events,
    this.onEventTap,
    this.onEmptySlotTap,
  });

  /// Monday of the displayed week.
  final DateTime weekStart;

  /// Events to render in the grid.
  final List<rust_api.AtomListItem> events;

  /// Tap callback on an event block (PR-0012D).
  final void Function(rust_api.AtomListItem item)? onEventTap;

  /// Tap callback on an empty grid slot (PR-0012D).
  final void Function(DateTime date, int hour)? onEmptySlotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DayHeaderRow(
          key: const Key('week_grid_day_headers'),
          weekStart: weekStart,
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: SingleChildScrollView(
            child: _GridBody(
              weekStart: weekStart,
              events: events,
              onEventTap: onEventTap,
              onEmptySlotTap: onEmptySlotTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// Row of day headers showing abbreviated day name and date number.
class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({super.key, required this.weekStart});

  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final textColor = calendarHeaderTextColor(context);
    final secondaryColor = calendarSecondaryTextColor(context);

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Time axis placeholder
          SizedBox(width: kCalendarTimeAxisWidth),
          // 7 day columns
          for (int i = 0; i < 7; i++) ...[
            Expanded(
              child: _buildDayHeader(
                context,
                dayIndex: i,
                today: today,
                textColor: textColor,
                secondaryColor: secondaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context, {
    required int dayIndex,
    required DateTime today,
    required Color textColor,
    required Color secondaryColor,
  }) {
    final date = weekStart.add(Duration(days: dayIndex));
    final isToday = date == today;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _dayAbbreviations[dayIndex],
          style: TextStyle(
            color: isToday ? primaryColor : secondaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 28,
          height: 28,
          decoration: isToday
              ? BoxDecoration(color: primaryColor, shape: BoxShape.circle)
              : null,
          alignment: Alignment.center,
          child: Text(
            '${date.day}',
            style: TextStyle(
              color: isToday
                  ? Theme.of(context).colorScheme.onPrimary
                  : textColor,
              fontSize: 14,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The scrollable grid body: time axis + 7 day columns with event blocks.
class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.weekStart,
    required this.events,
    this.onEventTap,
    this.onEmptySlotTap,
  });

  final DateTime weekStart;
  final List<rust_api.AtomListItem> events;
  final void Function(rust_api.AtomListItem item)? onEventTap;
  final void Function(DateTime date, int hour)? onEmptySlotTap;

  static const int _totalHours = 24;
  static const double _minBlockHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final totalHeight = _totalHours * kCalendarHourHeight;

    return SizedBox(
      height: totalHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimeAxis(key: const Key('week_grid_time_axis')),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth = constraints.maxWidth / 7;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: onEmptySlotTap != null
                      ? (details) =>
                            _handleGridTap(details.localPosition, columnWidth)
                      : null,
                  child: Stack(
                    children: [
                      // Grid lines
                      _GridLines(
                        key: const Key('week_grid_lines'),
                        totalHeight: totalHeight,
                        columnWidth: columnWidth,
                      ),
                      // Current time indicator
                      _CurrentTimeIndicator(
                        weekStart: weekStart,
                        columnWidth: columnWidth,
                      ),
                      // Event blocks
                      ..._buildEventBlocks(context, columnWidth),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleGridTap(Offset localPosition, double columnWidth) {
    final dayIndex = (localPosition.dx / columnWidth).floor().clamp(0, 6);
    final hour = (localPosition.dy / kCalendarHourHeight).floor().clamp(0, 23);
    final date = weekStart.add(Duration(days: dayIndex));
    onEmptySlotTap!(date, hour);
  }

  List<Widget> _buildEventBlocks(BuildContext context, double columnWidth) {
    final blocks = <Widget>[];

    for (int i = 0; i < events.length; i++) {
      final item = events[i];
      if (item.startAt == null || item.endAt == null) continue;

      final startMs = item.startAt!.toInt();
      final endMs = item.endAt!.toInt();
      final startDt = DateTime.fromMillisecondsSinceEpoch(startMs);
      final endDt = DateTime.fromMillisecondsSinceEpoch(endMs);

      // An event may span multiple days; render a block per visible day.
      for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
        final dayDate = weekStart.add(Duration(days: dayIndex));
        final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day);
        final dayEnd = dayStart.add(const Duration(days: 1));

        // Skip if event doesn't overlap this day
        if (startDt.millisecondsSinceEpoch >= dayEnd.millisecondsSinceEpoch ||
            endDt.millisecondsSinceEpoch <= dayStart.millisecondsSinceEpoch) {
          continue;
        }

        // Clamp to this day's boundaries
        final blockStartMs =
            startDt.millisecondsSinceEpoch < dayStart.millisecondsSinceEpoch
            ? dayStart.millisecondsSinceEpoch
            : startDt.millisecondsSinceEpoch;
        final blockEndMs =
            endDt.millisecondsSinceEpoch > dayEnd.millisecondsSinceEpoch
            ? dayEnd.millisecondsSinceEpoch
            : endDt.millisecondsSinceEpoch;

        // Calculate vertical position
        final msFromDayStart = blockStartMs - dayStart.millisecondsSinceEpoch;
        final blockDurationMs = blockEndMs - blockStartMs;
        const msPerHour = 3600000;

        final top = (msFromDayStart / msPerHour) * kCalendarHourHeight;
        final height = (blockDurationMs / msPerHour) * kCalendarHourHeight;
        final effectiveHeight = height < _minBlockHeight
            ? _minBlockHeight
            : height;

        final left = dayIndex * columnWidth + 2;
        final blockWidth = columnWidth - 4;
        final title = item.previewText ?? item.content.split('\n').first;

        blocks.add(
          Positioned(
            key: Key('event_block_${item.atomId}_day$dayIndex'),
            top: top,
            left: left,
            width: blockWidth > 0 ? blockWidth : 0,
            height: effectiveHeight,
            child: EventBlock(
              title: title,
              colorIndex: i,
              onTap: onEventTap != null ? () => onEventTap!(item) : null,
            ),
          ),
        );
      }
    }

    return blocks;
  }
}

/// Vertical time axis showing hour labels (0:00–23:00).
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({super.key});

  @override
  Widget build(BuildContext context) {
    final color = calendarSecondaryTextColor(context);

    return SizedBox(
      width: kCalendarTimeAxisWidth,
      child: Column(
        children: [
          for (int h = 0; h < 24; h++)
            SizedBox(
              height: kCalendarHourHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 0),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal and vertical grid lines painted behind event blocks.
class _GridLines extends StatelessWidget {
  const _GridLines({
    super.key,
    required this.totalHeight,
    required this.columnWidth,
  });

  final double totalHeight;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final lineColor = calendarSecondaryTextColor(
      context,
    ).withValues(alpha: 0.15);

    return CustomPaint(
      size: Size(columnWidth * 7, totalHeight),
      painter: _GridLinesPainter(
        lineColor: lineColor,
        columnWidth: columnWidth,
        hourHeight: kCalendarHourHeight,
      ),
    );
  }
}

class _GridLinesPainter extends CustomPainter {
  _GridLinesPainter({
    required this.lineColor,
    required this.columnWidth,
    required this.hourHeight,
  });

  final Color lineColor;
  final double columnWidth;
  final double hourHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    // Horizontal hour lines
    for (int h = 0; h <= 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical day dividers
    for (int d = 1; d < 7; d++) {
      final x = d * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter oldDelegate) =>
      lineColor != oldDelegate.lineColor ||
      columnWidth != oldDelegate.columnWidth ||
      hourHeight != oldDelegate.hourHeight;
}

/// Red horizontal line indicating the current time on today's column.
class _CurrentTimeIndicator extends StatelessWidget {
  const _CurrentTimeIndicator({
    required this.weekStart,
    required this.columnWidth,
  });

  final DateTime weekStart;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Check if today falls within this week
    final weekEnd = weekStart.add(const Duration(days: 7));
    if (today.isBefore(weekStart) || !today.isBefore(weekEnd)) {
      return const SizedBox.shrink();
    }

    final dayIndex = today.difference(weekStart).inDays;
    final minutesSinceMidnight = now.hour * 60 + now.minute;
    final top = (minutesSinceMidnight / 60) * kCalendarHourHeight;
    final left = dayIndex * columnWidth;

    return Positioned(
      key: const Key('week_grid_current_time_indicator'),
      top: top,
      left: left,
      width: columnWidth,
      height: 2,
      child: Container(
        decoration: BoxDecoration(
          color: CalendarPalette.redIndicator,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
