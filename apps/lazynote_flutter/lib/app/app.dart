import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/routes.dart';
import 'package:lazynote_flutter/features/diagnostics/rust_diagnostics_page.dart';
import 'package:lazynote_flutter/features/entry/entry_shell_page.dart';

/// Root app shell for the Windows-first UI stage.
class LazyNoteApp extends StatelessWidget {
  const LazyNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LazyNote',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      initialRoute: AppRoutes.workbench,
      routes: {
        AppRoutes.workbench: (_) => const EntryShellPage(),
        AppRoutes.entry: (_) => const EntryShellPage(),
        AppRoutes.notes: (_) => const FeaturePlaceholderPage(
          title: 'Notes',
          description: 'Notes UI will be implemented in a dedicated PR.',
        ),
        AppRoutes.tasks: (_) => const FeaturePlaceholderPage(
          title: 'Tasks',
          description: 'Tasks UI will be implemented in a dedicated PR.',
        ),
        AppRoutes.settings: (_) => const FeaturePlaceholderPage(
          title: 'Settings',
          description: 'Settings UI will be implemented in a dedicated PR.',
        ),
        AppRoutes.rustDiagnostics: (_) => const RustDiagnosticsPage(),
      },
    );
  }
}
