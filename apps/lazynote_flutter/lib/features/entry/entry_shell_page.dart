import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/diagnostics/rust_diagnostics_page.dart';
import 'package:lazynote_flutter/features/entry/workbench_shell_layout.dart';

/// Left-pane sections inside Workbench shell.
enum WorkbenchSection { home, notes, tasks, settings, rustDiagnostics }

/// Default shell page used to validate new features before wiring final UIs.
///
/// Left-pane routing is handled in-place via state so the right logs panel
/// remains mounted and stable across section switches.
class EntryShellPage extends StatefulWidget {
  const EntryShellPage({
    super.key,
    this.initialSection = WorkbenchSection.home,
  });

  final WorkbenchSection initialSection;

  @override
  State<EntryShellPage> createState() => _EntryShellPageState();
}

class _EntryShellPageState extends State<EntryShellPage> {
  final TextEditingController _inputController = TextEditingController();
  String _status = 'Idle. Use the field below to validate UI behavior first.';
  late WorkbenchSection _activeSection;

  @override
  void initState() {
    super.initState();
    _activeSection = widget.initialSection;
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _openSection(WorkbenchSection section) {
    setState(() {
      _activeSection = section;
    });
  }

  void _runWorkbenchValidation() {
    final content = _inputController.text.trim();
    setState(() {
      _status = content.isEmpty
          ? 'No draft entered yet. Add text and validate again.'
          : 'Validated draft input: "$content"';
    });
  }

  String _titleForSection(WorkbenchSection section) {
    return switch (section) {
      WorkbenchSection.home => 'LazyNote Workbench',
      WorkbenchSection.notes => 'Notes',
      WorkbenchSection.tasks => 'Tasks',
      WorkbenchSection.settings => 'Settings',
      WorkbenchSection.rustDiagnostics => 'Rust Diagnostics',
    };
  }

  Widget _buildWorkbenchHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Feature Validation Window',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Use this workbench as the default homepage while features are '
          'being built and verified.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('workbench_input'),
          controller: _inputController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Draft Input',
            hintText: 'Type an idea or flow to validate here...',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _runWorkbenchValidation,
          child: const Text('Validate in Workbench'),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_status, key: const Key('workbench_status')),
          ),
        ),
        const SizedBox(height: 24),
        Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _openSection(WorkbenchSection.rustDiagnostics),
          child: const Text('Rust Diagnostics'),
        ),
        const SizedBox(height: 24),
        Text(
          'Placeholder Routes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: () => _openSection(WorkbenchSection.notes),
              child: const Text('Notes (Placeholder)'),
            ),
            OutlinedButton(
              onPressed: () => _openSection(WorkbenchSection.tasks),
              child: const Text('Tasks (Placeholder)'),
            ),
            OutlinedButton(
              onPressed: () => _openSection(WorkbenchSection.settings),
              child: const Text('Settings (Placeholder)'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholder({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Icon(Icons.construction_outlined, size: 42),
        const SizedBox(height: 12),
        Text(
          '$title is under construction',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 8),
        Text(description),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _openSection(WorkbenchSection.home),
          child: const Text('Back to Workbench'),
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
    return switch (_activeSection) {
      WorkbenchSection.home => _buildWorkbenchHome(),
      WorkbenchSection.notes => _buildPlaceholder(
        title: 'Notes',
        description: 'Notes UI will be implemented in a dedicated PR.',
      ),
      WorkbenchSection.tasks => _buildPlaceholder(
        title: 'Tasks',
        description: 'Tasks UI will be implemented in a dedicated PR.',
      ),
      WorkbenchSection.settings => _buildPlaceholder(
        title: 'Settings',
        description: 'Settings UI will be implemented in a dedicated PR.',
      ),
      WorkbenchSection.rustDiagnostics => _buildRustDiagnosticsSection(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return WorkbenchShellLayout(
      title: _titleForSection(_activeSection),
      content: _buildActiveLeftContent(),
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

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final section = switch (title.toLowerCase()) {
      'notes' => WorkbenchSection.notes,
      'tasks' => WorkbenchSection.tasks,
      'settings' => WorkbenchSection.settings,
      _ => WorkbenchSection.home,
    };
    return EntryShellPage(initialSection: section);
  }
}
