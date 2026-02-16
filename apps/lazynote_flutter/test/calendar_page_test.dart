import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/calendar/calendar_controller.dart';
import 'package:lazynote_flutter/features/calendar/calendar_page.dart';

void main() {
  const largeSize = Size(1200, 900);

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  rust_api.AtomListResponse successResponse(
    List<rust_api.AtomListItem> items,
  ) {
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

  testWidgets('renders page with sidebar and week grid', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async =>
          successResponse(const []),
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('calendar_page_root')), findsOneWidget);
    expect(find.byKey(const Key('calendar_mini_month')), findsOneWidget);
    expect(find.byKey(const Key('calendar_week_grid')), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
  });

  testWidgets('week navigation changes date range label', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async =>
          successResponse(const []),
      initialDate: DateTime(2026, 2, 15), // Sunday → week of Feb 9
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initial week: Feb 9 – 15, 2026
    final labelFinder = find.byKey(const Key('calendar_week_label'));
    expect(labelFinder, findsOneWidget);
    expect(find.textContaining('Feb 9'), findsOneWidget);

    // Navigate to next week
    await tester.tap(find.byKey(const Key('calendar_next_week_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Feb 16'), findsOneWidget);
  });

  testWidgets('error state renders error message', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async =>
          errorResponse('Database connection failed'),
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('calendar_error_state')), findsOneWidget);
    expect(find.textContaining('Database connection failed'), findsOneWidget);
  });

  testWidgets('back to workbench button fires callback', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var backPressed = false;
    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async =>
          successResponse(const []),
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
      onBackToWorkbench: () => backPressed = true,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const Key('calendar_back_to_workbench_button')),
    );
    expect(backPressed, isTrue);
  });

  testWidgets('createEvent triggers reload', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var rangeCallCount = 0;
    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async {
        rangeCallCount++;
        return successResponse(const []);
      },
      scheduleInvoker: ({
        required title,
        required startEpochMs,
        endEpochMs,
      }) async {
        return rust_api.EntryActionResponse(
          ok: true,
          atomId: 'new-evt-1',
          message: 'ok',
        );
      },
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final countBefore = rangeCallCount;
    await controller.createEvent(
      'Test event',
      DateTime(2026, 2, 16, 9, 0).millisecondsSinceEpoch,
      DateTime(2026, 2, 16, 10, 0).millisecondsSinceEpoch,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // createEvent should trigger loadWeek, increasing rangeCallCount
    expect(rangeCallCount, greaterThan(countBefore));
  });

  testWidgets('updateEvent triggers reload', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var rangeCallCount = 0;
    final controller = CalendarController(
      prepare: () async {},
      rangeInvoker: ({required startMs, required endMs, limit, offset}) async {
        rangeCallCount++;
        return successResponse(const []);
      },
      updateEventInvoker: ({
        required atomId,
        required startMs,
        required endMs,
      }) async {
        return rust_api.EntryActionResponse(
          ok: true,
          atomId: atomId,
          message: 'ok',
        );
      },
    );

    await tester.pumpWidget(wrapWithMaterial(CalendarPage(
      controller: controller,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final countBefore = rangeCallCount;
    await controller.updateEvent(
      'evt-1',
      DateTime(2026, 2, 16, 14, 0).millisecondsSinceEpoch,
      DateTime(2026, 2, 16, 15, 0).millisecondsSinceEpoch,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(rangeCallCount, greaterThan(countBefore));
  });
}
