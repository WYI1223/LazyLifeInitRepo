import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/tasks/tasks_controller.dart';
import 'package:lazynote_flutter/features/tasks/tasks_page.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  rust_api.AtomListItem atomItem({
    required String atomId,
    required String content,
    String? previewText,
    String? taskStatus,
    int? startAt,
    int? endAt,
  }) {
    return rust_api.AtomListItem(
      atomId: atomId,
      kind: 'note',
      content: content,
      previewText: previewText,
      previewImage: null,
      tags: const [],
      startAt: startAt,
      endAt: endAt,
      taskStatus: taskStatus,
      updatedAt: 1000,
    );
  }

  rust_api.AtomListResponse successResponse(List<rust_api.AtomListItem> items) {
    return rust_api.AtomListResponse(
      ok: true,
      errorCode: null,
      message: 'ok',
      items: items,
      appliedLimit: 50,
    );
  }

  rust_api.AtomListResponse errorResponse(String message) {
    return rust_api.AtomListResponse(
      ok: false,
      errorCode: 'db_error',
      message: message,
      items: const [],
      appliedLimit: 50,
    );
  }

  testWidgets('renders three section cards after successful load', (
    WidgetTester tester,
  ) async {
    final controller = TasksController(
      prepare: () async {},
      inboxInvoker: ({limit, offset}) async => successResponse([
        atomItem(atomId: 'inbox-1', content: 'Reply to emails'),
      ]),
      todayInvoker: ({required bodMs, required eodMs, limit, offset}) async =>
          successResponse([
            atomItem(
              atomId: 'today-1',
              content: 'Morning standup',
              taskStatus: 'done',
            ),
          ]),
      upcomingInvoker: ({required eodMs, limit, offset}) async =>
          successResponse([
            atomItem(
              atomId: 'upcoming-1',
              content: 'Team Lunch',
              startAt: DateTime.now()
                  .add(const Duration(days: 2))
                  .millisecondsSinceEpoch,
            ),
          ]),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(TasksPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('tasks_inbox_card')), findsOneWidget);
    expect(find.byKey(const Key('tasks_today_card')), findsOneWidget);
    expect(find.byKey(const Key('tasks_upcoming_card')), findsOneWidget);
    expect(find.text('Reply to emails'), findsOneWidget);
    expect(find.text('Morning standup'), findsOneWidget);
    expect(find.text('Team Lunch'), findsOneWidget);
  });

  testWidgets('shows error state when section load fails', (
    WidgetTester tester,
  ) async {
    final controller = TasksController(
      prepare: () async {},
      inboxInvoker: ({limit, offset}) async =>
          errorResponse('Inbox DB failure'),
      todayInvoker: ({required bodMs, required eodMs, limit, offset}) async =>
          successResponse(const []),
      upcomingInvoker: ({required eodMs, limit, offset}) async =>
          successResponse(const []),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(TasksPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.inboxPhase, TasksPhase.error);
    expect(find.textContaining('Inbox DB failure'), findsOneWidget);
  });

  testWidgets('toggle status removes item from section', (
    WidgetTester tester,
  ) async {
    final statusCalls = <({String atomId, String? status})>[];
    final controller = TasksController(
      prepare: () async {},
      inboxInvoker: ({limit, offset}) async => successResponse(const []),
      todayInvoker: ({required bodMs, required eodMs, limit, offset}) async =>
          successResponse([atomItem(atomId: 'task-1', content: 'Review code')]),
      upcomingInvoker: ({required eodMs, limit, offset}) async =>
          successResponse(const []),
      statusInvoker: ({required atomId, status}) async {
        statusCalls.add((atomId: atomId, status: status));
        return const rust_api.EntryActionResponse(
          ok: true,
          atomId: 'task-1',
          message: 'ok',
        );
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(TasksPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Review code'), findsOneWidget);

    await controller.toggleStatus('task-1', null);
    await tester.pump();

    expect(statusCalls.length, 1);
    expect(statusCalls.first.status, 'done');
    expect(find.text('Review code'), findsNothing);
  });

  testWidgets('inline inbox create shows text field and submits', (
    WidgetTester tester,
  ) async {
    final createCompleter = Completer<rust_api.EntryActionResponse>();
    int inboxLoadCount = 0;
    final controller = TasksController(
      prepare: () async {},
      inboxInvoker: ({limit, offset}) async {
        inboxLoadCount++;
        if (inboxLoadCount > 1) {
          return successResponse([
            atomItem(atomId: 'new-1', content: 'New task'),
          ]);
        }
        return successResponse(const []);
      },
      todayInvoker: ({required bodMs, required eodMs, limit, offset}) async =>
          successResponse(const []),
      upcomingInvoker: ({required eodMs, limit, offset}) async =>
          successResponse(const []),
      createInvoker: ({required content}) => createCompleter.future,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(TasksPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('tasks_inbox_add_button')));
    await tester.pump();

    expect(find.byKey(const Key('tasks_inbox_text_field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('tasks_inbox_text_field')),
      'New task',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    createCompleter.complete(
      const rust_api.EntryActionResponse(
        ok: true,
        atomId: 'new-1',
        message: 'ok',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('New task'), findsOneWidget);
  });

  testWidgets('reload button triggers loadAll', (WidgetTester tester) async {
    int loadCount = 0;
    final controller = TasksController(
      prepare: () async {},
      inboxInvoker: ({limit, offset}) async {
        loadCount++;
        return successResponse(const []);
      },
      todayInvoker: ({required bodMs, required eodMs, limit, offset}) async =>
          successResponse(const []),
      upcomingInvoker: ({required eodMs, limit, offset}) async =>
          successResponse(const []),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapWithMaterial(TasksPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();
    expect(loadCount, 1);

    await tester.tap(find.byKey(const Key('tasks_reload_button')));
    await tester.pump();
    await tester.pump();

    expect(loadCount, 2);
  });
}
