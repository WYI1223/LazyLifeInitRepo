/// Named routes for the Flutter shell.
abstract final class AppRoutes {
  /// Workbench default landing page.
  static const workbench = '/';

  /// Alias route for the same workbench page.
  static const entry = '/entry';

  /// Placeholder notes section (left pane).
  static const notes = '/notes';

  /// Placeholder tasks section (left pane).
  static const tasks = '/tasks';

  /// Placeholder settings section (left pane).
  static const settings = '/settings';

  /// Rust diagnostics section route.
  static const rustDiagnostics = '/diag/rust';
}
