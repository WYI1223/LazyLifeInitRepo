import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/app.dart';

void main() {
  Future<void> tapWorkbenchButton(
    WidgetTester tester,
    String buttonText,
  ) async {
    final buttonFinder = find.text(buttonText);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
  }

  testWidgets('workbench can validate draft input', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('workbench_input')),
      'search notes next',
    );
    await tapWorkbenchButton(tester, 'Validate in Workbench');

    expect(
      find.textContaining('Validated draft input: "search notes next"'),
      findsOneWidget,
    );
  });

  testWidgets('notes placeholder route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    await tapWorkbenchButton(tester, 'Notes (Placeholder)');

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Notes is under construction'), findsOneWidget);
    expect(find.text('Back to Workbench'), findsOneWidget);
  });

  testWidgets('tasks placeholder route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    await tapWorkbenchButton(tester, 'Tasks (Placeholder)');

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Tasks is under construction'), findsOneWidget);
    expect(find.text('Back to Workbench'), findsOneWidget);
  });

  testWidgets('settings placeholder route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    await tapWorkbenchButton(tester, 'Settings (Placeholder)');

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Settings is under construction'), findsOneWidget);
    expect(find.text('Back to Workbench'), findsOneWidget);
  });

  testWidgets('rust diagnostics route is reachable from workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    await tapWorkbenchButton(tester, 'Rust Diagnostics');

    expect(find.text('Rust Diagnostics'), findsOneWidget);
  });
}
