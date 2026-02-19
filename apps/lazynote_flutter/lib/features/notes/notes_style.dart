import 'package:flutter/material.dart';

/// Shared visual tokens for Notes shell.
///
/// These constants intentionally stay close to Single Entry light-theme tones
/// so Notes keeps a consistent minimalist surface in Workbench.
const Color kNotesSidebarBackground = Color(0xFFF7F7F5);

/// Unified Notes shell radius aligned with v0.2 card language.
const double kNotesShellRadius = 20;

/// Inset divider indentation used by split panes.
const double kNotesShellDividerIndent = 12;

/// Outer spacing between Notes header and shell card.
const double kNotesShellTopGap = 12;

/// Shadow blur for Notes shell card.
const double kNotesShellShadowBlur = 24;

/// Shadow offset for Notes shell card.
const Offset kNotesShellShadowOffset = Offset(0, 8);

/// Shadow opacity for Notes shell card.
const double kNotesShellShadowOpacity = 0.05;

/// Shared height for explorer header row and top tab strip.
const double kNotesTopStripHeight = 40;

/// Main document canvas background color.
const Color kNotesCanvasBackground = Color(0xFFFFFFFF);

/// Primary text color for titles and body content.
const Color kNotesPrimaryText = Color(0xFF37352F);

/// Secondary text color for metadata and auxiliary labels.
const Color kNotesSecondaryText = Color(0xFF6B6B6B);

/// Divider and subtle border color.
const Color kNotesDividerColor = Color(0xFFE3E2DE);

/// Row hover fill used in explorer and tab strip.
const Color kNotesItemHoverColor = Color(0xFFEDECE8);

/// Active item fill for selected notes/tabs.
const Color kNotesItemSelectedColor = Color(0xFFE9E8E3);

/// Shared placeholder icon for note rows and top tabs.
const IconData kNotesItemPlaceholderIcon = Icons.description_outlined;

/// Error surface background color for inline detail failures.
const Color kNotesErrorBackground = Color(0xFFFFEBEE);

/// Error surface border color for inline detail failures.
const Color kNotesErrorBorder = Color(0xFFFFCDD2);

/// Resolves Notes shell card background from current theme.
Color notesShellBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainer;

/// Resolves Notes shell headline text color from current theme.
Color notesHeaderTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

/// Resolves Notes secondary text color from current theme.
Color notesSecondaryTextColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Resolves Notes split divider color from current theme.
Color notesDividerColor(BuildContext context) =>
    Theme.of(context).colorScheme.outlineVariant;
