import 'dart:async';

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

rust_api.WorkspaceActionResponse _okAction() {
  return const rust_api.WorkspaceActionResponse(
    ok: true,
    errorCode: null,
    message: 'ok',
  );
}

NotesController _buildController({
  required Map<String, rust_api.NoteItem> store,
  Future<rust_api.NoteResponse> Function({
    required String atomId,
    required String content,
  })?
  noteUpdateInvoker,
  WorkspaceCreateFolderInvoker? workspaceCreateFolderInvoker,
  WorkspaceRenameNodeInvoker? workspaceRenameNodeInvoker,
  WorkspaceMoveNodeInvoker? workspaceMoveNodeInvoker,
  WorkspaceListChildrenInvoker? workspaceListChildrenInvoker,
}) {
  return NotesController(
    prepare: () async {},
    autosaveDebounce: const Duration(seconds: 30),
    notesListInvoker: ({tag, limit, offset}) async {
      final ids = store.keys.toList()..sort();
      final items = <rust_api.NoteItem>[];
      for (final id in ids) {
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
    workspaceCreateFolderInvoker:
        workspaceCreateFolderInvoker ??
        ({parentNodeId, required name}) async {
          return const rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: null,
          );
        },
    workspaceRenameNodeInvoker:
        workspaceRenameNodeInvoker ??
        ({required nodeId, required newName}) async {
          return _okAction();
        },
    workspaceMoveNodeInvoker:
        workspaceMoveNodeInvoker ??
        ({required nodeId, newParentId, targetOrder}) async {
          return _okAction();
        },
    workspaceListChildrenInvoker:
        workspaceListChildrenInvoker ??
        ({parentNodeId}) async {
          if (parentNodeId != null) {
            return const rust_api.WorkspaceListChildrenResponse(
              ok: true,
              errorCode: null,
              message: 'ok',
              items: <rust_api.WorkspaceNodeItem>[],
            );
          }
          return const rust_api.WorkspaceListChildrenResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            items: <rust_api.WorkspaceNodeItem>[
              rust_api.WorkspaceNodeItem(
                nodeId: '11111111-1111-4111-8111-111111111111',
                kind: 'folder',
                parentNodeId: null,
                atomId: null,
                displayName: 'Folder A',
                sortOrder: 0,
              ),
            ],
          );
        },
  );
}

