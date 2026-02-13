import 'package:flutter/material.dart';
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

  testWidgets('single entry panel can open and close inside workbench', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();

    expect(find.byKey(const Key('single_entry_input')), findsNothing);

    await tapWorkbenchButton(tester, 'Open Single Entry');
    expect(find.byKey(const Key('single_entry_input')), findsOneWidget);

    await tapWorkbenchButton(tester, 'Hide Single Entry');
    expect(find.byKey(const Key('single_entry_input')), findsNothing);
  });

  testWidgets('send icon color changes with input emptiness', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();

    await tapWorkbenchButton(tester, 'Open Single Entry');

    Icon sendIcon() {
      return tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('single_entry_send_button')),
          matching: find.byType(Icon),
        ),
      );
    }

    expect(sendIcon().color, Colors.grey.shade600);

    await tester.enterText(
      find.byKey(const Key('single_entry_input')),
      '> task search notes',
    );
    await tester.pump();
    expect(sendIcon().color, Colors.blue);
  });

  testWidgets('onChanged command preview and Enter detail are split', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();

    await tapWorkbenchButton(tester, 'Open Single Entry');

    await tester.enterText(
      find.byKey(const Key('single_entry_input')),
      '> task project update',
    );
    await tester.pump();

    expect(
      find.text('Command preview ready. Press Enter or Send for details.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('single_entry_detail')), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(find.byKey(const Key('single_entry_detail')), findsOneWidget);
    expect(find.text('Detail opened.'), findsOneWidget);
  });

  testWidgets('parse error keeps input text unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();

    await tapWorkbenchButton(tester, 'Open Single Entry');

    const badInput = '> schedule tomorrow standup';
    await tester.enterText(
      find.byKey(const Key('single_entry_input')),
      badInput,
    );
    await tester.pump();

    expect(
      find.textContaining(
        'Schedule format must be MM/DD/YYYY HH:mm <title> or MM/DD/YYYY HH:mm-HH:mm <title>.',
      ),
      findsOneWidget,
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('single_entry_input')),
    );
    expect(field.controller?.text, badInput);
  });

  testWidgets('opening single entry does not remove debug logs panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();

    await tapWorkbenchButton(tester, 'Open Single Entry');

    expect(find.text('Debug Logs (Live)'), findsOneWidget);
    expect(find.byType(DebugLogsPanel), findsOneWidget);
  });
}
