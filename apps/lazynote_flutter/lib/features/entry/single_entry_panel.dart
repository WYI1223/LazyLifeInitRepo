import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';

/// Single Entry input panel rendered inside Workbench left pane.
class SingleEntryPanel extends StatelessWidget {
  const SingleEntryPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final SingleEntryController controller;
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final statusMessage =
            controller.state.statusMessage?.text ??
            'Single Entry idle. Type to preview route.';
        final sendColor = controller.hasInput
            ? Colors.blue
            : Colors.grey.shade600;

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
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('single_entry_input'),
                      focusNode: controller.inputFocusNode,
                      controller: controller.textController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Ask me anything...',
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: controller.handleInputChanged,
                      onSubmitted: (_) => controller.handleDetailAction(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Microphone',
                    onPressed: null,
                    icon: Icon(Icons.mic, color: Colors.grey.shade600),
                  ),
                  IconButton(
                    key: const Key('single_entry_send_button'),
                    tooltip: 'Open details',
                    onPressed: controller.handleDetailAction,
                    icon: Icon(Icons.send_outlined, color: sendColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              statusMessage,
              key: const Key('single_entry_status'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    );
  }
}