void main() {
  test(
    'save-in-flight + pane switch keeps active-pane routing stable',
    () async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
        'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
      };
      final saveStarted = Completer<void>();
      final allowSaveFinish = Completer<void>();
      final saveCalls = <String>[];

      final controller = _buildController(
        store: store,
        noteUpdateInvoker: ({required atomId, required content}) async {
          saveCalls.add('$atomId::$content');
          if (!saveStarted.isCompleted) {
            saveStarted.complete();
          }
          await allowSaveFinish.future;
          final current = store[atomId]!;
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
      addTearDown(controller.dispose);

      await controller.loadNotes();
      final primaryPane = controller.workspaceProvider.activePaneId;
      expect(
        controller.splitActivePane(
          direction: WorkspaceSplitDirection.horizontal,
          containerExtent: 1200,
        ),
        WorkspaceSplitResult.ok,
      );
      final splitPane = controller.workspaceProvider.activePaneId;
      expect(splitPane, isNot(primaryPane));

      await controller.openNoteFromExplorer('note-2');
      expect(controller.workspaceProvider.activePaneId, splitPane);
      expect(controller.activeNoteId, 'note-2');

      controller.updateActiveDraft('# second updated');
      final flushFuture = controller.flushPendingSave();
      await saveStarted.future;

      expect(controller.switchActivePane(primaryPane), isTrue);
      expect(controller.workspaceProvider.activePaneId, primaryPane);
      expect(controller.activeNoteId, 'note-1');

      allowSaveFinish.complete();
      final flushed = await flushFuture;

      expect(flushed, isTrue);
      expect(saveCalls, ['note-2::# second updated']);
      expect(controller.workspaceProvider.activePaneId, primaryPane);
      expect(controller.activeNoteId, 'note-1');
      expect(controller.detailErrorMessage, isNull);
    },
  );

  test('rename/move workspace node keeps active editor state stable', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    final renameCalls = <(String, String)>[];
    final moveCalls = <(String, String?, int?)>[];

    final controller = _buildController(
      store: store,
      workspaceRenameNodeInvoker: ({required nodeId, required newName}) async {
        renameCalls.add((nodeId, newName));
        return _okAction();
      },
      workspaceMoveNodeInvoker:
          ({required nodeId, newParentId, targetOrder}) async {
            moveCalls.add((nodeId, newParentId, targetOrder));
            return _okAction();
          },
    );
    addTearDown(controller.dispose);

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    final beforeRevision = controller.workspaceTreeRevision;

    final renamed = await controller.renameWorkspaceNode(
      nodeId: '11111111-1111-4111-8111-111111111111',
      newName: 'Folder Renamed',
    );
    final moved = await controller.moveWorkspaceNode(
      nodeId: '11111111-1111-4111-8111-111111111111',
      newParentNodeId: null,
      targetOrder: 9,
    );

    expect(renamed.ok, isTrue);
    expect(moved.ok, isTrue);
    expect(controller.workspaceTreeRevision, beforeRevision + 2);
    expect(renameCalls, [
      ('11111111-1111-4111-8111-111111111111', 'Folder Renamed'),
    ]);
    expect(moveCalls, [('11111111-1111-4111-8111-111111111111', null, null)]);
    expect(controller.activeNoteId, 'note-2');
    expect(controller.openNoteIds, contains('note-2'));
    expect(controller.detailErrorMessage, isNull);
  });

  test('workspace tree refresh path does not reset opened tabs', () async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# first', updatedAt: 2),
      'note-2': _note(atomId: 'note-2', content: '# second', updatedAt: 1),
    };
    var treeVersion = 0;

    final controller = _buildController(
      store: store,
      workspaceCreateFolderInvoker: ({parentNodeId, required name}) async {
        treeVersion += 1;
        return rust_api.WorkspaceNodeResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          node: rust_api.WorkspaceNodeItem(
            nodeId: '33333333-3333-4333-8333-333333333333',
            kind: 'folder',
            parentNodeId: null,
            atomId: null,
            displayName: name,
            sortOrder: treeVersion,
          ),
        );
      },
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId != null) {
          return const rust_api.WorkspaceListChildrenResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            items: <rust_api.WorkspaceNodeItem>[],
          );
        }
        final root = <rust_api.WorkspaceNodeItem>[
          const rust_api.WorkspaceNodeItem(
            nodeId: '11111111-1111-4111-8111-111111111111',
            kind: 'folder',
            parentNodeId: null,
            atomId: null,
            displayName: 'Folder A',
            sortOrder: 0,
          ),
        ];
        if (treeVersion > 0) {
          root.add(
            const rust_api.WorkspaceNodeItem(
              nodeId: '33333333-3333-4333-8333-333333333333',
              kind: 'folder',
              parentNodeId: null,
              atomId: null,
              displayName: 'Inbox',
              sortOrder: 1,
            ),
          );
        }
        return rust_api.WorkspaceListChildrenResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          items: root,
        );
      },
    );
    addTearDown(controller.dispose);

    await controller.loadNotes();
    await controller.openNoteFromExplorer('note-2');
    final tabsBefore = List<String>.from(controller.openNoteIds);
    final activeBefore = controller.activeNoteId;

    final firstTree = await controller.listWorkspaceChildren(
      parentNodeId: null,
    );
    expect(firstTree.ok, isTrue);
    expect(firstTree.items.any((row) => row.displayName == 'Inbox'), isFalse);

    final created = await controller.createWorkspaceFolder(name: 'Inbox');
    expect(created.ok, isTrue);

    final secondTree = await controller.listWorkspaceChildren(
      parentNodeId: null,
    );
    expect(secondTree.ok, isTrue);
    expect(secondTree.items.any((row) => row.displayName == 'Inbox'), isTrue);
    expect(controller.openNoteIds, tabsBefore);
    expect(controller.activeNoteId, activeBefore);
  });
}
