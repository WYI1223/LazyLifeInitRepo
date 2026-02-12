import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/rust_bridge.dart';
import 'package:lazynote_flutter/main.dart';

void main() {
  testWidgets('shows rust health check result', (WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(
        loadRustHealth: () async =>
            const RustHealthSnapshot(ping: 'pong', coreVersion: '0.1.0'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Rust bridge connected'), findsOneWidget);
    expect(find.text('ping: pong'), findsOneWidget);
    expect(find.text('coreVersion: 0.1.0'), findsOneWidget);
  });

  testWidgets('shows error and recovers on retry', (WidgetTester tester) async {
    var attempts = 0;
    Future<RustHealthSnapshot> flakyLoader() async {
      attempts += 1;
      if (attempts == 1) {
        throw Exception('boom');
      }
      return const RustHealthSnapshot(ping: 'pong', coreVersion: '0.1.1');
    }

    await tester.pumpWidget(MyApp(loadRustHealth: flakyLoader));
    await tester.pumpAndSettle();

    expect(find.text('Rust bridge initialization failed'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Rust bridge connected'), findsOneWidget);
    expect(find.text('ping: pong'), findsOneWidget);
    expect(find.text('coreVersion: 0.1.1'), findsOneWidget);
    expect(attempts, 2);
  });
}
