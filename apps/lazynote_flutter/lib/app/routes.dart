/// Named routes for the Flutter shell.
abstract final class AppRoutes {
  /// Workbench default landing page.
  static const workbench = '/';

  /// Alias route for the same workbench page.
  static const entry = '/entry';

  /// Notes section (left pane).
  static const notes = '/notes';

  /// Placeholder tasks section (left pane).
  static const tasks = '/tasks';

  /// Calendar section (left pane).
  static const calendar = '/calendar';

  /// Placeholder settings section (left pane).
  static const settings = '/settings';

  /// Rust diagnostics section route.
  static const rustDiagnostics = '/diag/rust';
}
