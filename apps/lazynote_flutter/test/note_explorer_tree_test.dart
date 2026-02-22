import 'package:flutter/gestures.dart';
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

rust_api.WorkspaceNodeItem _node({
  required String nodeId,
  required String kind,
  required String displayName,
  String? parentNodeId,
  String? atomId,
  int sortOrder = 0,
}) {
  return rust_api.WorkspaceNodeItem(
    nodeId: nodeId,
    kind: kind,
    parentNodeId: parentNodeId,
    atomId: atomId,
    displayName: displayName,
    sortOrder: sortOrder,
  );
}

rust_api.WorkspaceListChildrenResponse _ok(
  List<rust_api.WorkspaceNodeItem> items,
) {
  return rust_api.WorkspaceListChildrenResponse(
    ok: true,
    errorCode: null,
    message: 'ok',
    items: items,
  );
}

NotesController _controllerWithStore(
  Map<String, rust_api.NoteItem> store, {
  NoteCreateInvoker? noteCreateInvoker,
  NoteUpdateInvoker? noteUpdateInvoker,
  WorkspaceDeleteFolderInvoker? workspaceDeleteFolderInvoker,
  WorkspaceListChildrenInvoker? workspaceListChildrenInvoker,
  WorkspaceCreateFolderInvoker? workspaceCreateFolderInvoker,
  WorkspaceCreateNoteRefInvoker? workspaceCreateNoteRefInvoker,
  WorkspaceRenameNodeInvoker? workspaceRenameNodeInvoker,
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
    noteUpdateInvoker: noteUpdateInvoker,
    workspaceListChildrenInvoker: workspaceListChildrenInvoker,
    workspaceCreateFolderInvoker: workspaceCreateFolderInvoker,
    workspaceDeleteFolderInvoker: workspaceDeleteFolderInvoker,
    workspaceCreateNoteRefInvoker: workspaceCreateNoteRefInvoker,
    workspaceRenameNodeInvoker: workspaceRenameNodeInvoker,
  );
}

