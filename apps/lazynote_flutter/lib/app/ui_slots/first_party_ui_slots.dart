import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/note_explorer.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';

/// Canonical workbench section ids for slot contexts.
abstract final class WorkbenchSectionIds {
  static const String home = 'home';
  static const String notes = 'notes';
  static const String tasks = 'tasks';
  static const String calendar = 'calendar';
  static const String settings = 'settings';
  static const String rustDiagnostics = 'rustDiagnostics';
}

/// Callback contract for section open action in workbench shell.
typedef WorkbenchOpenSectionCallback = void Function(String sectionId);

/// Creates one registry with default first-party slot contributions.
UiSlotRegistry createFirstPartyUiSlotRegistry() {
  final registry = UiSlotRegistry();
  registerFirstPartyUiSlots(registry);
  return registry;
}

/// Registers default first-party slot contributions.
void registerFirstPartyUiSlots(UiSlotRegistry registry) {
  _registerWorkbenchHomeSlots(registry);
  _registerNotesSlots(registry);
}

void _registerWorkbenchHomeSlots(UiSlotRegistry registry) {
  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.workbench.home.diagnostics_block',
      slotId: UiSlotIds.workbenchHomeBlocks,
      layer: UiSlotLayer.contentBlock,
      priority: 200,
      builder: (context, slotContext) {
        final openDiagnostics = slotContext.require<VoidCallback>(
          UiSlotContextKeys.onOpenDiagnostics,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: openDiagnostics,
              child: const Text('Rust Diagnostics'),
            ),
          ],
        );
      },
    ),
  );

  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.workbench.home.widget.notes_button',
      slotId: UiSlotIds.workbenchHomeWidgets,
      layer: UiSlotLayer.homeWidget,
      priority: 400,
      builder: (context, slotContext) {
        final openSection = slotContext.require<WorkbenchOpenSectionCallback>(
          UiSlotContextKeys.onOpenSection,
        );
        return OutlinedButton(
          onPressed: () => openSection(WorkbenchSectionIds.notes),
          child: const Text('Notes'),
        );
      },
    ),
  );
  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.workbench.home.widget.tasks_button',
      slotId: UiSlotIds.workbenchHomeWidgets,
      layer: UiSlotLayer.homeWidget,
      priority: 300,
      builder: (context, slotContext) {
        final openSection = slotContext.require<WorkbenchOpenSectionCallback>(
          UiSlotContextKeys.onOpenSection,
        );
        return OutlinedButton(
          onPressed: () => openSection(WorkbenchSectionIds.tasks),
          child: const Text('Tasks'),
        );
      },
    ),
  );
  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.workbench.home.widget.calendar_button',
      slotId: UiSlotIds.workbenchHomeWidgets,
      layer: UiSlotLayer.homeWidget,
      priority: 200,
      builder: (context, slotContext) {
        final openSection = slotContext.require<WorkbenchOpenSectionCallback>(
          UiSlotContextKeys.onOpenSection,
        );
        return OutlinedButton(
          onPressed: () => openSection(WorkbenchSectionIds.calendar),
          child: const Text('Calendar'),
        );
      },
    ),
  );
  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.workbench.home.widget.settings_button',
      slotId: UiSlotIds.workbenchHomeWidgets,
      layer: UiSlotLayer.homeWidget,
      priority: 100,
      builder: (context, slotContext) {
        final openSection = slotContext.require<WorkbenchOpenSectionCallback>(
          UiSlotContextKeys.onOpenSection,
        );
        return OutlinedButton(
          onPressed: () => openSection(WorkbenchSectionIds.settings),
          child: const Text('Settings (Placeholder)'),
        );
      },
    ),
  );
}

void _registerNotesSlots(UiSlotRegistry registry) {
  registry.register(
    UiSlotContribution(
      contributionId: 'builtin.notes.side_panel.explorer',
      slotId: UiSlotIds.notesSidePanel,
      layer: UiSlotLayer.sidePanel,
      priority: 500,
      builder: (context, slotContext) {
        final controller = slotContext.require<NotesController>(
          UiSlotContextKeys.notesController,
        );
        final onOpenNoteRequested = slotContext.require<ValueChanged<String>>(
          UiSlotContextKeys.notesOnOpenNoteRequested,
        );
        final onCreateNoteRequested = slotContext
            .require<Future<void> Function()>(
              UiSlotContextKeys.notesOnCreateNoteRequested,
            );
        final onDeleteFolderRequested = slotContext
            .read<
              Future<rust_api.WorkspaceActionResponse> Function(String, String)
            >(UiSlotContextKeys.notesOnDeleteFolderRequested);
        return NoteExplorer(
          controller: controller,
          onOpenNoteRequested: onOpenNoteRequested,
          onCreateNoteRequested: onCreateNoteRequested,
          onDeleteFolderRequested: onDeleteFolderRequested,
        );
      },
    ),
  );
}
