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
  WorkspaceListChildrenInvoker? workspaceListChildrenInvoker,
  WorkspaceCreateFolderInvoker? workspaceCreateFolderInvoker,
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
    workspaceListChildrenInvoker: workspaceListChildrenInvoker,
    workspaceCreateFolderInvoker: workspaceCreateFolderInvoker,
  );
}

Widget _buildHarness({
  required NotesController controller,
  required ValueChanged<String> onOpen,
  ExplorerFolderCreateInvoker? onCreateFolderRequested,
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
            onCreateNoteRequested: () async {},
            onCreateFolderRequested: onCreateFolderRequested,
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

  testWidgets('injects default uncategorized folder and shows existing notes', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': _note(atomId: 'note-1', content: '# Legacy Note', updatedAt: 1),
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

    expect(
      find.byKey(const Key('notes_tree_folder___uncategorized__')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
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
}
