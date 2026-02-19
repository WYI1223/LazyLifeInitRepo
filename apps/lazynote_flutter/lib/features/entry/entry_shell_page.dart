import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/ui_slots/first_party_ui_slots.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_host.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';
import 'package:lazynote_flutter/features/calendar/calendar_page.dart';
import 'package:lazynote_flutter/features/diagnostics/rust_diagnostics_page.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';
import 'package:lazynote_flutter/features/entry/single_entry_panel.dart';
import 'package:lazynote_flutter/features/entry/workbench_shell_layout.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_page.dart';
import 'package:lazynote_flutter/features/settings/settings_capability_page.dart';
import 'package:lazynote_flutter/features/tasks/tasks_page.dart';

/// Left-pane sections inside Workbench shell.
enum WorkbenchSection {
  home,
  notes,
  tasks,
  calendar,
  settings,
  rustDiagnostics,
}

/// Default shell page used to validate new features before wiring final UIs.
///
/// Left-pane routing is handled in-place via state so the right logs panel
/// remains mounted and stable across section switches.
class EntryShellPage extends StatefulWidget {
  const EntryShellPage({
    super.key,
    this.initialSection = WorkbenchSection.home,
    this.uiSlotRegistry,
  });

  /// Initial left-pane section to render inside Workbench shell.
  final WorkbenchSection initialSection;
  final UiSlotRegistry? uiSlotRegistry;

  @override
  State<EntryShellPage> createState() => _EntryShellPageState();
}

class _EntryShellPageState extends State<EntryShellPage> {
  // Single Entry is the primary interactive path in Workbench after PR-0009C.
  final SingleEntryController _singleEntryController = SingleEntryController();
  final NotesController _notesController = NotesController();
  late final UiSlotRegistry _uiSlotRegistry;
  late WorkbenchSection _activeSection;
  bool _showSingleEntryPanel = false;

  @override
  void initState() {
    super.initState();
    _uiSlotRegistry = widget.uiSlotRegistry ?? createFirstPartyUiSlotRegistry();
    _activeSection = widget.initialSection;
  }

