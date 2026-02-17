import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';
import 'package:lazynote_flutter/features/tags/tag_filter.dart';

/// Folder node model reserved for hierarchical explorer expansion.
class ExplorerFolderNode {
  const ExplorerFolderNode({
    required this.id,
    required this.label,
    this.children = const <ExplorerFolderNode>[],
    this.noteIds = const <String>[],
    this.deletable = true,
  });

  /// Stable node id used by future tree operations.
  final String id;

  /// Display label rendered in explorer tree.
  final String label;

  /// Recursive child folders (v0.1 currently one-level usage).
  final List<ExplorerFolderNode> children;

  /// Note ids attached to this folder node.
  final List<String> noteIds;

  /// Whether this folder should expose delete action in explorer UI.
  final bool deletable;
}

/// Async folder-delete callback from explorer to controller layer.
typedef ExplorerFolderDeleteInvoker =
    Future<rust_api.WorkspaceActionResponse> Function(
      String folderId,
      String mode,
    );

/// Optional tree builder hook for tests/future workspace integration.
typedef ExplorerFolderTreeBuilder =
    List<ExplorerFolderNode> Function(NotesController controller);

/// Left explorer panel for notes navigation.
class NoteExplorer extends StatefulWidget {
  const NoteExplorer({
    super.key,
    required this.controller,
    required this.onOpenNoteRequested,
    required this.onCreateNoteRequested,
    this.onDeleteFolderRequested,
    this.folderTreeBuilder,
  });

  /// Source controller that provides list/tree state snapshots.
  final NotesController controller;

  /// Callback emitted when user requests opening one note.
  final ValueChanged<String> onOpenNoteRequested;

  /// Callback emitted when user requests creating one note.
  final Future<void> Function() onCreateNoteRequested;

  /// Optional callback emitted when user requests deleting one folder.
  final ExplorerFolderDeleteInvoker? onDeleteFolderRequested;

  /// Optional custom folder tree builder.
  final ExplorerFolderTreeBuilder? folderTreeBuilder;

  @override
  State<NoteExplorer> createState() => _NoteExplorerState();
}

/// Scrollbar thickness used in explorer list.
///
/// Keep this value in sync with right-side row padding so the thumb does not
/// overlap note content.
const double _scrollThickness = 4;