Widget _buildHarness({
  required NotesController controller,
  required ValueChanged<String> onOpen,
  ValueChanged<String>? onOpenPinned,
  ExplorerNoteCreateInFolderInvoker? onCreateNoteInFolderRequested,
  ExplorerFolderDeleteInvoker? onDeleteFolderRequested,
  ExplorerFolderCreateInvoker? onCreateFolderRequested,
  ExplorerNodeRenameInvoker? onRenameNodeRequested,
  WorkspaceListChildrenInvoker? treeLoader,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return NoteExplorer(
            controller: controller,
            onOpenNoteRequested: onOpen,
            onOpenNotePinnedRequested: onOpenPinned,
            onCreateNoteRequested: () async {},
            onCreateNoteInFolderRequested: onCreateNoteInFolderRequested,
            onDeleteFolderRequested: onDeleteFolderRequested,
            onCreateFolderRequested: onCreateFolderRequested,
            onRenameNodeRequested: onRenameNodeRequested,
            workspaceListChildrenInvoker: treeLoader,
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('loads root first and lazy-loads folder children on expand', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
      'note-2': _note(atomId: 'note-2', content: '# Note Two', updatedAt: 2),
    };
    final calls = <String>[];
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      calls.add(parentNodeId ?? '<root>');
      if (parentNodeId == null) {
        return _ok(<rust_api.WorkspaceNodeItem>[
          _node(
            nodeId: 'folder-1',
            kind: 'folder',
            displayName: 'Folder',
            sortOrder: 0,
          ),
          _node(
            nodeId: 'root-note-1',
            kind: 'note_ref',
            atomId: 'note-1',
            displayName: 'Note One',
            sortOrder: 1,
          ),
        ]);
      }
      if (parentNodeId == 'folder-1') {
        return _ok(<rust_api.WorkspaceNodeItem>[
          _node(
            nodeId: 'folder-note-2',
            kind: 'note_ref',
            parentNodeId: 'folder-1',
            atomId: 'note-2',
            displayName: 'Note Two',
            sortOrder: 0,
          ),
        ]);
      }
      return _ok(const <rust_api.WorkspaceNodeItem>[]);
    }

    await tester.pumpWidget(
      _buildHarness(controller: controller, onOpen: (_) {}, treeLoader: loader),
    );
    await tester.pumpAndSettle();

    expect(calls.where((call) => call == '<root>').length, 1);
    expect(find.byKey(const Key('notes_tree_folder_folder-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-2')), findsNothing);

    await tester.tap(find.byKey(const Key('notes_tree_toggle_folder-1')));
    await tester.pumpAndSettle();

    expect(calls, contains('folder-1'));
    expect(find.byKey(const Key('notes_list_item_note-2')), findsOneWidget);
  });

  testWidgets(
    'folder children keep folder-before-note grouping even with lower note sortOrder',
    (WidgetTester tester) async {
      const parentId = '11111111-1111-4111-8111-111111111111';
      const childFolderId = '22222222-2222-4222-8222-222222222222';
      const childNoteRefId = '33333333-3333-4333-8333-333333333333';
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(
          atomId: 'note-1',
          content: '# Child Note',
          updatedAt: 1,
        ),
      };
      final controller = _controllerWithStore(store);
      addTearDown(controller.dispose);
      await controller.loadNotes();

      Future<rust_api.WorkspaceListChildrenResponse> loader({
        String? parentNodeId,
      }) async {
        if (parentNodeId == null) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: parentId,
              kind: 'folder',
              displayName: 'Parent',
              sortOrder: 0,
            ),
          ]);
        }
        if (parentNodeId == parentId) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: childNoteRefId,
              kind: 'note_ref',
              parentNodeId: parentId,
              atomId: 'note-1',
              displayName: 'Child Note',
              sortOrder: 0,
            ),
            _node(
              nodeId: childFolderId,
              kind: 'folder',
              parentNodeId: parentId,
              displayName: 'Child Folder',
              sortOrder: 99,
            ),
          ]);
        }
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      }

      await tester.pumpWidget(
        _buildHarness(
          controller: controller,
          onOpen: (_) {},
          treeLoader: loader,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notes_tree_toggle_$parentId')));
      await tester.pumpAndSettle();

      final folderY = tester
          .getTopLeft(find.byKey(const Key('notes_tree_folder_$childFolderId')))
          .dy;
      final noteY = tester
          .getTopLeft(
            find.byKey(const Key('notes_tree_note_row_$childNoteRefId')),
          )
          .dy;
      expect(folderY, lessThan(noteY));
    },
  );

  testWidgets('injects default uncategorized folder and shows existing notes', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
    };
    final controller = _controllerWithStore(
      store,
      noteUpdateInvoker: ({required atomId, required content}) async {
        final existing = store[atomId]!;
        final updated = rust_api.NoteItem(
          atomId: existing.atomId,
          content: content,
          previewText: null,
          previewImage: null,
          updatedAt: existing.updatedAt + 1,
          tags: existing.tags,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
        );
      },
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(controller: controller, onOpen: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notes_tree_folder___uncategorized__')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.text('No preview available.'), findsNothing);
  });

  testWidgets(
    'create folder button triggers callback and refreshes root tree',
    (WidgetTester tester) async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
      };
      final controller = _controllerWithStore(store);
      addTearDown(controller.dispose);
      await controller.loadNotes();

      final createdNames = <String>[];
      final rootFolders = <rust_api.WorkspaceNodeItem>[];
      var rootLoads = 0;
      Future<rust_api.WorkspaceListChildrenResponse> loader({
        String? parentNodeId,
      }) async {
        if (parentNodeId != null) {
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        }
        rootLoads += 1;
        return _ok(List<rust_api.WorkspaceNodeItem>.from(rootFolders));
      }

      await tester.pumpWidget(
        _buildHarness(
          controller: controller,
          onOpen: (_) {},
          treeLoader: loader,
          onCreateFolderRequested: (name, parentNodeId) async {
            createdNames.add(name);
            rootFolders.add(
              _node(
                nodeId: 'folder-team',
                kind: 'folder',
                displayName: name,
                parentNodeId: parentNodeId,
                sortOrder: 0,
              ),
            );
            return rust_api.WorkspaceNodeResponse(
              ok: true,
              errorCode: null,
              message: 'ok',
              node: rootFolders.first,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final loadsBeforeCreate = rootLoads;
      await tester.tap(find.byKey(const Key('notes_create_folder_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('notes_create_folder_name_input')),
        'Team',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('notes_create_folder_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(createdNames, const <String>['Team']);
      expect(rootLoads, greaterThan(loadsBeforeCreate));
      expect(
        find.byKey(const Key('notes_tree_folder_folder-team')),
        findsOneWidget,
      );
    },
  );

  testWidgets('create folder refresh keeps uncategorized collapse state', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
    };
    final rootFolders = <rust_api.WorkspaceNodeItem>[];
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId != null) {
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        }
        return _ok(List<rust_api.WorkspaceNodeItem>.from(rootFolders));
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        onCreateFolderRequested: (name, parentNodeId) async {
          rootFolders.add(
            _node(
              nodeId: '33333333-3333-4333-8333-333333333333',
              kind: 'folder',
              displayName: name,
              parentNodeId: parentNodeId,
              sortOrder: 0,
            ),
          );
          return rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: rootFolders.first,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('notes_tree_toggle___uncategorized__')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);

    await tester.tap(find.byKey(const Key('notes_create_folder_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_create_folder_name_input')),
      'Team',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('notes_create_folder_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);
    expect(
      find.byKey(
        const Key('notes_tree_folder_33333333-3333-4333-8333-333333333333'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('folder row create button forwards parent folder id', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
    };
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    final created = <String?>[];
    const parentId = '11111111-1111-4111-8111-111111111111';
    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      if (parentNodeId != null) {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      }
      return _ok(<rust_api.WorkspaceNodeItem>[
        _node(
          nodeId: parentId,
          kind: 'folder',
          displayName: 'Team',
          sortOrder: 0,
        ),
      ]);
    }

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        treeLoader: loader,
        onCreateFolderRequested: (name, parentNodeId) async {
          created.add(parentNodeId);
          return const rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: null,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key(
          'notes_folder_create_button_11111111-1111-4111-8111-111111111111',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_create_folder_name_input')),
      'Child',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('notes_create_folder_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(created, const <String?>[parentId]);
  });

  testWidgets('create child folder refreshes parent branch and shows child', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
    };
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    const parentId = '11111111-1111-4111-8111-111111111111';
    var hasChild = false;
    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      if (parentNodeId == null) {
        return _ok(<rust_api.WorkspaceNodeItem>[
          _node(
            nodeId: parentId,
            kind: 'folder',
            displayName: 'Team',
            sortOrder: 0,
          ),
        ]);
      }
      if (parentNodeId == parentId) {
        return _ok(
          hasChild
              ? <rust_api.WorkspaceNodeItem>[
                  _node(
                    nodeId: '22222222-2222-4222-8222-222222222222',
                    kind: 'folder',
                    parentNodeId: parentId,
                    displayName: 'Child',
                    sortOrder: 0,
                  ),
                ]
              : const <rust_api.WorkspaceNodeItem>[],
        );
      }
      return _ok(const <rust_api.WorkspaceNodeItem>[]);
    }

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        treeLoader: loader,
        onCreateFolderRequested: (name, parentNodeId) async {
          hasChild = true;
          return const rust_api.WorkspaceNodeResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            node: null,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key(
          'notes_folder_create_button_11111111-1111-4111-8111-111111111111',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_create_folder_name_input')),
      'Child',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('notes_create_folder_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('notes_tree_folder_22222222-2222-4222-8222-222222222222'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'create child folder stays visible when controller revision refresh path is used',
    (WidgetTester tester) async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
      };
      const parentId = '11111111-1111-4111-8111-111111111111';
      var hasChild = false;
      final controller = _controllerWithStore(
        store,
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          if (parentNodeId == null) {
            return _ok(<rust_api.WorkspaceNodeItem>[
              _node(
                nodeId: parentId,
                kind: 'folder',
                displayName: 'Team',
                sortOrder: 0,
              ),
            ]);
          }
          if (parentNodeId == parentId) {
            return _ok(
              hasChild
                  ? <rust_api.WorkspaceNodeItem>[
                      _node(
                        nodeId: '22222222-2222-4222-8222-222222222222',
                        kind: 'folder',
                        parentNodeId: parentId,
                        displayName: 'Child',
                        sortOrder: 0,
                      ),
                    ]
                  : const <rust_api.WorkspaceNodeItem>[],
            );
          }
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        },
        workspaceCreateFolderInvoker: ({parentNodeId, required name}) async {
          if (parentNodeId == parentId && name == 'Child') {
            hasChild = true;
          }
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

      await tester.pumpWidget(
        _buildHarness(
          controller: controller,
          onOpen: (_) {},
          onCreateFolderRequested: (name, parentNodeId) {
            return controller.createWorkspaceFolder(
              name: name,
              parentNodeId: parentNodeId,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const Key(
            'notes_folder_create_button_11111111-1111-4111-8111-111111111111',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('notes_create_folder_name_input')),
        'Child',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('notes_create_folder_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('notes_tree_folder_22222222-2222-4222-8222-222222222222'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('single tap emits open intent for note row', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
    };
    final opened = <String>[];
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      if (parentNodeId != null) {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      }
      return _ok(<rust_api.WorkspaceNodeItem>[
        _node(
          nodeId: 'root-note-1',
          kind: 'note_ref',
          atomId: 'note-1',
          displayName: 'Note One',
        ),
      ]);
    }

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: opened.add,
        treeLoader: loader,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_list_item_note-1')));
    await tester.pump();

    expect(opened, const <String>['note-1']);
  });

  testWidgets('double tap emits pinned-open intent when callback is provided', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
    };
    final opened = <String>[];
    final pinned = <String>[];
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      if (parentNodeId != null) {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      }
      return _ok(<rust_api.WorkspaceNodeItem>[
        _node(
          nodeId: 'root-note-1',
          kind: 'note_ref',
          atomId: 'note-1',
          displayName: 'Note One',
        ),
      ]);
    }

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: opened.add,
        onOpenPinned: pinned.add,
        treeLoader: loader,
      ),
    );
    await tester.pumpAndSettle();

    final noteFinder = find.byKey(const Key('notes_list_item_note-1'));
    await tester.tap(noteFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(noteFinder);
    await tester.pumpAndSettle();

    expect(opened, const <String>['note-1']);
    expect(pinned, const <String>['note-1']);
  });

  testWidgets('root error displays retry action and can recover', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Note One', updatedAt: 1),
    };
    final controller = _controllerWithStore(store);
    addTearDown(controller.dispose);
    await controller.loadNotes();

    var rootAttempts = 0;
    Future<rust_api.WorkspaceListChildrenResponse> loader({
      String? parentNodeId,
    }) async {
      if (parentNodeId != null) {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      }
      rootAttempts += 1;
      if (rootAttempts == 1) {
        return const rust_api.WorkspaceListChildrenResponse(
          ok: false,
          errorCode: 'db_error',
          message: 'load failed',
          items: <rust_api.WorkspaceNodeItem>[],
        );
      }
      return _ok(<rust_api.WorkspaceNodeItem>[
        _node(
          nodeId: 'root-note-1',
          kind: 'note_ref',
          atomId: 'note-1',
          displayName: 'Note One',
        ),
      ]);
    }

    await tester.pumpWidget(
      _buildHarness(controller: controller, onOpen: (_) {}, treeLoader: loader),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_tree_root_error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_tree_root_retry_button')));
    await tester.pumpAndSettle();

    expect(rootAttempts, 2);
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
  });

  testWidgets(
    'create note from uncategorized refreshes cached branch while collapsed',
    (WidgetTester tester) async {
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(
          atomId: 'note-1',
          content: '# Legacy Note',
          updatedAt: 1,
        ),
      };
      final controller = _controllerWithStore(
        store,
        noteCreateInvoker: ({required content}) async {
          final created = _note(
            atomId: 'note-2',
            content: '# Created',
            updatedAt: 2,
          );
          store[created.atomId] = created;
          return rust_api.NoteResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            note: created,
          );
        },
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        },
        workspaceCreateNoteRefInvoker:
            ({parentNodeId, required atomId, displayName}) async {
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
      );
      addTearDown(controller.dispose);
      await controller.loadNotes();

      await tester.pumpWidget(
        _buildHarness(
          controller: controller,
          onOpen: (_) {},
          onCreateNoteInFolderRequested: (parentNodeId) {
            return controller.createWorkspaceNoteInFolder(
              parentNodeId: parentNodeId,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Collapse Uncategorized so its branch cache can become stale.
      await tester.tap(
        find.byKey(const Key('notes_tree_toggle___uncategorized__')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);

      await tester.tap(
        find.byKey(const Key('notes_tree_folder___uncategorized__')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes_context_action_newNote')));
      await tester.pumpAndSettle();

      // Re-expand and ensure newly created note is visible without app reload.
      await tester.tap(
        find.byKey(const Key('notes_tree_toggle___uncategorized__')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes_list_item_note-2')), findsOneWidget);
    },
  );

  testWidgets('delete folder preserves uncategorized collapse state', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
    };
    const folderId = '11111111-1111-4111-8111-111111111111';
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId != null) {
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        }
        return _ok(<rust_api.WorkspaceNodeItem>[
          _node(
            nodeId: folderId,
            kind: 'folder',
            displayName: 'Team',
            sortOrder: 0,
          ),
        ]);
      },
      workspaceDeleteFolderInvoker: ({required nodeId, required mode}) async {
        return const rust_api.WorkspaceActionResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        onDeleteFolderRequested: (id, mode) {
          return controller.deleteWorkspaceFolder(folderId: id, mode: mode);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('notes_tree_toggle___uncategorized__')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);

    await tester.tap(find.byKey(Key('notes_folder_delete_button_$folderId')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_folder_delete_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);
  });

  testWidgets('delete child folder refreshes parent branch immediately', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
    };
    const parentId = '11111111-1111-4111-8111-111111111111';
    const childId = '22222222-2222-4222-8222-222222222222';
    var hasChild = true;
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId == null) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: parentId,
              kind: 'folder',
              displayName: 'Team',
              sortOrder: 0,
            ),
          ]);
        }
        if (parentNodeId == parentId) {
          return _ok(
            hasChild
                ? <rust_api.WorkspaceNodeItem>[
                    _node(
                      nodeId: childId,
                      kind: 'folder',
                      parentNodeId: parentId,
                      displayName: 'Child',
                      sortOrder: 0,
                    ),
                  ]
                : const <rust_api.WorkspaceNodeItem>[],
          );
        }
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      },
      workspaceDeleteFolderInvoker: ({required nodeId, required mode}) async {
        if (nodeId == childId) {
          hasChild = false;
        }
        return const rust_api.WorkspaceActionResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        onDeleteFolderRequested: (id, mode) {
          return controller.deleteWorkspaceFolder(folderId: id, mode: mode);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_tree_toggle_$parentId')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('notes_tree_folder_$childId')), findsOneWidget);

    await tester.tap(find.byKey(Key('notes_folder_delete_button_$childId')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notes_folder_delete_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('notes_tree_folder_$childId')), findsNothing);
    expect(
      find.byKey(Key('notes_folder_delete_button_$childId')),
      findsNothing,
    );
  });

  testWidgets('rename child folder refreshes parent branch immediately', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
    };
    const parentId = '11111111-1111-4111-8111-111111111111';
    const childId = '22222222-2222-4222-8222-222222222222';
    var childName = 'Child';
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId == null) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: parentId,
              kind: 'folder',
              displayName: 'Team',
              sortOrder: 0,
            ),
          ]);
        }
        if (parentNodeId == parentId) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: childId,
              kind: 'folder',
              parentNodeId: parentId,
              displayName: childName,
              sortOrder: 0,
            ),
          ]);
        }
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      },
      workspaceRenameNodeInvoker: ({required nodeId, required newName}) async {
        if (nodeId == childId) {
          childName = newName;
        }
        return const rust_api.WorkspaceActionResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(
        controller: controller,
        onOpen: (_) {},
        onRenameNodeRequested: (nodeId, newName) {
          return controller.renameWorkspaceNode(
            nodeId: nodeId,
            newName: newName,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('notes_tree_toggle_$parentId')));
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);

    await tester.tap(
      find.byKey(Key('notes_tree_folder_$childId')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_context_action_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes_rename_node_input')),
      'Child Renamed',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('notes_rename_node_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.text('Child Renamed'), findsOneWidget);
    expect(find.text('Child'), findsNothing);
  });

  testWidgets('uncategorized note title updates after draft edit', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Old Title', updatedAt: 1),
    };
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(controller: controller, onOpen: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old Title'), findsWidgets);

    controller.updateActiveDraft('# New Title');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();

    expect(find.text('New Title'), findsWidgets);
  });

  testWidgets('folder note title follows draft projection', (
    WidgetTester tester,
  ) async {
    const folderId = '11111111-1111-4111-8111-111111111111';
    const noteRefId = '22222222-2222-4222-8222-222222222222';
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(
        atomId: 'note-1',
        content: '# Old Folder Title',
        updatedAt: 1,
      ),
    };
    final controller = _controllerWithStore(
      store,
      workspaceListChildrenInvoker: ({parentNodeId}) async {
        if (parentNodeId == null) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: folderId,
              kind: 'folder',
              displayName: 'Team',
              sortOrder: 0,
            ),
          ]);
        }
        if (parentNodeId == folderId) {
          return _ok(<rust_api.WorkspaceNodeItem>[
            _node(
              nodeId: noteRefId,
              kind: 'note_ref',
              parentNodeId: folderId,
              atomId: 'note-1',
              displayName: 'Untitled note',
              sortOrder: 0,
            ),
          ]);
        }
        return _ok(const <rust_api.WorkspaceNodeItem>[]);
      },
    );
    addTearDown(controller.dispose);
    await controller.loadNotes();

    await tester.pumpWidget(
      _buildHarness(controller: controller, onOpen: (_) {}),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes_tree_toggle_$folderId')));
    await tester.pumpAndSettle();

    expect(find.text('Old Folder Title'), findsWidgets);

    controller.updateActiveDraft('# New Folder Title');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();

    expect(find.text('New Folder Title'), findsWidgets);
  });

  testWidgets(
    'note created in child folder is not duplicated under uncategorized',
    (WidgetTester tester) async {
      const folderId = '11111111-1111-4111-8111-111111111111';
      const folderNoteRefId = 'ref_folder_note_1';
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(
          atomId: 'note-1',
          content: '# Child Note',
          updatedAt: 1,
        ),
      };
      final controller = _controllerWithStore(
        store,
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          if (parentNodeId == null) {
            return _ok(<rust_api.WorkspaceNodeItem>[
              _node(
                nodeId: folderId,
                kind: 'folder',
                displayName: 'Projects',
                sortOrder: 0,
              ),
            ]);
          }
          if (parentNodeId == folderId) {
            return _ok(<rust_api.WorkspaceNodeItem>[
              _node(
                nodeId: folderNoteRefId,
                kind: 'note_ref',
                parentNodeId: folderId,
                atomId: 'note-1',
                displayName: 'Child Note',
                sortOrder: 0,
              ),
            ]);
          }
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        },
      );
      addTearDown(controller.dispose);
      await controller.loadNotes();

      await tester.pumpWidget(
        _buildHarness(controller: controller, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notes_tree_toggle_$folderId')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notes_tree_note_row_$folderNoteRefId')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('notes_tree_note_row_note_ref_uncategorized_note-1'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'literal Untitled title does not fallback to note_ref display name',
    (WidgetTester tester) async {
      const folderId = '11111111-1111-4111-8111-111111111111';
      const noteRefId = '33333333-3333-4333-8333-333333333333';
      final store = <String, rust_api.NoteItem>{
        'note-1': _note(atomId: 'note-1', content: 'Untitled', updatedAt: 1),
      };
      final controller = _controllerWithStore(
        store,
        workspaceListChildrenInvoker: ({parentNodeId}) async {
          if (parentNodeId == null) {
            return _ok(<rust_api.WorkspaceNodeItem>[
              _node(
                nodeId: folderId,
                kind: 'folder',
                displayName: 'Team',
                sortOrder: 0,
              ),
            ]);
          }
          if (parentNodeId == folderId) {
            return _ok(<rust_api.WorkspaceNodeItem>[
              _node(
                nodeId: noteRefId,
                kind: 'note_ref',
                parentNodeId: folderId,
                atomId: 'note-1',
                displayName: 'Display Alias',
                sortOrder: 0,
              ),
            ]);
          }
          return _ok(const <rust_api.WorkspaceNodeItem>[]);
        },
      );
      addTearDown(controller.dispose);
      await controller.loadNotes();

      await tester.pumpWidget(
        _buildHarness(controller: controller, onOpen: (_) {}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notes_tree_toggle_$folderId')));
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('notes_tree_note_row_$noteRefId'));
      expect(
        find.descendant(of: row, matching: find.text('Untitled')),
        findsWidgets,
      );
      expect(
        find.descendant(of: row, matching: find.text('Display Alias')),
        findsNothing,
      );
    },
  );
}
