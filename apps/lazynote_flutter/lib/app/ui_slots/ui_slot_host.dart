import 'package:flutter/material.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_registry.dart';

/// Builder used by multi-item slot host.
typedef UiSlotListBuilder =
    Widget Function(BuildContext context, List<Widget> children);

/// View-slot host that renders the highest-priority contribution.
class UiSlotViewHost extends StatefulWidget {
  const UiSlotViewHost({
    super.key,
    required this.registry,
    required this.slotId,
    required this.slotContext,
    required this.fallbackBuilder,
  });

  final UiSlotRegistry registry;
  final String slotId;
  final UiSlotContext slotContext;
  final WidgetBuilder fallbackBuilder;

  @override
  State<UiSlotViewHost> createState() => _UiSlotViewHostState();
}

class _UiSlotViewHostState extends State<UiSlotViewHost> {
  List<UiSlotContribution> _resolved = const <UiSlotContribution>[];

  @override
  void initState() {
    super.initState();
    _resolved = _resolve();
    _mountAdded(previous: const <UiSlotContribution>[], current: _resolved);
  }

  @override
  void didUpdateWidget(covariant UiSlotViewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextResolved = _resolve();
    _disposeRemoved(previous: _resolved, current: nextResolved);
    _mountAdded(previous: _resolved, current: nextResolved);
    _resolved = nextResolved;
  }

  @override
  void dispose() {
    for (final contribution in _resolved) {
      contribution.onDispose?.call(widget.slotContext);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _resolved.isEmpty ? null : _resolved.first;
    if (selected == null) {
      return widget.fallbackBuilder(context);
    }
    return KeyedSubtree(
      key: ValueKey<String>(selected.contributionId),
      child: selected.builder(context, widget.slotContext),
    );
  }

  List<UiSlotContribution> _resolve() {
    return widget.registry.resolve(
      slotId: widget.slotId,
      layer: UiSlotLayer.view,
      slotContext: widget.slotContext,
    );
  }

  void _mountAdded({
    required List<UiSlotContribution> previous,
    required List<UiSlotContribution> current,
  }) {
    final previousIds = previous.map((item) => item.contributionId).toSet();
    for (final contribution in current) {
      if (!previousIds.contains(contribution.contributionId)) {
        contribution.onMount?.call(widget.slotContext);
      }
    }
  }

  void _disposeRemoved({
    required List<UiSlotContribution> previous,
    required List<UiSlotContribution> current,
  }) {
    final currentIds = current.map((item) => item.contributionId).toSet();
    for (final contribution in previous) {
      if (!currentIds.contains(contribution.contributionId)) {
        contribution.onDispose?.call(widget.slotContext);
      }
    }
  }
}

/// Multi-item slot host for `content_block|side_panel|home_widget` layers.
class UiSlotListHost extends StatefulWidget {
  const UiSlotListHost({
    super.key,
    required this.registry,
    required this.slotId,
    required this.layer,
    required this.slotContext,
    required this.listBuilder,
    this.fallbackBuilder,
  });

  final UiSlotRegistry registry;
  final String slotId;
  final UiSlotLayer layer;
  final UiSlotContext slotContext;
  final UiSlotListBuilder listBuilder;
  final WidgetBuilder? fallbackBuilder;

  @override
  State<UiSlotListHost> createState() => _UiSlotListHostState();
}

class _UiSlotListHostState extends State<UiSlotListHost> {
  List<UiSlotContribution> _resolved = const <UiSlotContribution>[];

  @override
  void initState() {
    super.initState();
    _resolved = _resolve();
    _mountAdded(previous: const <UiSlotContribution>[], current: _resolved);
  }

  @override
  void didUpdateWidget(covariant UiSlotListHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextResolved = _resolve();
    _disposeRemoved(previous: _resolved, current: nextResolved);
    _mountAdded(previous: _resolved, current: nextResolved);
    _resolved = nextResolved;
  }

  @override
  void dispose() {
    for (final contribution in _resolved) {
      contribution.onDispose?.call(widget.slotContext);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved.isEmpty) {
      return widget.fallbackBuilder?.call(context) ?? const SizedBox.shrink();
    }

    final children = _resolved
        .map(
          (contribution) => KeyedSubtree(
            key: ValueKey<String>(contribution.contributionId),
            child: contribution.builder(context, widget.slotContext),
          ),
        )
        .toList(growable: false);
    return widget.listBuilder(context, children);
  }

  List<UiSlotContribution> _resolve() {
    return widget.registry.resolve(
      slotId: widget.slotId,
      layer: widget.layer,
      slotContext: widget.slotContext,
    );
  }

  void _mountAdded({
    required List<UiSlotContribution> previous,
    required List<UiSlotContribution> current,
  }) {
    final previousIds = previous.map((item) => item.contributionId).toSet();
    for (final contribution in current) {
      if (!previousIds.contains(contribution.contributionId)) {
        contribution.onMount?.call(widget.slotContext);
      }
    }
  }

  void _disposeRemoved({
    required List<UiSlotContribution> previous,
    required List<UiSlotContribution> current,
  }) {
    final currentIds = current.map((item) => item.contributionId).toSet();
    for (final contribution in previous) {
      if (!currentIds.contains(contribution.contributionId)) {
        contribution.onDispose?.call(widget.slotContext);
      }
    }
  }
}
