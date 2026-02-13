import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';
import 'package:lazynote_flutter/features/entry/single_entry_panel.dart';

void main() {
  testWidgets('search input updates realtime results section', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit}) async {
        return EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-$text',
              kind: 'note',
              snippet: 'snippet for $text',
            ),
          ],
          message: 'Found 1 result(s).',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SingleEntryPanel(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('single_entry_input')),
      'alpha',
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('single_entry_search_results')),
      findsOneWidget,
    );
    expect(find.textContaining('snippet for alpha'), findsOneWidget);
  });

  testWidgets('Enter opens detail without removing realtime results', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit}) async {
        return EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: const [
            EntrySearchItem(
              atomId: 'atom-1',
              kind: 'note',
              snippet: 'first result',
            ),
          ],
          message: 'Found 1 result(s).',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SingleEntryPanel(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('single_entry_input')), 'beta');
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('single_entry_search_results')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('single_entry_detail')), findsNothing);

    await tester.tap(find.byKey(const Key('single_entry_send_button')));
    await tester.pump();

    expect(find.byKey(const Key('single_entry_detail')), findsOneWidget);
    expect(
      find.byKey(const Key('single_entry_search_results')),
      findsOneWidget,
    );
  });
}
