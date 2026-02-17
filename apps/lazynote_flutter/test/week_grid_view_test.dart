import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/calendar/week_grid_view.dart';

void main() {
  const largeSize = Size(1200, 900);

  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 800, height: 700, child: child)),
    );
  }

  rust_api.AtomListItem makeEvent({
    required String id,
    required String content,
    required int startMs,
    required int endMs,
    String? previewText,
  }) {
    return rust_api.AtomListItem(
      atomId: id,
      kind: 'event',
      content: content,
      previewText: previewText,
      tags: const [],
      startAt: startMs,
      endAt: endMs,
      updatedAt: startMs,
    );
  }

  testWidgets('day headers show correct dates for given weekStart', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Monday Feb 9, 2026
    final weekStart = DateTime(2026, 2, 9);

    await tester.pumpWidget(
      wrapWithMaterial(WeekGridView(weekStart: weekStart, events: const [])),
    );
    await tester.pump();

    expect(find.byKey(const Key('week_grid_day_headers')), findsOneWidget);

    // Check day abbreviations are present
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Tue'), findsOneWidget);
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Thu'), findsOneWidget);
    expect(find.text('Fri'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);

    // Check date numbers: Feb 9–15
    expect(find.text('9'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('event block renders with correct preview text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final weekStart = DateTime(2026, 2, 9);
    // Event on Tuesday Feb 10, 9:00–10:00
    final tuesdayStart = DateTime(2026, 2, 10, 9, 0).millisecondsSinceEpoch;
    final tuesdayEnd = DateTime(2026, 2, 10, 10, 0).millisecondsSinceEpoch;

    final events = [
      makeEvent(
        id: 'evt-1',
        content: 'Team standup meeting\nWith agenda',
        previewText: 'Team standup meeting',
        startMs: tuesdayStart,
        endMs: tuesdayEnd,
      ),
    ];

    await tester.pumpWidget(
      wrapWithMaterial(WeekGridView(weekStart: weekStart, events: events)),
    );
    await tester.pump();

    // Event block should exist with its key
    expect(find.byKey(const Key('event_block_evt-1_day1')), findsOneWidget);

    // Preview text should render
    expect(find.text('Team standup meeting'), findsOneWidget);
  });

  testWidgets('time axis shows hour labels', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final weekStart = DateTime(2026, 2, 9);

    await tester.pumpWidget(
      wrapWithMaterial(WeekGridView(weekStart: weekStart, events: const [])),
    );
    await tester.pump();

    expect(find.byKey(const Key('week_grid_time_axis')), findsOneWidget);

    // First visible hour label
    expect(find.text('00:00'), findsOneWidget);
    // A mid-day label
    expect(find.text('12:00'), findsOneWidget);
  });

  testWidgets('grid lines are painted', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final weekStart = DateTime(2026, 2, 9);

    await tester.pumpWidget(
      wrapWithMaterial(WeekGridView(weekStart: weekStart, events: const [])),
    );
    await tester.pump();

    expect(find.byKey(const Key('week_grid_lines')), findsOneWidget);
  });

  testWidgets('event uses content first line when previewText is null', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(largeSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final weekStart = DateTime(2026, 2, 9);
    final mondayStart = DateTime(2026, 2, 9, 14, 0).millisecondsSinceEpoch;
    final mondayEnd = DateTime(2026, 2, 9, 15, 30).millisecondsSinceEpoch;

    final events = [
      makeEvent(
        id: 'evt-2',
        content: 'Design review\nSecond line ignored',
        startMs: mondayStart,
        endMs: mondayEnd,
      ),
    ];

    await tester.pumpWidget(
      wrapWithMaterial(WeekGridView(weekStart: weekStart, events: events)),
    );
    await tester.pump();

    expect(find.byKey(const Key('event_block_evt-2_day0')), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
  });
}
