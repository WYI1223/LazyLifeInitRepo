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

  testWidgets(
    'list host isolates builder failures and keeps healthy contributions',
    (tester) async {
      final registry = UiSlotRegistry(
        contributions: <UiSlotContribution>[
          UiSlotContribution(
            contributionId: 'test.slot.broken',
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            priority: 20,
            builder: (context, slotContext) {
              throw StateError('broken builder');
            },
          ),
          UiSlotContribution(
            contributionId: 'test.slot.healthy',
            slotId: UiSlotIds.workbenchHomeWidgets,
            layer: UiSlotLayer.homeWidget,
            priority: 10,
            builder: (context, slotContext) => const Text('healthy'),
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

      expect(find.text('healthy'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

  testWidgets(
    'view host skips broken contribution and renders next candidate',
    (tester) async {
      final registry = UiSlotRegistry(
        contributions: <UiSlotContribution>[
          UiSlotContribution(
            contributionId: 'test.view.broken',
            slotId: UiSlotIds.workbenchSectionView,
            layer: UiSlotLayer.view,
            priority: 20,
            builder: (context, slotContext) {
              throw StateError('broken view builder');
            },
          ),
          UiSlotContribution(
            contributionId: 'test.view.safe',
            slotId: UiSlotIds.workbenchSectionView,
            layer: UiSlotLayer.view,
            priority: 10,
            builder: (context, slotContext) => const Text('safe'),
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

      expect(find.text('safe'), findsOneWidget);
      expect(find.text('fallback'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('slot host isolates lifecycle callback failures', (tester) async {
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.lifecycle.broken',
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          priority: 10,
          onMount: (slotContext) {
            throw StateError('mount failure');
          },
          onDispose: (slotContext) {
            throw StateError('dispose failure');
          },
          builder: (context, slotContext) => const Text('lifecycle-safe'),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        UiSlotListHost(
          registry: registry,
          slotId: UiSlotIds.workbenchHomeBlocks,
          layer: UiSlotLayer.contentBlock,
          slotContext: const UiSlotContext(),
          listBuilder: (context, children) => Column(children: children),
        ),
      ),
    );
    expect(find.text('lifecycle-safe'), findsOneWidget);

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    expect(tester.takeException(), isNull);
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

  test('registry rejects blank contribution id', () {
    final registry = UiSlotRegistry();
    expect(
      () => registry.register(
        UiSlotContribution(
          contributionId: '   ',
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          priority: 1,
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ),
      throwsA(
        isA<UiSlotRegistryError>().having(
          (error) => error.code,
          'code',
          'invalid_contribution_id',
        ),
      ),
    );
  });

  test('registry rejects blank slot id', () {
    final registry = UiSlotRegistry();
    expect(
      () => registry.register(
        UiSlotContribution(
          contributionId: 'test.invalid.slot',
          slotId: '   ',
          layer: UiSlotLayer.homeWidget,
          priority: 1,
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ),
      throwsA(
        isA<UiSlotRegistryError>().having(
          (error) => error.code,
          'code',
          'invalid_slot_id',
        ),
      ),
    );
  });

  test('registry resolve returns empty for unknown slot id', () {
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.known.slot',
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          priority: 1,
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ],
    );

    final resolved = registry.resolve(
      slotId: 'slot.not.registered',
      layer: UiSlotLayer.homeWidget,
      slotContext: const UiSlotContext(),
    );
    expect(resolved, isEmpty);
  });

  test('registry resolve skips contribution when enabledWhen throws', () {
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.resolve.broken',
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          priority: 10,
          enabledWhen: (slotContext) {
            throw StateError('enabledWhen failure');
          },
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
        UiSlotContribution(
          contributionId: 'test.resolve.healthy',
          slotId: UiSlotIds.workbenchHomeWidgets,
          layer: UiSlotLayer.homeWidget,
          priority: 1,
          builder: (context, slotContext) => const SizedBox.shrink(),
        ),
      ],
    );

    final resolved = registry.resolve(
      slotId: UiSlotIds.workbenchHomeWidgets,
      layer: UiSlotLayer.homeWidget,
      slotContext: const UiSlotContext(),
    );

    expect(resolved.map((item) => item.contributionId), <String>[
      'test.resolve.healthy',
    ]);
  });

  testWidgets('view host updates when slot id changes', (tester) async {
    final registry = UiSlotRegistry(
      contributions: <UiSlotContribution>[
        UiSlotContribution(
          contributionId: 'test.view.slot_a',
          slotId: 'slot.a',
          layer: UiSlotLayer.view,
          priority: 10,
          builder: (context, slotContext) => const Text('slot-a'),
        ),
        UiSlotContribution(
          contributionId: 'test.view.slot_b',
          slotId: 'slot.b',
          layer: UiSlotLayer.view,
          priority: 10,
          builder: (context, slotContext) => const Text('slot-b'),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        UiSlotViewHost(
          registry: registry,
          slotId: 'slot.a',
          slotContext: const UiSlotContext(),
          fallbackBuilder: (context) => const Text('fallback'),
        ),
      ),
    );
    expect(find.text('slot-a'), findsOneWidget);
    expect(find.text('slot-b'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        UiSlotViewHost(
          registry: registry,
          slotId: 'slot.b',
          slotContext: const UiSlotContext(),
          fallbackBuilder: (context) => const Text('fallback'),
        ),
      ),
    );
    expect(find.text('slot-a'), findsNothing);
    expect(find.text('slot-b'), findsOneWidget);
  });
}
