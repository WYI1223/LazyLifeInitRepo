import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/app/ui_slots/ui_slot_models.dart';

/// In-process UI slot registry.
class UiSlotRegistry {
  UiSlotRegistry({Iterable<UiSlotContribution> contributions = const []}) {
    for (final contribution in contributions) {
      register(contribution);
    }
  }

  final Map<String, UiSlotContribution> _contributionsById =
      <String, UiSlotContribution>{};

  /// Registers one contribution.
  ///
  /// Throws [UiSlotRegistryError] on duplicate or invalid identifiers.
  void register(UiSlotContribution contribution) {
    final contributionId = contribution.contributionId.trim();
    if (contributionId.isEmpty) {
      throw const UiSlotRegistryError(
        code: 'invalid_contribution_id',
        message: 'Contribution id must not be empty.',
      );
    }
    if (_contributionsById.containsKey(contributionId)) {
      throw UiSlotRegistryError(
        code: 'duplicate_contribution_id',
        message: 'Duplicate contribution id: $contributionId',
      );
    }

    final slotId = contribution.slotId.trim();
    if (slotId.isEmpty) {
      throw const UiSlotRegistryError(
        code: 'invalid_slot_id',
        message: 'Slot id must not be empty.',
      );
    }

    _contributionsById[contributionId] = UiSlotContribution(
      contributionId: contributionId,
      slotId: slotId,
      layer: contribution.layer,
      priority: contribution.priority,
      builder: contribution.builder,
      enabledWhen: contribution.enabledWhen,
      onMount: contribution.onMount,
      onDispose: contribution.onDispose,
    );
  }

  /// Resolves contributions for one slot/layer with deterministic ordering.
  List<UiSlotContribution> resolve({
    required String slotId,
    required UiSlotLayer layer,
    required UiSlotContext slotContext,
  }) {
    final normalizedSlotId = slotId.trim();
    final resolved = _contributionsById.values.where((contribution) {
      if (contribution.layer != layer) {
        return false;
      }
      if (contribution.slotId != normalizedSlotId) {
        return false;
      }
      try {
        return contribution.enabledWhen?.call(slotContext) ?? true;
      } catch (error, stackTrace) {
        _reportUiSlotResolveError(
          contribution: contribution,
          error: error,
          stackTrace: stackTrace,
          stage: 'enabled_when',
        );
        return false;
      }
    }).toList();

    resolved.sort((left, right) {
      final byPriority = right.priority.compareTo(left.priority);
      if (byPriority != 0) {
        return byPriority;
      }
      return left.contributionId.compareTo(right.contributionId);
    });
    return resolved;
  }

  /// Number of registered slot contributions.
  int get length => _contributionsById.length;
}

void _reportUiSlotResolveError({
  required UiSlotContribution contribution,
  required Object error,
  required StackTrace stackTrace,
  required String stage,
}) {
  debugPrint(
    '[ui_slots] resolve error ($stage) '
    '${contribution.slotId}/${contribution.contributionId}: $error',
  );
  assert(() {
    debugPrintStack(
      label:
          '[ui_slots] resolve stack ${contribution.slotId}/${contribution.contributionId}',
      stackTrace: stackTrace,
    );
    return true;
  }());
}
