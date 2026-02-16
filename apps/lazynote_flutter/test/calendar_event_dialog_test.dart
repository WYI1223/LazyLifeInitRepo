import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/calendar/calendar_event_dialog.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  Future<void> openDialog(
    WidgetTester tester, {
    rust_api.AtomListItem? existingItem,
    DateTime? initialDate,
    int initialHour = 9,
  }) async {
    await tester.pumpWidget(wrapWithMaterial(
      Builder(
        builder: (context) => FilledButton(
          key: const Key('open_dialog'),
          onPressed: () {
            showDialog<CalendarEventResult>(
              context: context,
              builder: (_) => CalendarEventDialog(
                existingItem: existingItem,
                initialDate: initialDate ?? DateTime(2026, 2, 16),
                initialHour: initialHour,
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();
  }

  testWidgets('create dialog shows empty title field', (
    WidgetTester tester,
  ) async {
    await openDialog(tester);

    expect(find.byKey(const Key('calendar_event_dialog')), findsOneWidget);
    expect(find.text('New Event'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    // Title field should be empty
    final titleField = tester.widget<TextField>(
      find.byKey(const Key('calendar_event_title_field')),
    );
    expect(titleField.controller!.text, isEmpty);
  });

  testWidgets('edit dialog pre-fills from existing event', (
    WidgetTester tester,
  ) async {
    final existing = rust_api.AtomListItem(
      atomId: 'evt-edit-1',
      kind: 'event',
      content: 'Team standup\nWith agenda notes',
      previewText: 'Team standup',
      tags: const [],
      startAt: DateTime(2026, 2, 16, 10, 0).millisecondsSinceEpoch,
      endAt: DateTime(2026, 2, 16, 11, 0).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 2, 16, 10, 0).millisecondsSinceEpoch,
    );

    await openDialog(tester, existingItem: existing);

    expect(find.text('Edit Event'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    // Title should be pre-filled with previewText
    final titleField = tester.widget<TextField>(
      find.byKey(const Key('calendar_event_title_field')),
    );
    expect(titleField.controller!.text, 'Team standup');
  });

  testWidgets('submit with empty title shows validation error', (
    WidgetTester tester,
  ) async {
    await openDialog(tester);

    // Tap submit without entering a title
    await tester.tap(find.byKey(const Key('calendar_event_submit_button')));
    await tester.pump();

    expect(
      find.byKey(const Key('calendar_event_validation_error')),
      findsOneWidget,
    );
    expect(find.text('Title cannot be empty'), findsOneWidget);
  });

  testWidgets('cancel returns null and closes dialog', (
    WidgetTester tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('calendar_event_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('calendar_event_dialog')), findsNothing);
  });

  testWidgets('submit with valid title closes dialog', (
    WidgetTester tester,
  ) async {
    await openDialog(tester, initialHour: 14);

    // Enter a title
    await tester.enterText(
      find.byKey(const Key('calendar_event_title_field')),
      'Design review',
    );
    await tester.pump();

    // Submit
    await tester.tap(find.byKey(const Key('calendar_event_submit_button')));
    await tester.pumpAndSettle();

    // Dialog should close
    expect(find.byKey(const Key('calendar_event_dialog')), findsNothing);
  });

  testWidgets('date and time pickers are present', (
    WidgetTester tester,
  ) async {
    await openDialog(tester, initialHour: 9);

    expect(
      find.byKey(const Key('calendar_event_date_picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar_event_start_time_picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar_event_end_time_picker')),
      findsOneWidget,
    );

    // Check displayed time values
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
  });
}
