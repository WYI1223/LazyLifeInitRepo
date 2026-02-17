import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/note_explorer.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';

rust_api.NoteItem _note({
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

void main() {
  testWidgets('folder delete dialog submits selected delete_all mode', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 1),
    };
    final calls = <String>[];
    final controller = NotesController(
      prepare: () async {},
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: store.values.toList(),
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
    );
    addTearDown(controller.dispose);

    await controller.loadNotes();
    const folderId = '11111111-1111-4111-8111-111111111111';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return NoteExplorer(
                controller: controller,
                onOpenNoteRequested: (_) {},
                onCreateNoteRequested: () async {},
                onDeleteFolderRequested: (id, mode) async {
                  calls.add('$id::$mode');
                  return const rust_api.WorkspaceActionResponse(
                    ok: true,
                    errorCode: null,
                    message: 'ok',
                  );
                },
                folderTreeBuilder: (_) {
                  return const <ExplorerFolderNode>[
                    ExplorerFolderNode(
                      id: folderId,
                      label: 'Team',
                      deletable: true,
                    ),
                  ];
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key(
          'notes_folder_delete_button_11111111-1111-4111-8111-111111111111',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_folder_delete_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(calls, const ['11111111-1111-4111-8111-111111111111::delete_all']);
  });
}
