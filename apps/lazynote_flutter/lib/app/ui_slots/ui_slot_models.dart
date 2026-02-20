import 'package:flutter/widgets.dart';

/// Logical UI extension slot layers.
enum UiSlotLayer { contentBlock, view, sidePanel, homeWidget }

/// Common slot identifiers used by first-party shell.
abstract final class UiSlotIds {
  static const String workbenchHomeBlocks = 'workbench.home.blocks';
  static const String workbenchHomeWidgets = 'workbench.home.widgets';
  static const String workbenchSectionView = 'workbench.section.view';
  static const String notesSidePanel = 'notes.side_panel';
}

/// Shared render-context keys.
abstract final class UiSlotContextKeys {
  static const String runtimeCapabilities = 'runtime_capabilities';
  static const String activeSection = 'active_section';
  static const String onOpenSection = 'on_open_section';
  static const String onOpenDiagnostics = 'on_open_diagnostics';
  static const String onBackToWorkbench = 'on_back_to_workbench';
  static const String notesController = 'notes_controller';
  static const String notesOnOpenNoteRequested = 'notes_on_open_note_requested';
  static const String notesOnOpenNotePinnedRequested =
      'notes_on_open_note_pinned_requested';
  static const String notesOnCreateNoteRequested =
      'notes_on_create_note_requested';
  static const String notesOnDeleteFolderRequested =
      'notes_on_delete_folder_requested';
  static const String notesOnCreateFolderRequested =
      'notes_on_create_folder_requested';
  static const String notesOnCreateNoteInFolderRequested =
      'notes_on_create_note_in_folder_requested';
  static const String notesOnRenameNodeRequested =
      'notes_on_rename_node_requested';
  static const String notesOnMoveNodeRequested = 'notes_on_move_node_requested';
}

/// Immutable per-render slot context bag.
@immutable
class UiSlotContext {
  const UiSlotContext([this._values = const <String, Object?>{}]);

  final Map<String, Object?> _values;

  /// Reads one optional value from slot context.
  T? read<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  /// Reads one required typed value from slot context.
  T require<T>(String key) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    throw StateError('Missing slot context key "$key" (expected $T).');
  }
}

/// Slot contribution render function.
typedef UiSlotBuilder =
    Widget Function(BuildContext context, UiSlotContext slotContext);

/// Optional slot contribution lifecycle callback.
typedef UiSlotLifecycleCallback = void Function(UiSlotContext slotContext);

/// One UI slot contribution descriptor.
@immutable
class UiSlotContribution {
  const UiSlotContribution({
    required this.contributionId,
    required this.slotId,
    required this.layer,
    required this.priority,
    required this.builder,
    this.enabledWhen,
    this.onMount,
    this.onDispose,
  });

  /// Stable namespaced contribution id.
  final String contributionId;

  /// Target slot id where this contribution can render.
  final String slotId;

  /// Slot layer.
  final UiSlotLayer layer;

  /// Higher value renders earlier.
  final int priority;

  /// Slot render function.
  final UiSlotBuilder builder;

  /// Optional predicate for conditional visibility.
  final bool Function(UiSlotContext slotContext)? enabledWhen;

  /// Optional lifecycle callback for host attach.
  final UiSlotLifecycleCallback? onMount;

  /// Optional lifecycle callback for host detach.
  final UiSlotLifecycleCallback? onDispose;
}

/// Slot registration validation error.
class UiSlotRegistryError implements Exception {
  /// Creates one stable slot-registry error payload.
  const UiSlotRegistryError({required this.code, required this.message});

  /// Stable machine-readable error code.
  final String code;

  /// Human-readable validation error message.
  final String message;
}
