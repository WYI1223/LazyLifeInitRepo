import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  }) {
    return rust_api.NoteItem(
      atomId: atomId,
      content: content,
      previewText: null,
      previewImage: null,
      updatedAt: updatedAt,
      tags: const [],
    );
  }

  testWidgets('C3.1 typing transitions dirty -> saving -> saved', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# Seed', updatedAt: 1000),
    };
    final saveCompleter = Completer<rust_api.NoteResponse>();
    final saveCalls = <String>[];

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(milliseconds: 50),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) {
        saveCalls.add(content);
        return saveCompleter.future;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# Next',
    );
    await tester.pump();
    expect(find.byKey(const Key('notes_save_status_dirty')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(const Key('notes_save_status_saving')), findsOneWidget);
    expect(saveCalls, ['# Next']);

    final saved = note(atomId: 'note-1', content: '# Next', updatedAt: 1200);
    store['note-1'] = saved;
    saveCompleter.complete(
      rust_api.NoteResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        note: saved,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('notes_save_status_saved')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('C3.1 autosave failure shows error status', (
    WidgetTester tester,
  ) async {
    final base = note(atomId: 'note-1', content: '# Seed', updatedAt: 1000);
    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(milliseconds: 30),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [base],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: base,
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        return const rust_api.NoteResponse(
          ok: false,
          errorCode: 'db_error',
          message: 'disk full',
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

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# fail',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();

    expect(find.byKey(const Key('notes_save_status_error')), findsOneWidget);
  });

  testWidgets('top action area collapses into overflow on narrow width', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(760, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final base = note(atomId: 'note-1', content: '# Seed', updatedAt: 1000);
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [base],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: base,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('notes_detail_overflow_menu_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_detail_share_button')), findsNothing);
    expect(find.byKey(const Key('notes_detail_star_button')), findsNothing);
    expect(
      find.byKey(const Key('notes_detail_more_menu_button')),
      findsNothing,
    );
  });

  testWidgets('top action area keeps direct buttons on wide width', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1800, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final base = note(atomId: 'note-1', content: '# Seed', updatedAt: 1000);
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [base],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: base,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('notes_detail_overflow_menu_button')),
      findsNothing,
    );
    expect(find.byKey(const Key('notes_detail_share_button')), findsOneWidget);
    expect(find.byKey(const Key('notes_detail_star_button')), findsOneWidget);
    expect(
      find.byKey(const Key('notes_detail_more_menu_button')),
      findsOneWidget,
    );
  });

  testWidgets('C3.2 blocks note switch when flush fails', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# One', updatedAt: 2000),
      'note-2': note(atomId: 'note-2', content: '# Two', updatedAt: 1000),
    };

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(seconds: 10),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!, store['note-2']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        return const rust_api.NoteResponse(
          ok: false,
          errorCode: 'db_error',
          message: 'write failed',
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

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# One*',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_list_item_note-2')));
    await tester.pump();
    await tester.pump();

    expect(controller.activeNoteId, 'note-1');
    expect(
      find.byKey(const Key('notes_switch_block_error_banner')),
      findsOneWidget,
    );
  });

  testWidgets('C3.2 blocks closing active tab when flush fails', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# One', updatedAt: 2000),
    };

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(seconds: 10),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        return const rust_api.NoteResponse(
          ok: false,
          errorCode: 'db_error',
          message: 'write failed',
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

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# One*',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('note_tab_close_note-1')));
    await tester.pump();
    await tester.pump();

    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');
    expect(
      find.byKey(const Key('notes_switch_block_error_banner')),
      findsOneWidget,
    );
  });

  testWidgets('C3.2 flush success allows note switch', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# One', updatedAt: 2000),
      'note-2': note(atomId: 'note-2', content: '# Two', updatedAt: 1000),
    };

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(seconds: 10),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!, store['note-2']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        final updated = note(
          atomId: atomId,
          content: content,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# One*',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_list_item_note-2')));
    await tester.pump();
    await tester.pump();

    expect(controller.activeNoteId, 'note-2');
    expect(
      find.byKey(const Key('notes_switch_block_error_banner')),
      findsNothing,
    );
  });

  testWidgets('C3.3 retry saves current latest draft', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# Seed', updatedAt: 1000),
    };
    final updateCalls = <String>[];
    var callCount = 0;

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(milliseconds: 30),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        callCount += 1;
        updateCalls.add(content);
        if (callCount == 1) {
          return const rust_api.NoteResponse(
            ok: false,
            errorCode: 'db_error',
            message: 'disk full',
            note: null,
          );
        }
        final updated = note(
          atomId: atomId,
          content: content,
          updatedAt: 1100 + callCount,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# fail',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(find.byKey(const Key('notes_save_status_error')), findsOneWidget);
    expect(find.byKey(const Key('notes_save_retry_button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# latest draft',
    );
    await tester.pump();
    expect(find.byKey(const Key('notes_save_status_dirty')), findsOneWidget);

    await controller.retrySaveCurrentDraft();
    await tester.pump();
    await tester.pump();

    expect(updateCalls.last, '# latest draft');
    expect(find.byKey(const Key('notes_save_status_saved')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('C3.3 stale save completion cannot overwrite newer draft', (
    WidgetTester tester,
  ) async {
    final save1 = Completer<rust_api.NoteResponse>();
    final save2 = Completer<rust_api.NoteResponse>();
    var callCount = 0;
    final updateCalls = <String>[];
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# base', updatedAt: 1000),
    };

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(milliseconds: 20),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) {
        callCount += 1;
        updateCalls.add(content);
        if (callCount == 1) {
          return save1.future;
        }
        return save2.future;
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byKey(const Key('note_editor_field')), '# one');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(const Key('notes_save_status_saving')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note_editor_field')), '# two');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(updateCalls.first, '# one');

    save1.complete(
      rust_api.NoteResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        note: note(atomId: 'note-1', content: '# one', updatedAt: 2000),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(updateCalls.length, 2);
    expect(updateCalls.last, '# two');
    expect(find.byKey(const Key('notes_save_status_saving')), findsOneWidget);

    save2.complete(
      rust_api.NoteResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        note: note(atomId: 'note-1', content: '# two', updatedAt: 3000),
      ),
    );
    await tester.pump();

    expect(controller.activeDraftContent, '# two');
    expect(find.byKey(const Key('notes_save_status_saved')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('C3.3 app paused triggers best-effort flush', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# Seed', updatedAt: 1000),
    };
    final updateCalls = <String>[];

    final controller = NotesController(
      prepare: () async {},
      autosaveDebounce: const Duration(seconds: 5),
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: [store['note-1']!],
        );
      },
      noteGetInvoker: ({required atomId}) async {
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: store[atomId],
        );
      },
      noteUpdateInvoker: ({required atomId, required content}) async {
        updateCalls.add(content);
        final updated = note(atomId: atomId, content: content, updatedAt: 2000);
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('note_editor_field')),
      '# paused',
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    expect(updateCalls, ['# paused']);
    await tester.pump(const Duration(seconds: 3));
  });
}
