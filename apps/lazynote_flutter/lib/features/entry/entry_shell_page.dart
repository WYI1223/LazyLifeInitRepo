import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/routes.dart';

/// Default shell page used to validate new features before wiring final UIs.
class EntryShellPage extends StatefulWidget {
  const EntryShellPage({super.key});

  @override
  State<EntryShellPage> createState() => _EntryShellPageState();
}

class _EntryShellPageState extends State<EntryShellPage> {
  final TextEditingController _inputController = TextEditingController();
  String _status = 'Idle. Use the field below to validate UI behavior first.';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _runWorkbenchValidation() {
    final content = _inputController.text.trim();
    setState(() {
      _status = content.isEmpty
          ? 'No draft entered yet. Add text and validate again.'
          : 'Validated draft input: "$content"';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LazyNote Workbench')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feature Validation Window',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use this workbench as the default homepage while features '
                    'are being built and verified.',
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
                  Text(
                    'Diagnostics',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.rustDiagnostics),
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
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.notes),
                        child: const Text('Notes (Placeholder)'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.tasks),
                        child: const Text('Tasks (Placeholder)'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.settings),
                        child: const Text('Settings (Placeholder)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Generic placeholder page for routes that are intentionally deferred.
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_outlined, size: 42),
                const SizedBox(height: 12),
                Text(
                  '$title is under construction',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Workbench'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
