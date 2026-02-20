import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/explorer_tree_item.dart';
import 'package:lazynote_flutter/features/notes/explorer_tree_state.dart';
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

/// Async folder-create callback from explorer to controller layer.
typedef ExplorerFolderCreateInvoker =
    Future<rust_api.WorkspaceNodeResponse> Function(
      String name,
      String? parentNodeId,
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
    this.onCreateFolderRequested,
    this.onDeleteFolderRequested,
    this.workspaceListChildrenInvoker,
    this.folderTreeBuilder,
  });

  /// Source controller that provides list/tree state snapshots.
  final NotesController controller;

  /// Callback emitted when user requests opening one note.
  final ValueChanged<String> onOpenNoteRequested;

  /// Callback emitted when user requests creating one note.
  final Future<void> Function() onCreateNoteRequested;

  /// Optional callback emitted when user requests creating one folder.
  final ExplorerFolderCreateInvoker? onCreateFolderRequested;

  /// Optional callback emitted when user requests deleting one folder.
  final ExplorerFolderDeleteInvoker? onDeleteFolderRequested;

  /// Optional callback for loading workspace children tree.
  final WorkspaceListChildrenInvoker? workspaceListChildrenInvoker;

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
  static const String _defaultUncategorizedFolderId = '__uncategorized__';
  final ScrollController _listScrollController = ScrollController();
  late ExplorerTreeState _treeState;
  bool _treeBootstrapped = false;
  List<String> _treeVisibleNoteIds = const <String>[];
  int _treeObservedRevision = 0;
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  void initState() {
    super.initState();
    _treeState = _createTreeState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant NoteExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final invokerChanged =
        oldWidget.workspaceListChildrenInvoker !=
        widget.workspaceListChildrenInvoker;
    if (oldWidget.controller != widget.controller || invokerChanged) {
      oldWidget.controller.removeListener(_handleControllerChange);
      _treeState.dispose();
      _treeState = _createTreeState();
      _treeBootstrapped = false;
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _treeState.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  ExplorerTreeState _createTreeState() {
    final invoker =
        widget.workspaceListChildrenInvoker ??
        widget.controller.listWorkspaceChildren;
    return ExplorerTreeState(childrenLoader: invoker);
  }

  void _handleControllerChange() {
    if (widget.controller.listPhase != NotesListPhase.success) {
      _treeBootstrapped = false;
      _treeVisibleNoteIds = const <String>[];
      _treeObservedRevision = widget.controller.workspaceTreeRevision;
      if (_treeState.hasLoaded(null) ||
          _treeState.isLoading(null) ||
          _treeState.errorMessageFor(null) != null) {
        _treeState.clear();
      }
      return;
    }
    final currentVisibleIds = widget.controller.items
        .map((item) => item.atomId)
        .toList(growable: false);
    if (_treeBootstrapped) {
      final revision = widget.controller.workspaceTreeRevision;
      if (_treeObservedRevision != revision) {
        _treeObservedRevision = revision;
        unawaited(_reloadRootTree(force: true));
        return;
      }
      if (!listEquals(_treeVisibleNoteIds, currentVisibleIds)) {
        _treeVisibleNoteIds = currentVisibleIds;
        unawaited(_reloadRootTree(force: true));
      }
      return;
    }
    _treeBootstrapped = true;
    _treeVisibleNoteIds = currentVisibleIds;
    _treeObservedRevision = widget.controller.workspaceTreeRevision;
    unawaited(_reloadRootTree(force: true));
  }

  Future<void> _reloadRootTree({
    required bool force,
    String? refreshParentNodeId,
  }) async {
    await _treeState.loadRoot(force: force);
    // Preserve user expansion state during refresh; only auto-expand
    // Uncategorized once on first load so legacy notes stay discoverable.
    final shouldAutoExpandUncategorized =
        !_treeState.hasLoaded(_defaultUncategorizedFolderId) &&
        !_treeState.isExpanded(_defaultUncategorizedFolderId);
    if (shouldAutoExpandUncategorized) {
      await _treeState.ensureExpanded(_defaultUncategorizedFolderId);
    } else if (_treeState.isExpanded(_defaultUncategorizedFolderId)) {
      await _treeState.retryParent(_defaultUncategorizedFolderId);
    }
    final normalizedParent = refreshParentNodeId?.trim();
    if (normalizedParent != null && normalizedParent.isNotEmpty) {
      await _refreshParentBranch(normalizedParent);
    }
  }

  Future<void> _refreshParentBranch(String parentNodeId) async {
    final normalizedParent = parentNodeId.trim();
    if (normalizedParent.isEmpty) {
      return;
    }
    await _treeState.ensureExpanded(normalizedParent);
    await _treeState.retryParent(normalizedParent);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kNotesSidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Why: keep left header vertically aligned with top tab strip.
          SizedBox(
            height: kNotesTopStripHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'My Workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: kNotesPrimaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('notes_create_folder_button'),
                    tooltip: 'New folder',
                    onPressed: widget.onCreateFolderRequested == null
                        ? null
                        : widget.controller.workspaceCreateFolderInFlight
                        ? null
                        : () => _showCreateFolderDialog(context),
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 26,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 15,
                      color: kNotesSecondaryText,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload',
                    onPressed:
                        widget.controller.creatingNote ||
                            widget.controller.createTagApplyInFlight
                        ? null
                        : widget.controller.retryLoad,
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 26,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.refresh,
                      size: 15,
                      color: kNotesSecondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(
            height: 1,
            indent: 10,
            endIndent: 10,
            color: kNotesDividerColor,
          ),
          if (widget.controller.createErrorMessage case final createError?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
          Expanded(child: _buildBody(context)),
          const Divider(height: 1, color: kNotesDividerColor),
          SizedBox(
            height: 42,
            child: TextButton.icon(
              key: const Key('notes_create_button'),
              onPressed: widget.controller.creatingNote
                  ? null
                  : widget.onCreateNoteRequested,
              icon: widget.controller.creatingNote
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: kNotesSecondaryText,
                      ),
                    )
                  : const Icon(Icons.add, size: 16),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text('New Page'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: kNotesSecondaryText,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
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
        if (!_treeBootstrapped && widget.folderTreeBuilder == null) {
          _treeBootstrapped = true;
          unawaited(_reloadRootTree(force: false));
        }
        return _buildSuccessTree(context);
    }
  }

  Widget _buildSuccessTree(BuildContext context) {
    if (widget.folderTreeBuilder != null) {
      final rows = <Widget>[_buildTagFilter()];
      final tree = _buildFolderTree();
      for (final node in tree) {
        _appendLegacyFolderRows(context, rows: rows, node: node, depth: 0);
      }
      return _buildScrollableRows(rows);
    }

    return AnimatedBuilder(
      animation: _treeState,
      builder: (context, _) {
        final rows = <Widget>[_buildTagFilter()];
        if (_treeState.isLoading(null) && !_treeState.hasLoaded(null)) {
          rows.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  key: Key('notes_tree_root_loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
          return _buildScrollableRows(rows);
        }

        if (_treeState.errorMessageFor(null) case final rootError?) {
          rows.add(
            Padding(
              key: const Key('notes_tree_root_error'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rootError,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('notes_tree_root_retry_button'),
                    onPressed: () {
                      unawaited(_treeState.retryParent(null));
                    },
                    child: const Text('Retry tree'),
                  ),
                ],
              ),
            ),
          );
          return _buildScrollableRows(rows);
        }

        final rootItems =
            _treeState.childrenFor(null) ??
            const <rust_api.WorkspaceNodeItem>[];
        if (rootItems.isEmpty) {
          rows.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Text(
                'Workspace tree is empty.',
                key: Key('notes_tree_root_empty'),
                style: TextStyle(color: kNotesSecondaryText),
              ),
            ),
          );
          return _buildScrollableRows(rows);
        }

        _appendWorkspaceRows(context, rows: rows, items: rootItems, depth: 0);
        return _buildScrollableRows(rows);
      },
    );
  }

  Widget _buildTagFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: TagFilter(
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
    );
  }

  Widget _buildScrollableRows(List<Widget> rows) {
    return Scrollbar(
      controller: _listScrollController,
      thickness: _scrollThickness,
      radius: const Radius.circular(2),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          controller: _listScrollController,
          key: const Key('notes_list_view'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: rows,
        ),
      ),
    );
  }

  void _appendWorkspaceRows(
    BuildContext context, {
    required List<Widget> rows,
    required List<rust_api.WorkspaceNodeItem> items,
    required int depth,
  }) {
    for (final item in items) {
      if (item.kind == 'folder') {
        final expanded = _treeState.isExpanded(item.nodeId);
        final loading = _treeState.isLoading(item.nodeId);
        final error = _treeState.errorMessageFor(item.nodeId);
        final canCreateChild =
            widget.onCreateFolderRequested != null &&
            _looksLikeUuid(item.nodeId);
        final canDelete =
            widget.onDeleteFolderRequested != null &&
            _looksLikeUuid(item.nodeId);
        rows.add(
          ExplorerTreeItem.folder(
            key: Key('notes_tree_folder_row_${item.nodeId}'),
            node: item,
            depth: depth,
            selected: false,
            expanded: expanded,
            canCreateChild: canCreateChild,
            canDelete: canDelete,
            onTap: () {
              unawaited(_treeState.toggleFolder(item.nodeId));
            },
            onCreateChildFolder: canCreateChild
                ? widget.controller.workspaceCreateFolderInFlight
                      ? null
                      : () => _showCreateFolderDialog(
                          context,
                          parentNodeId: item.nodeId,
                        )
                : null,
            onDeleteFolder: canDelete
                ? () => _showDeleteFolderDialog(
                    context,
                    ExplorerFolderNode(
                      id: item.nodeId,
                      label: item.displayName,
                      deletable: true,
                    ),
                  )
                : null,
          ),
        );

        if (!expanded) {
          continue;
        }
        if (loading && !_treeState.hasLoaded(item.nodeId)) {
          rows.add(
            Padding(
              key: Key('notes_tree_loading_${item.nodeId}'),
              padding: EdgeInsets.fromLTRB(30 + depth * 12, 2, 10, 4),
              child: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            ),
          );
          continue;
        }
        if (error != null) {
          rows.add(
            Padding(
              key: Key('notes_tree_error_${item.nodeId}'),
              padding: EdgeInsets.fromLTRB(30 + depth * 12, 2, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: Key('notes_tree_retry_${item.nodeId}'),
                    onPressed: () {
                      unawaited(_treeState.retryParent(item.nodeId));
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
          continue;
        }
        final children =
            _treeState.childrenFor(item.nodeId) ??
            const <rust_api.WorkspaceNodeItem>[];
        if (children.isEmpty) {
          rows.add(
            Padding(
              key: Key('notes_tree_empty_${item.nodeId}'),
              padding: EdgeInsets.fromLTRB(30 + depth * 12, 2, 10, 6),
              child: Text(
                'No items',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: kNotesSecondaryText),
              ),
            ),
          );
          continue;
        }
        _appendWorkspaceRows(
          context,
          rows: rows,
          items: children,
          depth: depth + 1,
        );
        continue;
      }

      if (item.kind != 'note_ref') {
        continue;
      }
      final noteId = item.atomId;
      if (noteId == null || noteId.isEmpty) {
        continue;
      }
      final note = widget.controller.noteById(noteId);
      final displayName = item.displayName.trim().isEmpty
          ? widget.controller.titleForTab(noteId)
          : item.displayName;
      rows.add(
        ExplorerTreeItem.note(
          key: Key('notes_tree_note_row_${item.nodeId}'),
          node: rust_api.WorkspaceNodeItem(
            nodeId: item.nodeId,
            kind: item.kind,
            parentNodeId: item.parentNodeId,
            atomId: item.atomId,
            displayName: displayName,
            sortOrder: item.sortOrder,
          ),
          depth: depth + 1,
          selected: noteId == widget.controller.activeNoteId,
          onTap: () => widget.onOpenNoteRequested(noteId),
          previewText: _previewText(noteId: noteId, note: note),
        ),
      );
    }
  }

  List<ExplorerFolderNode> _buildFolderTree() {
    if (widget.folderTreeBuilder case final builder?) {
      return builder(widget.controller);
    }
    // v0.2A visual baseline: show workspace-like top folders while still
    // binding note rows from existing list source.
    final noteIds = widget.controller.items.map((item) => item.atomId).toList();
    return <ExplorerFolderNode>[
      ExplorerFolderNode(id: 'projects', label: 'Projects', deletable: false),
      ExplorerFolderNode(
        id: 'notes',
        label: 'Notes',
        deletable: false,
        noteIds: noteIds,
      ),
      ExplorerFolderNode(id: 'personal', label: 'Personal', deletable: false),
    ];
  }

  void _appendLegacyFolderRows(
    BuildContext context, {
    required List<Widget> rows,
    required ExplorerFolderNode node,
    required int depth,
  }) {
    final canDelete =
        widget.onDeleteFolderRequested != null &&
        node.deletable &&
        _looksLikeUuid(node.id);
    final canCreateChild =
        widget.onCreateFolderRequested != null && _looksLikeUuid(node.id);
    rows.add(
      Padding(
        padding: EdgeInsets.fromLTRB(12 + depth * 12, 8, 10, 2),
        child: Row(
          children: [
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: kNotesSecondaryText,
            ),
            const SizedBox(width: 2),
            Icon(Icons.folder_outlined, size: 16, color: kNotesSecondaryText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: kNotesSecondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (canCreateChild)
              IconButton(
                key: Key('notes_folder_create_button_${node.id}'),
                tooltip: 'New child folder',
                onPressed: widget.controller.workspaceCreateFolderInFlight
                    ? null
                    : () => _showCreateFolderDialog(
                        context,
                        parentNodeId: node.id,
                      ),
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: widget.controller.workspaceCreateFolderInFlight
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: kNotesSecondaryText,
                        ),
                      )
                    : const Icon(
                        Icons.create_new_folder_outlined,
                        size: 14,
                        color: kNotesSecondaryText,
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
      _appendLegacyFolderRows(
        context,
        rows: rows,
        node: child,
        depth: depth + 1,
      );
    }

    for (final noteId in node.noteIds) {
      final item = widget.controller.noteById(noteId);
      rows.add(
        ExplorerTreeItem.note(
          key: Key('notes_tree_legacy_note_row_$noteId'),
          node: rust_api.WorkspaceNodeItem(
            nodeId: 'legacy_note_$noteId',
            kind: 'note_ref',
            parentNodeId: node.id,
            atomId: noteId,
            displayName: widget.controller.titleForTab(noteId),
            sortOrder: 0,
          ),
          selected: noteId == widget.controller.activeNoteId,
          depth: depth + 1,
          onTap: () => widget.onOpenNoteRequested(noteId),
          previewText: _previewText(noteId: noteId, note: item),
        ),
      );
    }
  }

  String _previewText({
    required String noteId,
    required rust_api.NoteItem? note,
  }) {
    final preview = note?.previewText?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }
    if (note == null) {
      return noteId;
    }
    final normalized = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'No preview available.';
    }
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 120)}...';
  }

  bool _looksLikeUuid(String value) {
    return _uuidPattern.hasMatch(value.trim());
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context, {
    String? parentNodeId,
  }) async {
    final invoker = widget.onCreateFolderRequested;
    if (invoker == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    var draftName = '';
    final folderName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = draftName.trim().isNotEmpty;
            return AlertDialog(
              key: const Key('notes_create_folder_dialog'),
              title: const Text('Create folder'),
              content: TextField(
                key: const Key('notes_create_folder_name_input'),
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Folder name'),
                onChanged: (value) {
                  draftName = value;
                  setState(() {});
                },
                onSubmitted: (_) {
                  if (canSubmit) {
                    Navigator.of(dialogContext).pop(draftName.trim());
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton.tonal(
                  key: const Key('notes_create_folder_confirm_button'),
                  onPressed: canSubmit
                      ? () {
                          Navigator.of(dialogContext).pop(draftName.trim());
                        }
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    if (folderName == null || folderName.trim().isEmpty || !mounted) {
      return;
    }

    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(folderName.trim(), parentNodeId);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      final normalizedParent = parentNodeId?.trim();
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(
          force: true,
          refreshParentNodeId: normalizedParent,
        );
      } else if (normalizedParent != null && normalizedParent.isNotEmpty) {
        // Revision refresh reloads root; child create still needs explicit parent
        // branch refresh so new child folder appears immediately.
        await _refreshParentBranch(normalizedParent);
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Folder created.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
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

    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(node.id, selectedMode.wireValue);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(force: true);
      }
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
