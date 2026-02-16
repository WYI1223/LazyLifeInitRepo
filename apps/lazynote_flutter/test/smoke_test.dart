import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/app.dart';
import 'package:lazynote_flutter/features/diagnostics/debug_logs_panel.dart';

void main() {
  setUp(() {
    DebugLogsPanel.autoRefreshEnabled = false;
  });

  tearDown(() {
    DebugLogsPanel.autoRefreshEnabled = true;
  });

  Future<void> tapWorkbenchButton(
    WidgetTester tester,
    String buttonText,
  ) async {
    final buttonFinder = find.text(buttonText);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('workbench home shows single-entry-focused controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Workbench Home'), findsOneWidget);
    expect(find.text('Single Entry'), findsWidgets);
    expect(find.text('Open Single Entry'), findsOneWidget);
  });

  testWidgets('notes route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Notes');

    expect(find.byKey(const Key('notes_page_root')), findsOneWidget);
    expect(find.text('Notes'), findsWidgets);
  });

  testWidgets('notes page back button returns to workbench home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Notes');
    final backButton = find.byKey(const Key('notes_back_to_workbench_button'));
    await tester.ensureVisible(backButton);
    await tester.tap(backButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Workbench Home'), findsOneWidget);
    expect(find.byKey(const Key('notes_page_root')), findsNothing);
  });

  testWidgets('tasks route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Tasks');

    expect(find.byKey(const Key('tasks_page_root')), findsOneWidget);
    expect(find.text('Tasks'), findsWidgets);
  });

  testWidgets('calendar route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Calendar');

    expect(find.byKey(const Key('calendar_page_root')), findsOneWidget);
    expect(find.text('Calendar'), findsWidgets);
  });

  testWidgets('settings placeholder route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Settings (Placeholder)');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Settings is under construction'), findsOneWidget);
    expect(find.text('Back to Workbench'), findsOneWidget);
  });

  testWidgets('rust diagnostics route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Rust Diagnostics');

    expect(find.text('Rust Diagnostics'), findsWidgets);
  });

  testWidgets('workbench shows inline debug logs panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Debug Logs (Live)'), findsOneWidget);
    expect(find.text('Copy Visible Logs'), findsOneWidget);
    expect(find.text('Open Log Folder'), findsOneWidget);
  });

  testWidgets('single entry launcher is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tapWorkbenchButton(tester, 'Open Single Entry');

    expect(find.byKey(const Key('single_entry_input')), findsOneWidget);
    expect(find.byKey(const Key('single_entry_send_button')), findsOneWidget);
  });
}
