import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/app.dart';

void main() {
  testWidgets('boots to workbench page', (WidgetTester tester) async {
    await tester.pumpWidget(const LazyNoteApp());
    await tester.pumpAndSettle();

    expect(find.text('LazyNote Workbench'), findsOneWidget);
    expect(find.text('Feature Validation Window'), findsOneWidget);
    expect(find.text('Draft Input'), findsOneWidget);
  });
}
