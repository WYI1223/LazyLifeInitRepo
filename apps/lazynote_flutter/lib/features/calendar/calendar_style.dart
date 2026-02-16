import 'package:flutter/material.dart';

/// Layout constants for the unified calendar card.
const double kCalendarCardRadius = 24.0;
const double kCalendarSidebarWidth = 260.0;
const double kCalendarHourHeight = 60.0;
const double kCalendarTimeAxisWidth = 56.0;
const double kCalendarDividerIndent = 30.0;
const double kCalendarCardMargin = 24.0;

/// Shadow opacity for the unified card container.
const double kCalendarCardShadowOpacity = 0.06;
const double kCalendarCardShadowBlur = 30.0;
const Offset kCalendarCardShadowOffset = Offset(0, 10);

/// Returns the unified card background color from the current theme.
Color calendarCardBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainer;

/// Returns the calendar header text color from the current theme.
Color calendarHeaderTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

/// Returns the calendar secondary text color from the current theme.
Color calendarSecondaryTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Pastel event block colors with explicit Light/Dark pairs.
///
/// Design decision D2: base UI uses colorScheme, event blocks use CalendarPalette.
class CalendarPalette {
  CalendarPalette._();

  static const _lightColors = [
    Color(0xFFD6E6CE), // Sage
    Color(0xFFCBE4F9), // Baby Blue
    Color(0xFFE6D6F5), // Lavender
  ];

  static const _darkColors = [
    Color(0xFF2C3E28), // Sage Dark
    Color(0xFF1A3A5C), // Baby Blue Dark
    Color(0xFF3D2C52), // Lavender Dark
  ];

  /// Current time red indicator color (same for both modes).
  static const Color redIndicator = Color(0xFFFF5A5F);

  /// Returns the event block background color for the given index.
  static Color eventBlockColor(BuildContext context, int colorIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? _darkColors : _lightColors;
    return palette[colorIndex % palette.length];
  }

  /// Returns the event block text color for readability.
  static Color eventTextColor(BuildContext context, int colorIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFFE0E0E0) : const Color(0xFF2C2C2C);
  }
}
