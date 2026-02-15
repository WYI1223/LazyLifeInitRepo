import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/debug/log_reader.dart';
import 'package:lazynote_flutter/features/diagnostics/debug_logs_panel.dart';
import 'package:lazynote_flutter/features/diagnostics/log_line_meta.dart';

void main() {
  setUp(() {
    DebugLogsPanel.autoRefreshEnabled = false;
  });

  tearDown(() {
    DebugLogsPanel.autoRefreshEnabled = true;
  });

  testWidgets('queued refresh applies newest snapshot after in-flight load', (
    WidgetTester tester,
  ) async {
    final first = Completer<DebugLogSnapshot>();
    final second = Completer<DebugLogSnapshot>();
    var callCount = 0;

    Future<DebugLogSnapshot> loader() {
      callCount += 1;
      if (callCount == 1) {
        return first.future;
      }
      if (callCount == 2) {
        return second.future;
      }
      return Future.value(_snapshot('fallback snapshot'));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 640,
            child: DebugLogsPanel(snapshotLoader: loader),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Refresh'));
    await tester.pump();

    first.complete(_snapshot('older snapshot'));
    await tester.pump();
    await tester.pump();
    expect(callCount, 2);
    expect(find.textContaining('older snapshot'), findsOneWidget);

    second.complete(_snapshot('newest snapshot'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('newest snapshot'), findsOneWidget);
    expect(find.textContaining('older snapshot'), findsNothing);
  });

  testWidgets('coalesces overlapping refresh requests', (
    WidgetTester tester,
  ) async {
    final first = Completer<DebugLogSnapshot>();
    final second = Completer<DebugLogSnapshot>();
    var callCount = 0;

    Future<DebugLogSnapshot> loader() {
      callCount += 1;
      if (callCount == 1) {
        return first.future;
      }
      if (callCount == 2) {
        return second.future;
      }
      return Future.value(_snapshot('unexpected'));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 640,
            child: DebugLogsPanel(snapshotLoader: loader),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(callCount, 1);

    first.complete(_snapshot('first snapshot'));
    await tester.pump();
    await tester.pump();
    expect(callCount, 2);

    second.complete(_snapshot('coalesced snapshot'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('coalesced snapshot'), findsOneWidget);
    expect(callCount, 2);
  });

  // --- LogLineMeta unit tests ---

  test('LogLineMeta parses detailed_format line - INFO', () {
    const line =
        '[2026-02-15 10:23:45.123456 +00:00] INFO [lazynote_core::logging] src/logging.rs:100: event=app_start';
    final meta = LogLineMeta.parse(line);
    expect(meta.timestamp, equals('10:23:45.123'));
    expect(meta.level, equals('info'));
    expect(meta.message, equals('event=app_start'));
    expect(meta.raw, equals(line));
  });

  test('LogLineMeta parses detailed_format line - WARN with offset timezone', () {
    const line =
        '[2026-02-15 10:23:45.654321 +08:00] WARN [lazynote_core::search::fts] src/service.rs:42: event=slow_query';
    final meta = LogLineMeta.parse(line);
    expect(meta.timestamp, equals('10:23:45.654'));
    expect(meta.level, equals('warn'));
    expect(meta.message, equals('event=slow_query'));
  });

  test('LogLineMeta parses detailed_format line - ERROR', () {
    const line =
        '[2026-02-15 10:23:46.000001 +00:00] ERROR [lazynote_core::db::open] src/db.rs:7: event=panic_captured';
    final meta = LogLineMeta.parse(line);
    expect(meta.level, equals('error'));
    expect(meta.timestamp, equals('10:23:46.000'));
  });

  test('LogLineMeta parses legacy default_format line for level badge', () {
    const line =
        'INFO [lazynote_core::db::open] event=db_open module=db status=ok';
    final meta = LogLineMeta.parse(line);
    expect(meta.timestamp, isNull);
    expect(meta.level, equals('info'));
    expect(meta.message, equals('event=db_open module=db status=ok'));
    expect(meta.raw, equals(line));
  });

  test('LogLineMeta gracefully handles unrecognised format', () {
    const line = 'some plain unstructured text';
    final meta = LogLineMeta.parse(line);
    expect(meta.timestamp, isNull);
    expect(meta.level, isNull);
    expect(meta.message, equals(line));
    expect(meta.raw, equals(line));
  });

  test('LogLineMeta gracefully handles empty string', () {
    final meta = LogLineMeta.parse('');
    expect(meta.timestamp, isNull);
    expect(meta.level, isNull);
    expect(meta.message, equals(''));
  });

  // --- Level badge rendering widget tests ---

  testWidgets('debug panel renders level badge and timestamp for error line', (
    WidgetTester tester,
  ) async {
    const errorLine =
        '[2026-02-15 10:23:46.000001 +00:00] ERROR [lazynote_core::db::open] src/db.rs:7: event=panic_captured';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 640,
            child: DebugLogsPanel(
              snapshotLoader: () async => _snapshot(errorLine),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('ERROR'), findsWidgets);
    expect(find.textContaining('10:23:46.000'), findsWidgets);
    expect(find.textContaining('event=panic_captured'), findsWidgets);
  });

  testWidgets('debug panel renders fallback row for unrecognised log line', (
    WidgetTester tester,
  ) async {
    const plainLine = 'unstructured log output';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 640,
            child: DebugLogsPanel(
              snapshotLoader: () async => _snapshot(plainLine),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Full raw line should appear as the message when format is not recognised.
    expect(find.textContaining(plainLine), findsWidgets);
  });
}

DebugLogSnapshot _snapshot(String tailText) {
  return DebugLogSnapshot(
    logDir: r'C:\logs',
    files: const [],
    activeFile: null,
    tailText: tailText,
  );
}
