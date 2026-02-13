import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/app.dart';
import 'package:lazynote_flutter/features/diagnostics/debug_logs_panel.dart';

void main() {
  setUp(() {
    DebugLogsPanel.autoRefreshEnabled = false;
  });

  tearDown(() {
    DebugLogsPanel.autoRefreshEnabled = true;
  });

  testWidgets('boots to workbench page', (WidgetTester tester) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('LazyNote Workbench'), findsOneWidget);
    expect(find.text('Feature Validation Window'), findsOneWidget);
    expect(find.text('Draft Input'), findsOneWidget);
  });
}
