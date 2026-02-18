import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_page.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  rust_api.NoteItem note({
    required String atomId,
    required String content,
    required int updatedAt,
    String? previewText,
  }) {
    return rust_api.NoteItem(
      atomId: atomId,
      content: content,
      previewText: previewText,
      previewImage: null,
      updatedAt: updatedAt,
      tags: const [],
    );
  }

  testWidgets(
    'C1 renders loading then success list and auto-selects first note',
    (WidgetTester tester) async {
      final listCompleter = Completer<rust_api.NotesListResponse>();
      final detailCalls = <String>[];

      final controller = NotesController(
        prepare: () async {},
        notesListInvoker: ({tag, limit, offset}) => listCompleter.future,
        noteGetInvoker: ({required atomId}) async {
          detailCalls.add(atomId);
          return rust_api.NoteResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            note: note(
              atomId: atomId,
              content: '# $atomId',
              previewText: 'detail $atomId',
              updatedAt: 1000,
            ),
          );
        },
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrapWithMaterial(NotesPage(controller: controller)),
      );
      await tester.pump();
      expect(find.byKey(const Key('notes_list_loading')), findsOneWidget);

      listCompleter.complete(
        rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [
            note(
              atomId: 'note-1',
              content: '# First Note',
              previewText: 'first preview',
              updatedAt: 2000,
            ),
            note(
              atomId: 'note-2',
              content: '# Second Note',
              previewText: 'second preview',
              updatedAt: 1000,
            ),
          ],
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('notes_list_view')), findsOneWidget);
      expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
      expect(find.byKey(const Key('notes_list_item_note-2')), findsOneWidget);
      expect(controller.selectedAtomId, 'note-1');
      expect(detailCalls, ['note-1']);
    },
  );

  testWidgets('C1 renders empty state when notes list is empty', (
    WidgetTester tester,
  ) async {
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        return const rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          items: [],
          appliedLimit: 50,
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return const rust_api.NoteResponse(
          ok: false,
          errorCode: 'not_found',
          message: 'not found',
          note: null,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_list_empty')), findsOneWidget);
  });

  testWidgets('C1 renders error and retry path can recover', (
    WidgetTester tester,
  ) async {
    var listCallCount = 0;
    final detailCalls = <String>[];
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        listCallCount += 1;
        if (listCallCount == 1) {
          return const rust_api.NotesListResponse(
            ok: false,
            errorCode: 'db_error',
            message: 'load failed',
            items: [],
            appliedLimit: 50,
          );
        }
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [
            note(
              atomId: 'note-retry',
              content: '# Retry Note',
              previewText: 'ready',
              updatedAt: 3000,
            ),
          ],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        detailCalls.add(atomId);
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: note(
            atomId: atomId,
            content: '# Retry Note',
            previewText: 'ready',
            updatedAt: 3000,
          ),
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_list_error')), findsOneWidget);
    expect(find.byKey(const Key('notes_retry_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_retry_button')));
    await tester.pump();
    await tester.pump();

    expect(listCallCount, 2);
    expect(find.byKey(const Key('notes_list_view')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-retry')), findsOneWidget);
    expect(detailCalls, ['note-retry']);
  });

  testWidgets('Notes side_panel renders all slot contributions', (
    WidgetTester tester,
  ) async {
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        return const rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return const rust_api.NoteResponse(
          ok: false,
          errorCode: 'not_found',
          message: 'not found',
          note: null,
        );
      },
    );
    addTearDown(controller.dispose);

    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.notes.side_panel.one',
          slotId: UiSlotIds.notesSidePanel,
          layer: UiSlotLayer.sidePanel,
          priority: 10,
          builder: (context, slotContext) => const Text('side-panel-one'),
        ),
        UiSlotContribution(
          contributionId: 'test.notes.side_panel.two',
          slotId: UiSlotIds.notesSidePanel,
          layer: UiSlotLayer.sidePanel,
          priority: 5,
          builder: (context, slotContext) => const Text('side-panel-two'),
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithMaterial(
        NotesPage(controller: controller, uiSlotRegistry: registry),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('side-panel-one'), findsOneWidget);
    expect(find.text('side-panel-two'), findsOneWidget);
  });
}
