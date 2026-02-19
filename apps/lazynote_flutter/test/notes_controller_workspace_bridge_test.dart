import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/workspace/workspace_models.dart';

rust_api.NoteItem _note({
  required String atomId,
  required String content,
  required int updatedAt,
}) {
  return rust_api.NoteItem(
    atomId: atomId,
    content: content,
    previewText: content,
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
    autosaveDebounce: const Duration(seconds: 30),
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
          final updated = _note(
            atomId: atomId,
            content: content,
            updatedAt: current.updatedAt + 1,
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

List<String> _workspaceTabs(NotesController controller) {
  return controller.workspaceProvider.openTabsByPane[controller
          .workspaceProvider
          .activePaneId] ??
      const <String>[];
}

void main() {
  test('M2 bridge keeps workspace tabs and active note aligned', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final controller = _buildController(store: store);
    addTearDown(controller.dispose);

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');

    expect(_workspaceTabs(controller), ['note-1', 'note-2']);
    expect(controller.workspaceProvider.activeNoteId, 'note-2');
  });

  test(
    'M2 bridge syncs active draft and save lifecycle to workspace',
    () async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      };
      final controller = _buildController(store: store);
      addTearDown(controller.dispose);

      await controller.loadNotes();
      controller.updateActiveDraft('# first updated');

      expect(
        controller.workspaceProvider.activeDraftContent,
        '# first updated',
      );
      expect(
        controller.workspaceProvider.saveStateByNoteId['note-1'],
        WorkspaceSaveState.dirty,
      );

      final flushed = await controller.flushPendingSave();
      expect(flushed, isTrue);
      expect(
        controller.workspaceProvider.saveStateByNoteId['note-1'],
        WorkspaceSaveState.clean,
      );
    },
  );

  test(
    'M2 bridge removes workspace tab snapshot when note tab closes',
    () async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
        'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
      };
      final controller = _buildController(store: store);
      addTearDown(controller.dispose);

      await controller.loadNotes();
      await controller.openNoteFromExplorer('note-2');
      expect(_workspaceTabs(controller), ['note-1', 'note-2']);

      final closed = await controller.closeOpenNote('note-2');
      expect(closed, isTrue);
      expect(_workspaceTabs(controller), ['note-1']);
      expect(controller.workspaceProvider.activeNoteId, 'note-1');
    },
  );
}
