import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/calendar/calendar_style.dart';
import 'package:table_calendar/table_calendar.dart';

/// Mini month calendar sidebar for the unified calendar card.
///
/// Uses `table_calendar` package in month format.
/// Tapping a day triggers [onDaySelected], which navigates to that week.
class CalendarSidebar extends StatefulWidget {
  const CalendarSidebar({
    super.key,
    required this.selectedDay,
    required this.onDaySelected,
  });

  /// Currently focused day (used for highlighting).
  final DateTime selectedDay;

  /// Callback when user taps a day in the mini month.
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<CalendarSidebar> createState() => _CalendarSidebarState();
}

class _CalendarSidebarState extends State<CalendarSidebar> {
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDay;
  }

  @override
  void didUpdateWidget(CalendarSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay) {
      _focusedDay = widget.selectedDay;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kCalendarSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TableCalendar<void>(
              key: const Key('calendar_mini_month'),
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(day, widget.selectedDay),
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarFormat: CalendarFormat.month,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle:
                    Theme.of(context).textTheme.titleSmall ?? const TextStyle(),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: calendarSecondaryTextColor(context),
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: calendarSecondaryTextColor(context),
                ),
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                defaultTextStyle: TextStyle(
                  color: calendarHeaderTextColor(context),
                  fontSize: 13,
                ),
                weekendTextStyle: TextStyle(
                  color: calendarSecondaryTextColor(context),
                  fontSize: 13,
                ),
                outsideTextStyle: TextStyle(
                  color: calendarSecondaryTextColor(
                    context,
                  ).withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: calendarSecondaryTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                weekendStyle: TextStyle(
                  color: calendarSecondaryTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
                widget.onDaySelected(selectedDay);
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
