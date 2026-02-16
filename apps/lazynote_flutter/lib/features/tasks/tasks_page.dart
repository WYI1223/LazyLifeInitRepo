import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/tasks/tasks_controller.dart';
import 'package:lazynote_flutter/features/tasks/tasks_section_card.dart';
import 'package:lazynote_flutter/features/tasks/tasks_style.dart';

/// Tasks feature page mounted in Workbench left pane (PR-0011B).
///
/// Three equal-width section cards: Inbox, Today, Upcoming.
/// Inbox supports inline note creation via a text input row.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.controller, this.onBackToWorkbench});

  /// Optional external controller for tests.
  final TasksController? controller;

  /// Optional callback that returns to Workbench home section.
  final VoidCallback? onBackToWorkbench;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final TasksController _controller;
  late final bool _ownsController;
  final TextEditingController _inboxInputController = TextEditingController();
  bool _showInboxInput = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TasksController();
    _ownsController = widget.controller == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.loadAll();
    });
  }

  @override
  void dispose() {
    _inboxInputController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _toggleInboxInput() {
    setState(() {
      _showInboxInput = !_showInboxInput;
      if (!_showInboxInput) {
        _inboxInputController.clear();
      }
    });
  }

  Future<void> _submitInboxItem() async {
    final text = _inboxInputController.text;
    if (text.trim().isEmpty) return;
    final success = await _controller.createInboxItem(text);
    if (success && mounted) {
      _inboxInputController.clear();
      setState(() {
        _showInboxInput = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          key: const Key('tasks_page_root'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildCards(context),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          key: const Key('tasks_back_to_workbench_button'),
          onPressed: widget.onBackToWorkbench,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to Workbench'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tasks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          key: const Key('tasks_reload_button'),
          tooltip: 'Reload tasks',
          onPressed: _controller.reload,
          icon: Icon(
            Icons.refresh,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCards(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TasksSectionCard(
              key: const Key('tasks_inbox_card'),
              section: TasksSectionType.inbox,
              phase: _controller.inboxPhase,
              items: _controller.inboxItems,
              error: _controller.inboxError,
              headerTrailing: IconButton(
                key: const Key('tasks_inbox_add_button'),
                icon: Icon(
                  Icons.add,
                  size: kTasksHeaderIconSize,
                  color: tasksSecondaryTextColor(context),
                ),
                onPressed: _toggleInboxInput,
                tooltip: 'Add inbox item',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              listHeader: _showInboxInput ? _buildInboxInput(context) : null,
            ),
          ),
          const SizedBox(width: kTasksCardGap),
          Expanded(
            child: TasksSectionCard(
              key: const Key('tasks_today_card'),
              section: TasksSectionType.today,
              phase: _controller.todayPhase,
              items: _controller.todayItems,
              error: _controller.todayError,
              onToggleStatus: _controller.toggleStatus,
            ),
          ),
          const SizedBox(width: kTasksCardGap),
          Expanded(
            child: TasksSectionCard(
              key: const Key('tasks_upcoming_card'),
              section: TasksSectionType.upcoming,
              phase: _controller.upcomingPhase,
              items: _controller.upcomingItems,
              error: _controller.upcomingError,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInboxInput(BuildContext context) {
    return Row(
      children: [
        Text(
          '•',
          style: TextStyle(
            fontSize: kTasksRowIconSize,
            color: tasksSecondaryTextColor(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const Key('tasks_inbox_text_field'),
            controller: _inboxInputController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type task...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tasksSecondaryTextColor(context),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 0,
              ),
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tasksHeaderTextColor(context),
            ),
            onSubmitted: (_) => unawaited(_submitInboxItem()),
          ),
        ),
        if (_controller.creating)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