class _NoteExplorerState extends State<NoteExplorer> {
  final ScrollController _listScrollController = ScrollController();
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kNotesSidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kNotesTopStripHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 235;
                  final reloadDisabled =
                      widget.controller.creatingNote ||
                      widget.controller.createTagApplyInFlight;
                  return Row(
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 14,
                        color: kNotesSecondaryText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Explorer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: kNotesPrimaryText,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${widget.controller.items.length}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: kNotesSecondaryText),
                        ),
                      ],
                      IconButton(
                        key: const Key('notes_create_button'),
                        tooltip: 'Create note',
                        onPressed: widget.controller.creatingNote
                            ? null
                            : widget.onCreateNoteRequested,
                        constraints: const BoxConstraints.tightFor(
                          width: 22,
                          height: 22,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: widget.controller.creatingNote
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: kNotesSecondaryText,
                                ),
                              )
                            : const Icon(
                                Icons.add,
                                size: 14,
                                color: kNotesSecondaryText,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Retry',
                        onPressed: reloadDisabled
                            ? null
                            : widget.controller.retryLoad,
                        constraints: const BoxConstraints.tightFor(
                          width: 22,
                          height: 22,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.refresh,
                          size: 14,
                          color: kNotesSecondaryText,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: kNotesDividerColor,
          ),
          if (widget.controller.createErrorMessage case final createError?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Text(
                createError,
                key: const Key('notes_create_error'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TagFilter(
            loading: widget.controller.tagsLoading,
            tags: widget.controller.availableTags,
            selectedTag: widget.controller.selectedTag,
            errorMessage: widget.controller.tagsErrorMessage,
            onSelectTag: (tag) {
              unawaited(widget.controller.applyTagFilter(tag));
            },
            onClearTag: () {
              unawaited(widget.controller.clearTagFilter());
            },
            onRetry: () {
              unawaited(widget.controller.retryTagLoad());
            },
          ),
          const Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: kNotesDividerColor,
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (widget.controller.listPhase) {
      case NotesListPhase.idle:
      case NotesListPhase.loading:
        return const Center(
          child: SizedBox(
            key: Key('notes_list_loading'),
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      case NotesListPhase.error:
        final message =
            widget.controller.listErrorMessage ?? 'Failed to load notes.';
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  key: const Key('notes_list_error'),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: kNotesPrimaryText),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('notes_retry_button'),
                  style: TextButton.styleFrom(
                    foregroundColor: kNotesPrimaryText,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.controller.retryLoad,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case NotesListPhase.empty:
        return Center(
          child: Text(
            'No notes yet.',
            key: const Key('notes_list_empty'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: kNotesSecondaryText),
          ),
        );
      case NotesListPhase.success:
        final tree = _buildFolderTree();
        final rows = <Widget>[];
        for (final node in tree) {
          _appendFolderRows(context, rows: rows, node: node, depth: 0);
        }
        return Scrollbar(
          controller: _listScrollController,
          thickness: _scrollThickness,
          radius: const Radius.circular(2),
          child: ScrollConfiguration(
            // Why: disable desktop auto-scrollbar for this subtree because we
            // already render an explicit scrollbar bound to the same controller.
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView(
              controller: _listScrollController,
              key: const Key('notes_list_view'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: rows,
            ),
          ),
        );
    }
  }

  List<ExplorerFolderNode> _buildFolderTree() {
    if (widget.folderTreeBuilder case final builder?) {
      return builder(widget.controller);
    }
    // v0.1 one-level structure while keeping recursive model for future folders.
    final noteIds = widget.controller.items.map((item) => item.atomId).toList();
    return <ExplorerFolderNode>[
      ExplorerFolderNode(
        id: 'private',
        label: 'Private',
        deletable: false,
        children: <ExplorerFolderNode>[
          ExplorerFolderNode(
            id: 'private/all',
            label: 'All Notes',
            noteIds: noteIds,
            deletable: false,
          ),
        ],
      ),
    ];
  }

  void _appendFolderRows(
    BuildContext context, {
    required List<Widget> rows,
    required ExplorerFolderNode node,
    required int depth,
  }) {
    final canDelete =
        widget.onDeleteFolderRequested != null &&
        node.deletable &&
        _looksLikeUuid(node.id);
    rows.add(
      Padding(
        padding: EdgeInsets.fromLTRB(10 + depth * 12, 6, 10, 2),
        child: Row(
          children: [
            Icon(
              depth == 0 ? Icons.bookmark_border : Icons.folder_outlined,
              size: 14,
              color: kNotesSecondaryText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: kNotesSecondaryText,
                  fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (canDelete)
              IconButton(
                key: Key('notes_folder_delete_button_${node.id}'),
                tooltip: 'Delete folder',
                onPressed: widget.controller.workspaceDeleteInFlight
                    ? null
                    : () => _showDeleteFolderDialog(context, node),
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: widget.controller.workspaceDeleteInFlight
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: kNotesSecondaryText,
                        ),
                      )
                    : const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: kNotesSecondaryText,
                      ),
              ),
          ],
        ),
      ),
    );

    for (final child in node.children) {
      _appendFolderRows(context, rows: rows, node: child, depth: depth + 1);
    }

    for (final noteId in node.noteIds) {
      final item = widget.controller.noteById(noteId);
      rows.add(
        _ExplorerNoteRow(
          key: Key('notes_list_item_$noteId'),
          note: item,
          noteId: noteId,
          selected: noteId == widget.controller.activeNoteId,
          depth: depth + 2,
          onTap: () => widget.onOpenNoteRequested(noteId),
          fallbackTitle: widget.controller.titleForTab(noteId),
        ),
      );
    }
  }

  bool _looksLikeUuid(String value) {
    return _uuidPattern.hasMatch(value.trim());
  }

  Future<void> _showDeleteFolderDialog(
    BuildContext context,
    ExplorerFolderNode node,
  ) async {
    final invoker = widget.onDeleteFolderRequested;
    if (invoker == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);

    final selectedMode = await showDialog<_FolderDeleteMode>(
      context: context,
      builder: (dialogContext) {
        var mode = _FolderDeleteMode.dissolve;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Delete folder'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _FolderDeleteMode.values
                        .map(
                          (entry) => ChoiceChip(
                            key: Key(
                              'notes_folder_delete_mode_${entry.wireValue}',
                            ),
                            label: Text(entry.label),
                            selected: mode == entry,
                            onSelected: (_) {
                              setState(() {
                                mode = entry;
                              });
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mode.description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: kNotesSecondaryText),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.tonal(
                  key: const Key('notes_folder_delete_confirm_button'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(mode);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selectedMode == null || !mounted) {
      return;
    }

    final response = await invoker(node.id, selectedMode.wireValue);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Folder deleted with ${selectedMode.wireValue}.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      return;
    }

    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(response.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }
}

enum _FolderDeleteMode { dissolve, deleteAll }

extension on _FolderDeleteMode {
  String get wireValue => switch (this) {
    _FolderDeleteMode.dissolve => 'dissolve',
    _FolderDeleteMode.deleteAll => 'delete_all',
  };

  String get label => switch (this) {
    _FolderDeleteMode.dissolve => 'Dissolve',
    _FolderDeleteMode.deleteAll => 'Delete all',
  };

  String get description => switch (this) {
    _FolderDeleteMode.dissolve => 'Keep notes, move direct children to root.',
    _FolderDeleteMode.deleteAll =>
      'Delete folder subtree references and scoped notes.',
  };
}

class _ExplorerNoteRow extends StatelessWidget {
  const _ExplorerNoteRow({
    super.key,
    required this.noteId,
    required this.note,
    required this.selected,
    required this.depth,
    required this.onTap,
    required this.fallbackTitle,
  });

  final String noteId;
  final rust_api.NoteItem? note;
  final bool selected;
  final int depth;
  final VoidCallback onTap;
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4 + depth * 6, 0, _scrollThickness * 2, 0),
      child: Material(
        color: selected ? kNotesItemSelectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: kNotesItemHoverColor,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  kNotesItemPlaceholderIcon,
                  size: 34,
                  color: kNotesSecondaryText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fallbackTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: kNotesPrimaryText,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _previewText(note),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: kNotesSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _previewText(rust_api.NoteItem? item) {
    final preview = item?.previewText?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }
    if (item == null) {
      return noteId;
    }
    final normalized = item.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'No preview available.';
    }
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 120)}...';
  }
}
