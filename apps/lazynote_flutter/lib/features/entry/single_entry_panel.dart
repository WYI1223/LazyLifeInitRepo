import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazynote_flutter/core/settings/local_settings_store.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';
import 'package:lazynote_flutter/features/search/search_results_view.dart';

/// Single Entry input panel rendered inside Workbench left pane.
class SingleEntryPanel extends StatelessWidget {
  const SingleEntryPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  /// State/controller that drives parser/search/command interactions.
  final SingleEntryController controller;

  /// Callback that hides this panel from Workbench host.
  final VoidCallback onClose;

  Color _statusColor(BuildContext context, EntryStatusMessageType? type) {
    return switch (type) {
      EntryStatusMessageType.error => Theme.of(context).colorScheme.error,
      EntryStatusMessageType.success => Colors.green.shade700,
      EntryStatusMessageType.info || null => Colors.grey.shade700,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissEntryIntent(),
      },
      child: Actions(
        actions: {
          _DismissEntryIntent: CallbackAction<_DismissEntryIntent>(
            onInvoke: (_) {
              controller.handleEscapePressed();
              return null;
            },
          ),
        },
        child: Focus(
          canRequestFocus: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final statusMessage =
                  controller.state.statusMessage?.text ??
                  'Single Entry idle. Type to preview route.';
              final sendColor = controller.hasInput
                  ? Colors.grey.shade800
                  : Colors.grey.shade600;
              final canPressSend = !controller.isCommandSubmitting;
              final uiTuning = LocalSettingsStore.entryUiTuning;
              final isExpanded = controller.shouldExpandUnifiedPanel;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Single Entry',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        key: const Key('single_entry_close_button'),
                        onPressed: onClose,
                        tooltip: 'Hide Single Entry',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    key: const Key('single_entry_unified_panel'),
                    duration: Duration(milliseconds: uiTuning.animationMs),
                    curve: Curves.easeOutCubic,
                    height: isExpanded
                        ? uiTuning.expandedMaxHeight
                        : uiTuning.collapsedHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 40,
                          spreadRadius: 0,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          // Why: keep input baseline and right icons visually
                          // centered for desktop while staying within collapsed
                          // height budget.
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('single_entry_input'),
                                  focusNode: controller.inputFocusNode,
                                  controller: controller.textController,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.only(
                                      top: 11,
                                      bottom: 8,
                                    ),
                                    hintText: 'Ask me anything...',
                                  ),
                                  textInputAction: TextInputAction.search,
                                  onChanged: controller.handleInputChanged,
                                  onSubmitted: (_) =>
                                      controller.handleDetailAction(),
                                ),
                              ),
                              Padding(
                                // Why: synchronize icon baseline with lowered
                                // text field to avoid top-heavy alignment.
                                padding: const EdgeInsets.only(top: 4),
                                child: IconButton(
                                  tooltip: 'Microphone',
                                  onPressed: () {},
                                  icon: Icon(
                                    Icons.mic,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              Padding(
                                // Why: synchronize icon baseline with lowered
                                // text field to avoid top-heavy alignment.
                                padding: const EdgeInsets.only(top: 4),
                                child: IconButton(
                                  key: const Key('single_entry_send_button'),
                                  tooltip: 'Open details',
                                  onPressed: canPressSend
                                      ? controller.handleDetailAction
                                      : null,
                                  icon: Icon(
                                    Icons.send_outlined,
                                    color: sendColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isExpanded) ...[
                          const Divider(
                            height: 1,
                            thickness: 0.6,
                            indent: 16,
                            endIndent: 16,
                          ),
                          Expanded(
                            child: controller.isSearchIntentActive
                                ? Column(
                                    children: [
                                      _SearchKindFilterBar(
                                        selected: controller.searchKindFilter,
                                        onSelected:
                                            controller.setSearchKindFilter,
                                      ),
                                      const Divider(
                                        height: 1,
                                        thickness: 0.6,
                                        indent: 16,
                                        endIndent: 16,
                                      ),
                                      Expanded(
                                        child: SearchResultsView(
                                          visible: true,
                                          isLoading: controller.isSearchLoading,
                                          errorMessage:
                                              controller.searchErrorMessage,
                                          items: controller.searchItems,
                                          appliedLimit:
                                              controller.searchAppliedLimit,
                                          onItemTap:
                                              controller.openSearchResultDetail,
                                        ),
                                      ),
                                    ],
                                  )
                                : _EntryResultPlaceholder(
                                    text: controller.hasInput
                                        ? 'Type plain text for realtime search, or press Send to run command detail.'
                                        : 'Focus input to start searching.',
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    statusMessage,
                    key: const Key('single_entry_status'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _statusColor(
                        context,
                        controller.state.statusMessage?.type,
                      ),
                    ),
                  ),
                  if (controller.visibleDetail case final detail?) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          detail,
                          key: const Key('single_entry_detail'),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EntryResultPlaceholder extends StatelessWidget {
  const _EntryResultPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('single_entry_non_search_placeholder'),
      children: [
        ListTile(
          leading: Icon(Icons.stream_outlined, color: Colors.grey.shade600),
          title: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          dense: true,
        ),
      ],
    );
  }
}

class _DismissEntryIntent extends Intent {
  /// Local shortcut intent used by Esc to clear/close entry state.
  const _DismissEntryIntent();
}

class _SearchKindFilterBar extends StatelessWidget {
  const _SearchKindFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final EntrySearchKindFilter selected;
  final ValueChanged<EntrySearchKindFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = EntrySearchKindFilter.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final option in options)
            ChoiceChip(
              key: Key('single_entry_search_kind_${option.label}'),
              label: Text(option.label.toUpperCase()),
              selected: selected == option,
              onSelected: (_) => onSelected(option),
            ),
        ],
      ),
    );
  }
}
