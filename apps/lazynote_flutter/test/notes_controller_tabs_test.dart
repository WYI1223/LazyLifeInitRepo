import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_controller.dart';

rust_api.NoteItem _note({
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

NotesController _buildController({
  required Map<String, rust_api.NoteItem> store,
  Future<rust_api.NoteResponse> Function({
    required String atomId,
    required String content,
  })?
  noteUpdateInvoker,
}) {
  return NotesController(
    prepare: () async {},
    autosaveDebounce: const Duration(seconds: 10),
    notesListInvoker: ({tag, limit, offset}) async {
      final items = <rust_api.NoteItem>[];
      for (final id in const ['note-1', 'note-2']) {
        if (store[id] case final item?) {
          items.add(item);
        }
      }
      return rust_api.NotesListResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        appliedLimit: 50,
        items: items,
      );
    },
    noteGetInvoker: ({required atomId}) async {
      final found = store[atomId];
      return rust_api.NoteResponse(
        ok: found != null,
        errorCode: found == null ? 'note_not_found' : null,
        message: found == null ? 'missing' : 'ok',
        note: found,
      );
    },
    noteUpdateInvoker:
        noteUpdateInvoker ??
        ({required atomId, required content}) async {
          final current = store[atomId];
          if (current == null) {
            return const rust_api.NoteResponse(
              ok: false,
              errorCode: 'note_not_found',
              message: 'missing',
              note: null,
            );
          }
          final updated = rust_api.NoteItem(
            atomId: atomId,
            content: content,
            previewText: current.previewText,
            previewImage: current.previewImage,
            updatedAt: current.updatedAt + 1,
            tags: current.tags,
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
}

void main() {
  test('load initializes first tab as active', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(
        atomId: 'note-1',
        content: '# first',
        previewText: 'first',
        updatedAt: 2,
      ),
      'note-2': _note(
        atomId: 'note-2',
        content: '# second',
        previewText: 'second',
        updatedAt: 1,
      ),
    };
    final controller = _buildController(store: store);
    addTearDown(controller.dispose);

    await controller.loadNotes();

    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');
  });

  test('open from explorer appends tab and activates target', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final controller = _buildController(store: store);
    addTearDown(controller.dispose);

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');

    expect(controller.openNoteIds, ['note-1', 'note-2']);
    expect(controller.activeNoteId, 'note-2');
  });

  test('tab close helpers keep deterministic active tab', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final controller = _buildController(store: store);
    addTearDown(controller.dispose);

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    await controller.activatePreviousOpenNote();
    expect(controller.activeNoteId, 'note-1');

    final closedRight = await controller.closeOpenNotesToRight('note-1');
    expect(closedRight, isTrue);
    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');

    final closedLast = await controller.closeOpenNote('note-1');
    expect(closedLast, isTrue);
    expect(controller.openNoteIds, isEmpty);
    expect(controller.activeNoteId, isNull);
  });

  test('closing active last tab flushes dirty draft before clearing', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
    };
    final updateCalls = <String>[];
    final controller = _buildController(
      store: store,
      noteUpdateInvoker: ({required atomId, required content}) async {
        updateCalls.add(content);
        final updated = _note(atomId: atomId, content: content, updatedAt: 3);
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

    await controller.loadNotes();
    controller.updateActiveDraft('# changed');

    final closed = await controller.closeOpenNote('note-1');

    expect(closed, isTrue);
    expect(updateCalls, ['# changed']);
    expect(controller.openNoteIds, isEmpty);
    expect(controller.activeNoteId, isNull);
  });

  test('closing active last tab is blocked when flush fails', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
    };
    final controller = _buildController(
      store: store,
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

    await controller.loadNotes();
    controller.updateActiveDraft('# changed');

    final closed = await controller.closeOpenNote('note-1');

    expect(closed, isFalse);
    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');
  });

  test('close others flushes when switching away from dirty active', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final updateCalls = <String>[];
    final controller = _buildController(
      store: store,
      noteUpdateInvoker: ({required atomId, required content}) async {
        updateCalls.add(content);
        final updated = _note(atomId: atomId, content: content, updatedAt: 5);
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

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    controller.updateActiveDraft('# second updated');

    final closed = await controller.closeOtherOpenNotes('note-1');

    expect(closed, isTrue);
    expect(updateCalls, ['# second updated']);
    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');
  });

  test('close right flushes when active tab would be pruned', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final updateCalls = <String>[];
    final controller = _buildController(
      store: store,
      noteUpdateInvoker: ({required atomId, required content}) async {
        updateCalls.add(content);
        final updated = _note(atomId: atomId, content: content, updatedAt: 6);
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

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    controller.updateActiveDraft('# second updated');

    final closed = await controller.closeOpenNotesToRight('note-1');

    expect(closed, isTrue);
    expect(updateCalls, ['# second updated']);
    expect(controller.openNoteIds, ['note-1']);
    expect(controller.activeNoteId, 'note-1');
  });

  test('close right is blocked when flush for pruned active fails', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final controller = _buildController(
      store: store,
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

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    controller.updateActiveDraft('# second updated');

    final closed = await controller.closeOpenNotesToRight('note-1');

    expect(closed, isFalse);
    expect(controller.openNoteIds, ['note-1', 'note-2']);
    expect(controller.activeNoteId, 'note-2');
  });
}
