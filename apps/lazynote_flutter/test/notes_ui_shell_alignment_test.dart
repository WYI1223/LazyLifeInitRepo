import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_page.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';

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

  NotesController buildController() {
    final store = <String, rust_api.NoteItem>{
      'note-1': note(atomId: 'note-1', content: '# First', updatedAt: 10),
      'note-2': note(atomId: 'note-2', content: '# Second', updatedAt: 8),
    };
    return NotesController(
      prepare: () async {},
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
    );
  }

  testWidgets('notes shell card aligns with shared split layout structure', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    final shellFinder = find.byKey(const Key('notes_shell_card'));
    expect(shellFinder, findsOneWidget);
    expect(find.byKey(const Key('notes_shell_divider')), findsOneWidget);
    expect(find.byKey(const Key('note_tab_manager')), findsOneWidget);
    expect(find.byKey(const Key('notes_detail_editor')), findsOneWidget);

    final shell = tester.widget<Container>(shellFinder);
    final decoration = shell.decoration as BoxDecoration;
    final shellContext = tester.element(shellFinder);
    expect(
      decoration.color,
      Theme.of(shellContext).colorScheme.surfaceContainer,
    );
  });

  testWidgets('notes explorer follows workspace-like shell markers', (
    WidgetTester tester,
  ) async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(NotesPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('My Workspace'), findsOneWidget);
    expect(find.text('New Page'), findsOneWidget);
    expect(find.byKey(const Key('notes_floating_capsule')), findsNothing);
  });

  testWidgets(
    'notes shell keeps workspace header aligned and title placeholders',
    (WidgetTester tester) async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrapWithMaterial(NotesPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const Key('note_tab_manager'))).height,
        kNotesTopStripHeight,
      );
      expect(find.text('My Workspace'), findsOneWidget);
      expect(
        find.byKey(const Key('notes_detail_title_icon_placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_detail_add_icon_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_detail_add_image_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notes_detail_add_comment_button')),
        findsOneWidget,
      );

      final activeTabShell = tester.widget<Material>(
        find.byKey(const Key('note_tab_shell_note-1')),
      );
      final activeShape = activeTabShell.shape! as RoundedRectangleBorder;
      expect(activeShape.side, BorderSide.none);
    },
  );
}
