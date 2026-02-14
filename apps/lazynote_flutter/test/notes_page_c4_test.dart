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
    required List<String> tags,
  }) {
    return rust_api.NoteItem(
      atomId: atomId,
      content: content,
      previewText: null,
      previewImage: null,
      updatedAt: updatedAt,
      tags: tags,
    );
  }

  testWidgets('C4 filter apply and clear refresh notes_list(tag)', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Work',
        updatedAt: 2,
        tags: const ['work'],
      ),
      'note-2': note(
        atomId: 'note-2',
        content: '# Home',
        updatedAt: 1,
        tags: const ['home'],
      ),
    };

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: ['home', 'work'],
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        final items = store.values
            .where((item) => tag == null || item.tags.contains(tag))
            .toList();
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: items,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_tag_filter_chip_work')));
    await tester.pump();
    await tester.pump();

    expect(controller.selectedTag, 'work');
    expect(
      find.byKey(const Key('notes_tag_filter_expand_button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('notes_tag_filter_clear_button')),
      findsNothing,
    );
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-2')), findsNothing);

    await tester.tap(find.byKey(const Key('notes_tag_filter_chip_work')));
    await tester.pump();
    await tester.pump();

    expect(controller.selectedTag, isNull);
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-2')), findsOneWidget);
  });

  testWidgets('C4 tag filter supports expand/collapse when too many tags', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Seed',
        updatedAt: 1,
        tags: const ['a'],
      ),
    };
    const tags = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: tags,
        );
      },
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('notes_tag_filter_expand_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_tag_filter_chip_h')), findsNothing);

    await tester.tap(find.byKey(const Key('notes_tag_filter_expand_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.byKey(const Key('notes_tag_filter_collapse_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_tag_filter_chip_h')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_tag_filter_collapse_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.byKey(const Key('notes_tag_filter_expand_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notes_tag_filter_chip_h')), findsNothing);
  });

  testWidgets(
    'C4 activating non-matching open tab does not pollute filtered list',
    (WidgetTester tester) async {
      final store = <String, rust_api.NoteItem>{
        'note-home': note(
          atomId: 'note-home',
          content: '# Home',
          updatedAt: 2,
          tags: const ['home'],
        ),
        'note-work': note(
          atomId: 'note-work',
          content: '# Work',
          updatedAt: 1,
          tags: const ['work'],
        ),
      };

      final controller = NotesController(
        prepare: () async {},
        tagsListInvoker: () async {
          return const rust_api.TagsListResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            tags: ['home', 'work'],
          );
        },
        notesListInvoker: ({tag, limit, offset}) async {
          final items = store.values
              .where((item) => tag == null || item.tags.contains(tag))
              .toList();
          return rust_api.NotesListResponse(
            ok: true,
            errorCode: null,
            message: 'ok',
            appliedLimit: 50,
            items: items,
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

      await tester.pumpWidget(
        wrapWithMaterial(NotesPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump();

      await controller.openNoteFromExplorer('note-work');
      await tester.pump();
      await tester.pump();
      expect(controller.openNoteIds, containsAll(['note-home', 'note-work']));

      await tester.tap(find.byKey(const Key('notes_tag_filter_chip_home')));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('notes_list_item_note-home')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('notes_list_item_note-work')), findsNothing);

      await controller.activateOpenNote('note-work');
      await tester.pump();
      await tester.pump();
      expect(controller.activeNoteId, 'note-work');

      // Critical: filtered list must remain pure `home` result set.
      expect(
        find.byKey(const Key('notes_list_item_note-home')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('notes_list_item_note-work')), findsNothing);
    },
  );

  testWidgets('C4 contextual create auto-applies active filter tag', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Work Seed',
        updatedAt: 2,
        tags: const ['work'],
      ),
    };
    final setTagCalls = <List<String>>[];

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: ['work'],
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        final items = store.values
            .where((item) => tag == null || item.tags.contains(tag))
            .toList();
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: items,
        );
      },
      noteCreateInvoker: ({required content}) async {
        final created = note(
          atomId: 'note-new',
          content: content,
          updatedAt: 3,
          tags: const [],
        );
        store[created.atomId] = created;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: created,
        );
      },
      noteSetTagsInvoker: ({required atomId, required tags}) async {
        setTagCalls.add(tags);
        final updated = note(
          atomId: atomId,
          content: store[atomId]?.content ?? '',
          updatedAt: 4,
          tags: tags,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_tag_filter_chip_work')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_create_button')));
    await tester.pump();
    await tester.pump();

    expect(setTagCalls, [
      ['work'],
    ]);
    expect(controller.activeNoteId, 'note-new');
    expect(find.byKey(const Key('notes_list_item_note-new')), findsOneWidget);
  });

  testWidgets('C4 add-tag dialog submits without controller dispose crash', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Seed',
        updatedAt: 2,
        tags: const [],
      ),
    };

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: [],
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: store.values.toList(),
        );
      },
      noteSetTagsInvoker: ({required atomId, required tags}) async {
        final updated = note(
          atomId: atomId,
          content: store[atomId]?.content ?? '',
          updatedAt: 3,
          tags: tags,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_add_tag_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_add_tag_input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('notes_add_tag_input')),
      'work',
    );
    await tester.tap(find.byKey(const Key('notes_add_tag_submit_button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_tag_chip_work')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('C4 ghost state keeps editor when active note leaves filter', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Work Doc',
        updatedAt: 2,
        tags: const ['work'],
      ),
    };

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: ['home', 'work'],
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        final items = store.values
            .where((item) => tag == null || item.tags.contains(tag))
            .toList();
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: items,
        );
      },
      noteSetTagsInvoker: ({required atomId, required tags}) async {
        final updated = note(
          atomId: atomId,
          content: store[atomId]?.content ?? '',
          updatedAt: 3,
          tags: tags,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_tag_filter_chip_work')));
    await tester.pump();
    await tester.pump();
    expect(controller.selectedTag, 'work');

    final changed = await controller.setActiveNoteTags(const ['home']);
    expect(changed, isTrue);
    await tester.pump();
    await tester.pump();

    expect(controller.activeNoteId, 'note-1');
    expect(find.byKey(const Key('notes_list_item_note-1')), findsNothing);
    expect(find.byKey(const Key('note_editor_field')), findsOneWidget);
  });

  testWidgets('C4 tag chip disappears after removed from last note', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Seed',
        updatedAt: 2,
        tags: const ['temp'],
      ),
    };

    List<String> computedTags() {
      final set = <String>{};
      for (final item in store.values) {
        set.addAll(item.tags);
      }
      final tags = set.toList()..sort();
      return tags;
    }

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: computedTags(),
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        final items = store.values
            .where((item) => tag == null || item.tags.contains(tag))
            .toList();
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: items,
        );
      },
      noteSetTagsInvoker: ({required atomId, required tags}) async {
        final updated = note(
          atomId: atomId,
          content: store[atomId]?.content ?? '',
          updatedAt: 3,
          tags: tags,
        );
        store[atomId] = updated;
        return rust_api.NoteResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          note: updated,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_tag_filter_chip_temp')), findsOneWidget);

    final changed = await controller.setActiveNoteTags(const []);
    expect(changed, isTrue);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_tag_filter_chip_temp')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('C4 tag filter failure is explicit and retry recovers', (
    WidgetTester tester,
  ) async {
    var tagCalls = 0;
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Work',
        updatedAt: 2,
        tags: const ['work'],
      ),
    };

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        tagCalls += 1;
        if (tagCalls == 1) {
          return const rust_api.TagsListResponse(
            ok: false,
            errorCode: 'db_error',
            message: 'tag load failed',
            tags: [],
          );
        }
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: ['work'],
        );
      },
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notes_tag_filter_error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_tag_filter_retry_button')));
    await tester.pump();
    await tester.pump();

    expect(tagCalls, 2);
    expect(find.byKey(const Key('notes_tag_filter_error')), findsNothing);
    expect(find.byKey(const Key('notes_tag_filter_chip_work')), findsOneWidget);
  });

  testWidgets('C4 filtered notes_list failure can recover via retry', (
    WidgetTester tester,
  ) async {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(
        atomId: 'note-1',
        content: '# Work',
        updatedAt: 2,
        tags: const ['work'],
      ),
      'note-2': note(
        atomId: 'note-2',
        content: '# Home',
        updatedAt: 1,
        tags: const ['home'],
      ),
    };
    var filteredCalls = 0;

    final controller = NotesController(
      prepare: () async {},
      tagsListInvoker: () async {
        return const rust_api.TagsListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          tags: ['home', 'work'],
        );
      },
      notesListInvoker: ({tag, limit, offset}) async {
        if (tag == 'work') {
          filteredCalls += 1;
          if (filteredCalls == 1) {
            return const rust_api.NotesListResponse(
              ok: false,
              errorCode: 'db_error',
              message: 'filter failed',
              appliedLimit: 50,
              items: [],
            );
          }
        }
        final items = store.values
            .where((item) => tag == null || item.tags.contains(tag))
            .toList();
        return rust_api.NotesListResponse(
          ok: true,
          errorCode: null,
          message: 'ok',
          appliedLimit: 50,
          items: items,
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

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('notes_tag_filter_chip_work')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('notes_list_error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notes_retry_button')));
    await tester.pump();
    await tester.pump();

    expect(filteredCalls, 2);
    expect(find.byKey(const Key('notes_list_item_note-1')), findsOneWidget);
    expect(find.byKey(const Key('notes_list_item_note-2')), findsNothing);
  });
}
