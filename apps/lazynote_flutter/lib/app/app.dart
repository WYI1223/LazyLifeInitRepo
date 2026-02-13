import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/routes.dart';
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
        AppRoutes.notes: (_) =>
            const EntryShellPage(initialSection: WorkbenchSection.notes),
        AppRoutes.tasks: (_) =>
            const EntryShellPage(initialSection: WorkbenchSection.tasks),
        AppRoutes.settings: (_) =>
            const EntryShellPage(initialSection: WorkbenchSection.settings),
        AppRoutes.rustDiagnostics: (_) => const EntryShellPage(
          initialSection: WorkbenchSection.rustDiagnostics,
        ),
      },
    );
  }
}
