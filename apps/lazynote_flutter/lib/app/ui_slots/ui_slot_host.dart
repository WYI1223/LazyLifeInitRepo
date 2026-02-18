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
      _invokeLifecycleSafely(
        contribution: contribution,
        stage: 'dispose',
        slotContext: widget.slotContext,
        callback: contribution.onDispose,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final contribution in _resolved) {
      final built = _buildContributionSafely(
        contribution: contribution,
        slotContext: widget.slotContext,
        context: context,
      );
      if (built == null) {
        continue;
      }
      return KeyedSubtree(
        key: ValueKey<String>(contribution.contributionId),
        child: built,
      );
    }
    return widget.fallbackBuilder(context);
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
        _invokeLifecycleSafely(
          contribution: contribution,
          stage: 'mount',
          slotContext: widget.slotContext,
          callback: contribution.onMount,
        );
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
        _invokeLifecycleSafely(
          contribution: contribution,
          stage: 'dispose',
          slotContext: widget.slotContext,
          callback: contribution.onDispose,
        );
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
      _invokeLifecycleSafely(
        contribution: contribution,
        stage: 'dispose',
        slotContext: widget.slotContext,
        callback: contribution.onDispose,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved.isEmpty) {
      return widget.fallbackBuilder?.call(context) ?? const SizedBox.shrink();
    }

    final children = <Widget>[];
    for (final contribution in _resolved) {
      final built = _buildContributionSafely(
        contribution: contribution,
        slotContext: widget.slotContext,
        context: context,
      );
      if (built == null) {
        continue;
      }
      children.add(
        KeyedSubtree(
          key: ValueKey<String>(contribution.contributionId),
          child: built,
        ),
      );
    }
    if (children.isEmpty) {
      return widget.fallbackBuilder?.call(context) ?? const SizedBox.shrink();
    }
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
        _invokeLifecycleSafely(
          contribution: contribution,
          stage: 'mount',
          slotContext: widget.slotContext,
          callback: contribution.onMount,
        );
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
        _invokeLifecycleSafely(
          contribution: contribution,
          stage: 'dispose',
          slotContext: widget.slotContext,
          callback: contribution.onDispose,
        );
      }
    }
  }
}

Widget? _buildContributionSafely({
  required UiSlotContribution contribution,
  required UiSlotContext slotContext,
  required BuildContext context,
}) {
  try {
    return contribution.builder(context, slotContext);
  } catch (error, stackTrace) {
    _reportUiSlotHostError(
      contribution: contribution,
      error: error,
      stackTrace: stackTrace,
      stage: 'build',
    );
    return null;
  }
}

void _invokeLifecycleSafely({
  required UiSlotContribution contribution,
  required String stage,
  required UiSlotContext slotContext,
  required UiSlotLifecycleCallback? callback,
}) {
  if (callback == null) {
    return;
  }
  try {
    callback(slotContext);
  } catch (error, stackTrace) {
    _reportUiSlotHostError(
      contribution: contribution,
      error: error,
      stackTrace: stackTrace,
      stage: stage,
    );
  }
}

void _reportUiSlotHostError({
  required UiSlotContribution contribution,
  required Object error,
  required StackTrace stackTrace,
  required String stage,
}) {
  debugPrint(
    '[ui_slots] host error ($stage) '
    '${contribution.slotId}/${contribution.contributionId}: $error',
  );
  assert(() {
    debugPrintStack(
      label:
          '[ui_slots] host stack ${contribution.slotId}/${contribution.contributionId}',
      stackTrace: stackTrace,
    );
    return true;
  }());
}
