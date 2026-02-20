import 'package:flutter/gestures.dart';
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
      tags: const <String>[],
    );
  }

  testWidgets(
    'NotesPage default side panel slot wires context actions end-to-end',
    (WidgetTester tester) async {
      const folderId = '11111111-1111-4111-8111-111111111111';
      const targetFolderId = '22222222-2222-4222-8222-222222222222';
      var nextUpdatedAt = 2;
      var noteCreateCalls = 0;
      final noteRefParents = <String?>[];
      final renameCalls = <(String, String)>[];
      final moveCalls = <(String, String?)>[];
      final store = <String, rust_api.NoteItem>{
        'note-1': note(atomId: 'note-1', content: '# Seed', updatedAt: 1),
      };

      final controller = NotesController(
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
        noteCreateInvoker: ({required content}) async {
          noteCreateCalls += 1;
          final created = note(
            atomId: 'note-${nextUpdatedAt + 10}',
            content: content,
            updatedAt: nextUpdatedAt,
          );
          nextUpdatedAt += 1;
          store[created.atomId] = created;
          return rust_api.NoteResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            note: created,
          );
        },
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          if (parentNodeId == null) {
            return rust_api.WorkspaceListChildrenResponse(
              ok: true,
              errorCode: null,
              message: 'ok',
              items: const <rust_api.WorkspaceNodeItem>[
                rust_api.WorkspaceNodeItem(
                  nodeId: folderId,
                  kind: 'folder',
                  parentNodeId: null,
                  atomId: null,
                  displayName: 'Team',
                  sortOrder: 0,
                ),
                rust_api.WorkspaceNodeItem(
                  nodeId: targetFolderId,
                  kind: 'folder',
                  parentNodeId: null,
                  atomId: null,
                  displayName: 'Archive',
                  sortOrder: 1,
                ),
              ],
            );
          }
          return const rust_api.WorkspaceListChildrenResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            items: <rust_api.WorkspaceNodeItem>[],
          );
        },
        workspaceCreateFolderInvoker: ({parentNodeId, required name}) async {
          return const rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: null,
          );
        },
        workspaceDeleteFolderInvoker: ({required nodeId, required mode}) async {
          return const rust_api.WorkspaceActionResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
          );
        },
        workspaceCreateNoteRefInvoker:
            ({parentNodeId, required atomId, displayName}) async {
              noteRefParents.add(parentNodeId);
              return rust_api.WorkspaceNodeResponse(
                ok: true,
                errorCode: null,
                message: 'ok',
                node: rust_api.WorkspaceNodeItem(
                  nodeId: 'ref_$atomId',
                  kind: 'note_ref',
                  parentNodeId: parentNodeId,
                  atomId: atomId,
                  displayName: displayName ?? atomId,
                  sortOrder: 0,
                ),
              );
            },
        workspaceRenameNodeInvoker:
            ({required nodeId, required newName}) async {
              renameCalls.add((nodeId, newName));
              return const rust_api.WorkspaceActionResponse(
                ok: true,
                errorCode: null,
                message: 'ok',
              );
            },
        workspaceMoveNodeInvoker:
            ({required nodeId, newParentId, targetOrder}) {
              moveCalls.add((nodeId, newParentId));
              return Future.value(
                const rust_api.WorkspaceActionResponse(
                  ok: true,
                  errorCode: null,
                  message: 'ok',
                ),
              );
            },
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrapWithMaterial(NotesPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      final folderLabel = find.byKey(const Key('notes_tree_folder_$folderId'));
      expect(folderLabel, findsOneWidget);

      await tester.tap(folderLabel, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notes_context_action_newNote')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_context_action_newFolder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_context_action_rename')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_context_action_move')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_context_action_deleteFolder')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('notes_context_action_newNote')));
      await tester.pumpAndSettle();

      expect(noteCreateCalls, 1);
      expect(noteRefParents, const <String?>[folderId]);

      await tester.tap(folderLabel, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_context_action_rename')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notes_rename_node_dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('notes_rename_node_input')),
        'Team Renamed',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('notes_rename_node_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(renameCalls.length, 1);
      expect(renameCalls.first.$1, folderId);
      expect(renameCalls.first.$2, 'Team Renamed');

      await tester.tap(folderLabel, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_context_action_move')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notes_move_node_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notes_move_node_target_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_move_node_confirm_button')));
      await tester.pumpAndSettle();

      expect(moveCalls.length, 1);
      expect(moveCalls.first.$1, folderId);
      expect(moveCalls.first.$2, targetFolderId);
    },
  );
}
