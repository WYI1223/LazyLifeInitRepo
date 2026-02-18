import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';
import 'package:lazynote_flutter/features/entry/single_entry_panel.dart';

void main() {
  Future<void> pumpEntryRealtime(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }

  testWidgets('search input updates realtime results section', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
        final resolvedKind = kind ?? 'all';
        return EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-$resolvedKind',
              kind: resolvedKind == 'all' ? 'note' : resolvedKind,
              snippet: 'snippet for $text/$resolvedKind',
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
            child: SizedBox(
              height: 900,
              child: SingleEntryPanel(controller: controller, onClose: () {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('single_entry_input')),
      'alpha',
    );
    await pumpEntryRealtime(tester);

    expect(
      find.byKey(const Key('single_entry_search_results')),
      findsOneWidget,
    );
    expect(find.textContaining('snippet for alpha/all'), findsOneWidget);

    await tester.tap(find.byKey(const Key('single_entry_search_kind_task')));
    await pumpEntryRealtime(tester);

    expect(find.textContaining('snippet for alpha/task'), findsOneWidget);
  });

  testWidgets('Enter opens detail without removing realtime results', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
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
            child: SizedBox(
              height: 900,
              child: SingleEntryPanel(controller: controller, onClose: () {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('single_entry_input')), 'beta');
    await pumpEntryRealtime(tester);

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

  testWidgets('tapping a result item opens selected detail payload', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
        return const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-picked',
              kind: 'task',
              snippet: 'picked result snippet',
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
            child: SizedBox(
              height: 900,
              child: SingleEntryPanel(controller: controller, onClose: () {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('single_entry_input')), 'pick');
    await pumpEntryRealtime(tester);

    await tester.ensureVisible(
      find.byKey(const Key('single_entry_search_item_0')),
    );
    final row = tester.widget<ListTile>(
      find.byKey(const Key('single_entry_search_item_0')),
    );
    row.onTap!.call();
    await tester.pump();

    expect(find.byKey(const Key('single_entry_detail')), findsOneWidget);
    expect(find.textContaining('mode=search_item'), findsOneWidget);
    expect(find.textContaining('atom_id=atom-picked'), findsOneWidget);
  });

  testWidgets('Escape clears input and closes detail panel', (
    WidgetTester tester,
  ) async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
        return const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-esc-1',
              kind: 'note',
              snippet: 'escape result',
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
            child: SizedBox(
              height: 900,
              child: SingleEntryPanel(controller: controller, onClose: () {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('single_entry_input')), 'esc');
    await pumpEntryRealtime(tester);
    await tester.tap(find.byKey(const Key('single_entry_send_button')));
    await tester.pump();

    expect(find.byKey(const Key('single_entry_detail')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('single_entry_input')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.byKey(const Key('single_entry_detail')), findsNothing);
  });

  testWidgets(
    'send executes command intent and renders command result detail',
    (WidgetTester tester) async {
      var taskCalls = 0;
      String? createdTaskContent;

      final controller = SingleEntryController(
        prepareCommand: () async {},
        createTaskInvoker: ({required content}) async {
          taskCalls += 1;
          createdTaskContent = content;
          return const EntryActionResponse(
            ok: true,
            atomId: 'atom-task-widget',
            message: 'Task created.',
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

      const commandText = '> task run widget command test';
      await tester.enterText(
        find.byKey(const Key('single_entry_input')),
        commandText,
      );
      await tester.pump();
      expect(
        find.text('Command preview ready. Press Enter or Send for details.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('single_entry_send_button')));
      await tester.pump();
      await tester.pump();

      expect(taskCalls, 1);
      expect(createdTaskContent, 'run widget command test');
      expect(find.text('Task created.'), findsOneWidget);
      expect(find.byKey(const Key('single_entry_detail')), findsOneWidget);
      expect(find.textContaining('action=create_task'), findsOneWidget);
      expect(find.textContaining('atom_id=atom-task-widget'), findsOneWidget);
    },
  );

  testWidgets('send button is disabled while command is executing', (
    WidgetTester tester,
  ) async {
    final commandResponse = Completer<EntryActionResponse>();
    var taskCalls = 0;

    final controller = SingleEntryController(
      prepareCommand: () async {},
      createTaskInvoker: ({required content}) {
        taskCalls += 1;
        return commandResponse.future;
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
      '> task disable send while loading',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('single_entry_send_button')));
    await tester.pump();

    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('single_entry_send_button')),
    );
    expect(sendButton.onPressed, isNull);
    expect(taskCalls, 1);

    commandResponse.complete(
      const EntryActionResponse(
        ok: true,
        atomId: 'atom-finish-1',
        message: 'Task created.',
      ),
    );
    await tester.pump();
    await tester.pump();

    final sendButtonAfter = tester.widget<IconButton>(
      find.byKey(const Key('single_entry_send_button')),
    );
    expect(sendButtonAfter.onPressed, isNotNull);
  });
}
