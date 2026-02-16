import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/calendar/calendar_style.dart';

/// A single event block rendered inside the week grid.
///
/// Positioned by the parent [WeekGridView] via Stack/Positioned.
/// Uses [CalendarPalette] for pastel background and text colors.
class EventBlock extends StatelessWidget {
  const EventBlock({
    super.key,
    required this.title,
    required this.colorIndex,
    this.onTap,
  });

  /// Display text (preview_text or content first line).
  final String title;

  /// Index into [CalendarPalette] color arrays.
  final int colorIndex;

  /// Optional tap callback for edit interaction (PR-0012D).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = CalendarPalette.eventBlockColor(context, colorIndex);
    final textColor = CalendarPalette.eventTextColor(context, colorIndex);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
