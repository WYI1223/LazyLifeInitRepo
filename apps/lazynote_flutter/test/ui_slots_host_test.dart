import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_host.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets(
    'list host renders deterministic slot order by priority then id',
    (tester) async {
      final registry = UiSlotRegistry(
        contributions: <UiSlotContribution>[
          UiSlotContribution(
            contributionId: 'test.slot.b',
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            priority: 10,
            builder: (context, slotContext) => const Text('B'),
          ),
          UiSlotContribution(
            contributionId: 'test.slot.a',
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            priority: 10,
            builder: (context, slotContext) => const Text('A'),
          ),
          UiSlotContribution(
            contributionId: 'test.slot.top',
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            priority: 20,
            builder: (context, slotContext) => const Text('TOP'),
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          UiSlotListHost(
            registry: registry,
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            slotContext: const UiSlotContext(),
            listBuilder: (context, children) => Column(children: children),
          ),
        ),
      );

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(labels, <String>['TOP', 'A', 'B']);
    },
  );

  testWidgets('list host renders fallback when slot has no contribution', (
    tester,
  ) async {
    final registry = UiSlotRegistry();
    await tester.pumpWidget(
      _wrap(
        UiSlotListHost(
          registry: registry,
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          slotContext: const UiSlotContext(),
          listBuilder: (context, children) => Column(children: children),
          fallbackBuilder: (context) => const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('view host picks highest-priority contribution and falls back', (
    tester,
  ) async {
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.view.low',
          slotId: UiSlotIds.workbenchSectionView,
          layer: UiSlotLayer.view,
          priority: 10,
          builder: (context, slotContext) => const Text('low'),
        ),
        UiSlotContribution(
          contributionId: 'test.view.high',
          slotId: UiSlotIds.workbenchSectionView,
          layer: UiSlotLayer.view,
          priority: 20,
          builder: (context, slotContext) => const Text('high'),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        UiSlotViewHost(
          registry: registry,
          slotId: UiSlotIds.workbenchSectionView,
          slotContext: const UiSlotContext(),
          fallbackBuilder: (context) => const Text('fallback'),
        ),
      ),
    );
    expect(find.text('high'), findsOneWidget);
    expect(find.text('low'), findsNothing);
    expect(find.text('fallback'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        UiSlotViewHost(
          registry: UiSlotRegistry(),
          slotId: UiSlotIds.workbenchSectionView,
          slotContext: const UiSlotContext(),
          fallbackBuilder: (context) => const Text('fallback'),
        ),
      ),
    );
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('slot host lifecycle callbacks run on mount and dispose', (
    tester,
  ) async {
    final events = <String>[];
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.lifecycle',
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          priority: 10,
          enabledWhen: (slotContext) =>
              slotContext.read<bool>('enabled') ?? false,
          onMount: (slotContext) => events.add('mount'),
          onDispose: (slotContext) => events.add('dispose'),
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ],
    );

    Widget build(bool enabled) {
      return _wrap(
        UiSlotListHost(
          registry: registry,
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          slotContext: UiSlotContext({'enabled': enabled}),
          listBuilder: (context, children) => Column(children: children),
        ),
      );
    }

    await tester.pumpWidget(build(true));
    expect(events, <String>['mount']);

    await tester.pumpWidget(build(true));
    expect(events, <String>['mount']);

    await tester.pumpWidget(build(false));
    expect(events, <String>['mount', 'dispose']);
  });

  test('registry rejects duplicate contribution id', () {
    final registry = UiSlotRegistry();
    registry.register(
      UiSlotContribution(
        contributionId: 'test.dup',
        slotId: UiSlotIds.workbenchHomeWidgets,
        layer: UiSlotLayer.homeWidget,
        priority: 1,
        builder: (context, slotContext) => const SizedBox.shrink(),
      ),
    );

    expect(
      () => registry.register(
        UiSlotContribution(
          contributionId: 'test.dup',
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          priority: 2,
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ),
      throwsA(
        isA<UiSlotRegistryError>().having(
          (error) => error.code,
          'code',
          'duplicate_contribution_id',
        ),
      ),
    );
  });
}