  @override
  void dispose() {
    _singleEntryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _openSection(WorkbenchSection section) {
    setState(() {
      _activeSection = section;
    });
  }

  void _openSectionById(String sectionId) {
    final section = switch (sectionId) {
      WorkbenchSectionIds.home => WorkbenchSection.home,
      WorkbenchSectionIds.notes => WorkbenchSection.notes,
      WorkbenchSectionIds.tasks => WorkbenchSection.tasks,
      WorkbenchSectionIds.calendar => WorkbenchSection.calendar,
      WorkbenchSectionIds.settings => WorkbenchSection.settings,
      WorkbenchSectionIds.rustDiagnostics => WorkbenchSection.rustDiagnostics,
      _ => WorkbenchSection.home,
    };
    _openSection(section);
  }

  String _sectionId(WorkbenchSection section) {
    return switch (section) {
      WorkbenchSection.home => WorkbenchSectionIds.home,
      WorkbenchSection.notes => WorkbenchSectionIds.notes,
      WorkbenchSection.tasks => WorkbenchSectionIds.tasks,
      WorkbenchSection.calendar => WorkbenchSectionIds.calendar,
      WorkbenchSection.settings => WorkbenchSectionIds.settings,
      WorkbenchSection.rustDiagnostics => WorkbenchSectionIds.rustDiagnostics,
    };
  }

  void _openOrFocusSingleEntryPanel() {
    setState(() {
      _showSingleEntryPanel = true;
    });
    // Why: defer focus request until panel subtree is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _singleEntryController.requestFocus();
    });
  }

  void _hideSingleEntryPanel() {
    setState(() {
      _showSingleEntryPanel = false;
    });
  }

  String _titleForSection(WorkbenchSection section) {
    final workspace = _notesController.workspaceProvider;
    final openTabs =
        workspace.openTabsByPane[workspace.activePaneId] ?? const <String>[];
    return switch (section) {
      WorkbenchSection.home => 'LazyNote Workbench',
      WorkbenchSection.notes =>
        openTabs.isEmpty ? 'Notes' : 'Notes (${openTabs.length})',
      WorkbenchSection.tasks => 'Tasks',
      WorkbenchSection.calendar => 'Calendar',
      WorkbenchSection.settings => 'Settings',
      WorkbenchSection.rustDiagnostics => 'Rust Diagnostics',
    };
  }

  Widget _buildWorkbenchHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Workbench Home',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Use Workbench to run Single Entry flow and diagnostics while '
          'feature UIs are landing.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Text('Single Entry', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              key: const Key('open_single_entry_panel_button'),
              onPressed: _openOrFocusSingleEntryPanel,
              child: Text(
                _showSingleEntryPanel
                    ? 'Focus Single Entry'
                    : 'Open Single Entry',
              ),
            ),
            if (_showSingleEntryPanel)
              OutlinedButton(
                key: const Key('hide_single_entry_panel_button'),
                onPressed: _hideSingleEntryPanel,
                child: const Text('Hide Single Entry'),
              ),
          ],
        ),
        // Keep Single Entry embedded in Workbench instead of route replacement
        // so the right-side debug logs panel remains stable while testing.
        if (_showSingleEntryPanel) ...[
          const SizedBox(height: 12),
          SingleEntryPanel(
            controller: _singleEntryController,
            onClose: _hideSingleEntryPanel,
          ),
        ],
        const SizedBox(height: 24),
        UiSlotListHost(
          registry: _uiSlotRegistry,
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          slotContext: UiSlotContext({
            UiSlotContextKeys.onOpenDiagnostics: () {
              _openSection(WorkbenchSection.rustDiagnostics);
            },
          }),
          listBuilder: (context, children) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(height: 24),
                  children[index],
                ],
              ],
            );
          },
          fallbackBuilder: (context) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnostics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () =>
                      _openSection(WorkbenchSection.rustDiagnostics),
                  child: const Text('Rust Diagnostics'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Placeholder Routes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        UiSlotListHost(
          registry: _uiSlotRegistry,
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          slotContext: UiSlotContext({
            UiSlotContextKeys.onOpenSection: _openSectionById,
          }),
          listBuilder: (context, children) {
            return Wrap(spacing: 12, runSpacing: 12, children: children);
          },
          fallbackBuilder: (context) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => _openSection(WorkbenchSection.notes),
                  child: const Text('Notes'),
                ),
                OutlinedButton(
                  onPressed: () => _openSection(WorkbenchSection.tasks),
                  child: const Text('Tasks'),
                ),
                OutlinedButton(
                  onPressed: () => _openSection(WorkbenchSection.calendar),
                  child: const Text('Calendar'),
                ),
                OutlinedButton(
                  onPressed: () => _openSection(WorkbenchSection.settings),
                  child: const Text('Settings'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRustDiagnosticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rust Diagnostics',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const RustDiagnosticsContent(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _openSection(WorkbenchSection.home),
          child: const Text('Back to Workbench'),
        ),
      ],
    );
  }

  Widget _buildActiveLeftContent() {
    return UiSlotViewHost(
      registry: _uiSlotRegistry,
      slotId: UiSlotIds.workbenchSectionView,
      slotContext: UiSlotContext({
        UiSlotContextKeys.activeSection: _sectionId(_activeSection),
        UiSlotContextKeys.onBackToWorkbench: () {
          _openSection(WorkbenchSection.home);
        },
      }),
      fallbackBuilder: (context) {
        return switch (_activeSection) {
          WorkbenchSection.home => _buildWorkbenchHome(),
          WorkbenchSection.notes => NotesPage(
            controller: _notesController,
            onBackToWorkbench: () => _openSection(WorkbenchSection.home),
            uiSlotRegistry: _uiSlotRegistry,
          ),
          WorkbenchSection.tasks => TasksPage(
            onBackToWorkbench: () => _openSection(WorkbenchSection.home),
          ),
          WorkbenchSection.calendar => CalendarPage(
            onBackToWorkbench: () => _openSection(WorkbenchSection.home),
          ),
          WorkbenchSection.settings => SettingsCapabilityPage(
            onBackToWorkbench: () => _openSection(WorkbenchSection.home),
          ),
          WorkbenchSection.rustDiagnostics => _buildRustDiagnosticsSection(),
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _notesController.workspaceProvider,
      builder: (context, _) {
        return WorkbenchShellLayout(
          title: _titleForSection(_activeSection),
          content: _buildActiveLeftContent(),
        );
      },
    );
  }
}

/// Compatibility wrapper for legacy direct route entries.
class FeaturePlaceholderPage extends StatelessWidget {
  const FeaturePlaceholderPage({
    super.key,
    required this.title,
    required this.description,
  });

  /// Placeholder title used to map route into a Workbench section.
  final String title;

  /// Placeholder text shown by the mapped section.
  final String description;

  @override
  Widget build(BuildContext context) {
    final section = switch (title.toLowerCase()) {
      'notes' => WorkbenchSection.notes,
      'tasks' => WorkbenchSection.tasks,
      'calendar' => WorkbenchSection.calendar,
      'settings' => WorkbenchSection.settings,
      _ => WorkbenchSection.home,
    };
    return EntryShellPage(initialSection: section);
  }
}
