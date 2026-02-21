import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
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

NotesController _buildController({
  required Map<String, rust_api.NoteItem> store,
  NoteCreateInvoker? noteCreateInvoker,
  WorkspaceCreateFolderInvoker? workspaceCreateFolderInvoker,
  WorkspaceCreateNoteRefInvoker? workspaceCreateNoteRefInvoker,
  WorkspaceRenameNodeInvoker? workspaceRenameNodeInvoker,
  WorkspaceMoveNodeInvoker? workspaceMoveNodeInvoker,
  WorkspaceListChildrenInvoker? workspaceListChildrenInvoker,
}) {
  return NotesController(
    prepare: () async {},
    notesListInvoker: ({tag, limit, offset}) async {
      return rust_api.NotesListResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        appliedLimit: 50,
        items: store.values.toList(growable: false),
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
    noteCreateInvoker: noteCreateInvoker,
    tagsListInvoker: () async {
      return const rust_api.TagsListResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
        tags: <String>[],
      );
    },
    workspaceCreateFolderInvoker: workspaceCreateFolderInvoker,
    workspaceCreateNoteRefInvoker: workspaceCreateNoteRefInvoker,
    workspaceRenameNodeInvoker: workspaceRenameNodeInvoker,
    workspaceMoveNodeInvoker: workspaceMoveNodeInvoker,
    workspaceListChildrenInvoker: workspaceListChildrenInvoker,
  );
}

void main() {
  test(
    'createWorkspaceFolder returns busy while previous create is in flight',
    () async {
      final completer = Completer<rust_api.WorkspaceNodeResponse>();
      var createCalls = 0;
      final controller = _buildController(
        store: <String, rust_api.NoteItem>{
          'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
        },
        workspaceCreateFolderInvoker: ({parentNodeId, required name}) {
          createCalls += 1;
          return completer.future;
        },
      );
      addTearDown(controller.dispose);

      final first = controller.createWorkspaceFolder(name: 'Inbox');
      final second = await controller.createWorkspaceFolder(name: 'Team');

      expect(second.ok, isFalse);
      expect(second.errorCode, 'busy');
      expect(createCalls, 1);

      completer.complete(
        const rust_api.WorkspaceNodeResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          node: null,
        ),
      );
      final firstResponse = await first;
      expect(firstResponse.ok, isTrue);
    },
  );

  test(
    'createWorkspaceFolder rejects non-UUID parent id before FFI call',
    () async {
      var createCalls = 0;
      final controller = _buildController(
        store: <String, rust_api.NoteItem>{
          'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
        },
        workspaceCreateFolderInvoker: ({parentNodeId, required name}) async {
          createCalls += 1;
          return const rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: null,
          );
        },
      );
      addTearDown(controller.dispose);

      final response = await controller.createWorkspaceFolder(
        name: 'Team',
        parentNodeId: 'not-a-uuid',
      );

      expect(response.ok, isFalse);
      expect(response.errorCode, 'invalid_parent_node_id');
      expect(createCalls, 0);
    },
  );

  test(
    'listWorkspaceChildren maps __uncategorized__ without forwarding synthetic id',
    () async {
      final requestedParentIds = <String?>[];
    final controller = _buildController(
      store: <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
      },
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        requestedParentIds.add(parentNodeId);
        return const rust_api.WorkspaceListChildrenResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          items: <rust_api.WorkspaceNodeItem>[],
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    final response = await controller.listWorkspaceChildren(
      parentNodeId: '__uncategorized__',
    );

    expect(response.ok, isTrue);
    expect(response.errorCode, isNull);
    expect(requestedParentIds, isNotEmpty);
    expect(requestedParentIds, isNot(contains('__uncategorized__')));
    expect(response.items, isNotEmpty);
    expect(response.items.first.parentNodeId, '__uncategorized__');
    },
  );

  test(
    'listWorkspaceChildren returns explicit error envelope on bridge exception',
    () async {
      final controller = _buildController(
        store: <String, rust_api.NoteItem>{
          'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
        },
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          throw StateError('bridge boom');
        },
      );
      addTearDown(controller.dispose);

      final response = await controller.listWorkspaceChildren(
        parentNodeId: null,
      );

      expect(response.ok, isFalse);
      expect(response.errorCode, 'internal_error');
      expect(response.message, contains('bridge boom'));
      expect(response.items, isEmpty);
    },
  );

  test(
    'createWorkspaceNoteInFolder maps __uncategorized__ parent to root',
    () async {
      String? linkedParentNodeId;
      final created = _note(
        atomId: '11111111-1111-4111-8111-111111111111',
        content: '# created',
        updatedAt: 2,
      );
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
      };
      final controller = _buildController(
        store: store,
        noteCreateInvoker: ({required content}) async {
          store[created.atomId] = created;
          return rust_api.NoteResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            note: created,
          );
        },
        workspaceCreateNoteRefInvoker:
            ({parentNodeId, required atomId, displayName}) async {
              linkedParentNodeId = parentNodeId;
              return const rust_api.WorkspaceNodeResponse(
                ok: true,
                errorCode: null,
                message: 'ok',
                node: null,
              );
            },
      );
      addTearDown(controller.dispose);
      await controller.loadNotes();

      final response = await controller.createWorkspaceNoteInFolder(
        parentNodeId: '__uncategorized__',
      );

      expect(response.ok, isTrue);
      expect(linkedParentNodeId, isNull);
    },
  );

  test('moveWorkspaceNode maps __uncategorized__ target to root', () async {
    String? movedParentNodeId;
    final controller = _buildController(
      store: <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# one', updatedAt: 1),
      },
      workspaceMoveNodeInvoker:
          ({required nodeId, newParentId, targetOrder}) async {
            movedParentNodeId = newParentId;
            return const rust_api.WorkspaceActionResponse(
              ok: true,
              errorCode: null,
              message: 'ok',
            );
          },
    );
    addTearDown(controller.dispose);

    final response = await controller.moveWorkspaceNode(
      nodeId: '11111111-1111-4111-8111-111111111111',
      newParentNodeId: '__uncategorized__',
    );

    expect(response.ok, isTrue);
    expect(movedParentNodeId, isNull);
  });
}
