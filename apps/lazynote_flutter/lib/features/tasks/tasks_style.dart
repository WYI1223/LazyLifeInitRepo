import 'package:flutter/material.dart';

/// Shared visual tokens for Tasks dashboard.
///
/// All colors use semantic theme references for dark mode readiness.
/// Layout constants are stable across themes.

/// Card border radius.
const double kTasksCardRadius = 16.0;

/// Gap between the three section cards.
const double kTasksCardGap = 16.0;

/// Internal card padding.
const EdgeInsets kTasksCardPadding = EdgeInsets.all(16.0);

/// Vertical spacing between header and list body.
const double kTasksHeaderBodyGap = 12.0;

/// Vertical spacing between list rows.
const double kTasksRowGap = 6.0;

/// Icon size for section header icons.
const double kTasksHeaderIconSize = 20.0;

/// Icon size for row-level icons (bullet, checkbox).
const double kTasksRowIconSize = 18.0;

/// Card elevation for soft shadow.
const double kTasksCardElevation = 1.0;

/// Resolves card background color from theme.
Color tasksCardBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainer;

/// Resolves primary header text color from theme.
Color tasksHeaderTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

/// Resolves secondary / metadata text color from theme.
Color tasksSecondaryTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Resolves checkbox active color from theme.
Color tasksCheckboxActiveColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// Resolves date badge background color from theme.
Color tasksDateBadgeColor(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;
