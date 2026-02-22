import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/explorer_context_menu.dart';
import 'package:lazynote_flutter/features/notes/explorer_drag_controller.dart';
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
    this.parentId,
    this.children = const <ExplorerFolderNode>[],
    this.noteIds = const <String>[],
    this.deletable = true,
  });

  /// Stable node id used by future tree operations.
  final String id;

  /// Display label rendered in explorer tree.
  final String label;

  /// Parent node id when sourced from workspace tree (nullable for root).
  final String? parentId;

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

/// Async note-create callback that also links note_ref under optional parent.
typedef ExplorerNoteCreateInFolderInvoker =
    Future<rust_api.WorkspaceActionResponse> Function(String? parentNodeId);

/// Async node-rename callback.
typedef ExplorerNodeRenameInvoker =
    Future<rust_api.WorkspaceActionResponse> Function(
      String nodeId,
      String newName,
    );

/// Async node-move callback.
typedef ExplorerNodeMoveInvoker =
    Future<rust_api.WorkspaceActionResponse> Function(
      String nodeId,
      String? newParentNodeId, {
      int? targetOrder,
    });

/// Optional tree builder hook for tests/future workspace integration.
typedef ExplorerFolderTreeBuilder =
    List<ExplorerFolderNode> Function(NotesController controller);

/// Left explorer panel for notes navigation.
class NoteExplorer extends StatefulWidget {
  const NoteExplorer({
    super.key,
    required this.controller,
    required this.onOpenNoteRequested,
    this.onOpenNotePinnedRequested,
    required this.onCreateNoteRequested,
    this.onCreateNoteInFolderRequested,
    this.onCreateFolderRequested,
    this.onDeleteFolderRequested,
    this.onRenameNodeRequested,
    this.onMoveNodeRequested,
    this.workspaceListChildrenInvoker,
    this.folderTreeBuilder,
  });

  /// Source controller that provides list/tree state snapshots.
  final NotesController controller;

  /// Callback emitted when user requests opening one note.
  final ValueChanged<String> onOpenNoteRequested;

  /// Optional callback emitted when user requests opening one note as pinned.
  final ValueChanged<String>? onOpenNotePinnedRequested;

  /// Callback emitted when user requests creating one note.
  final Future<void> Function() onCreateNoteRequested;

  /// Optional callback emitted when user requests creating one note in folder.
  final ExplorerNoteCreateInFolderInvoker? onCreateNoteInFolderRequested;

  /// Optional callback emitted when user requests creating one folder.
  final ExplorerFolderCreateInvoker? onCreateFolderRequested;

  /// Optional callback emitted when user requests deleting one folder.
  final ExplorerFolderDeleteInvoker? onDeleteFolderRequested;

  /// Optional callback emitted when user requests renaming one node.
  final ExplorerNodeRenameInvoker? onRenameNodeRequested;

  /// Optional callback emitted when user requests moving one node.
  final ExplorerNodeMoveInvoker? onMoveNodeRequested;

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
  static const String _rootTargetNodeId = '__root__';
  static const Duration _doubleTapThreshold = Duration(milliseconds: 280);
  static const Duration _contextMenuDedupWindow = Duration(milliseconds: 320);
  final ScrollController _listScrollController = ScrollController();
  late ExplorerTreeState _treeState;
  bool _treeBootstrapped = false;
  bool _didAutoExpandUncategorized = false;
  List<String> _treeVisibleNoteIds = const <String>[];
  int _treeObservedRevision = 0;
  String? _lastNoteTapId;
  DateTime? _lastNoteTapAt;
  Offset? _lastRowContextMenuPosition;
  DateTime? _lastRowContextMenuAt;
  final ExplorerDragController _dragController = const ExplorerDragController();
  bool _rowContextMenuPending = false;
  bool _dragInProgress = false;
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
      _didAutoExpandUncategorized = false;
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
      final keepTreeDuringRefresh =
          widget.controller.listPhase == NotesListPhase.loading &&
          _treeBootstrapped;
      if (keepTreeDuringRefresh) {
        _treeObservedRevision = widget.controller.workspaceTreeRevision;
        return;
      }
      _treeBootstrapped = false;
      _treeVisibleNoteIds = const <String>[];
      _treeObservedRevision = widget.controller.workspaceTreeRevision;
      _didAutoExpandUncategorized = false;
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
    // Preserve user expansion state during refresh; auto-expand Uncategorized
    // only once for first discoverability.
    final shouldAutoExpandUncategorized =
        !_didAutoExpandUncategorized &&
        !_treeState.hasLoaded(_defaultUncategorizedFolderId) &&
        !_treeState.isExpanded(_defaultUncategorizedFolderId);
    if (shouldAutoExpandUncategorized) {
      _didAutoExpandUncategorized = true;
      await _treeState.ensureExpanded(_defaultUncategorizedFolderId);
    } else if (force && _treeState.hasLoaded(_defaultUncategorizedFolderId)) {
      // Keep cached synthetic children fresh even when folder is collapsed.
      await _treeState.retryParent(_defaultUncategorizedFolderId);
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
      animation: Listenable.merge([_treeState, widget.controller]),
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

        if (_dragInProgress && widget.onMoveNodeRequested != null) {
          rows.add(_buildRootDropLane(context));
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) {
            unawaited(
              _showBlankAreaContextMenuDeferred(
                globalPosition: details.globalPosition,
              ),
            );
          },
          onLongPressStart: (details) {
            unawaited(
              _showBlankAreaContextMenuDeferred(
                globalPosition: details.globalPosition,
              ),
            );
          },
          child: ListView(
            controller: _listScrollController,
            key: const Key('notes_list_view'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: rows,
          ),
        ),
      ),
    );
  }

  void _handleNoteTap(String noteId) {
    final now = DateTime.now();
    final lastId = _lastNoteTapId;
    final lastAt = _lastNoteTapAt;
    _lastNoteTapId = noteId;
    _lastNoteTapAt = now;
    final isSecondTap =
        widget.onOpenNotePinnedRequested != null &&
        lastId == noteId &&
        lastAt != null &&
        now.difference(lastAt) <= _doubleTapThreshold;

    if (isSecondTap) {
      widget.onOpenNotePinnedRequested!(noteId);
      return;
    }
    widget.onOpenNoteRequested(noteId);
  }

  bool _isSyntheticRootNodeId(String nodeId) {
    return nodeId.trim() == _defaultUncategorizedFolderId;
  }

  String? _normalizeParentForMutation(String? parentNodeId) {
    final normalized = parentNodeId?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == _rootTargetNodeId ||
        normalized == _defaultUncategorizedFolderId) {
      return null;
    }
    return normalized;
  }

  void _recordRowContextMenuTrigger(Offset globalPosition) {
    _lastRowContextMenuPosition = globalPosition;
    _lastRowContextMenuAt = DateTime.now();
  }

  bool _shouldSuppressBlankAreaContextMenu(Offset globalPosition) {
    final lastAt = _lastRowContextMenuAt;
    final lastPosition = _lastRowContextMenuPosition;
    if (lastAt == null || lastPosition == null) {
      return false;
    }
    final withinWindow =
        DateTime.now().difference(lastAt) <= _contextMenuDedupWindow;
    if (!withinWindow) {
      return false;
    }
    return (globalPosition - lastPosition).distance <= 6;
  }

  Future<void> _showBlankAreaContextMenu({
    required Offset globalPosition,
  }) async {
    if (_rowContextMenuPending) {
      return;
    }
    final entries = buildExplorerContextMenuEntries(
      ExplorerContextMenuConfig(
        targetKind: ExplorerContextTargetKind.blankArea,
        canCreateNote: true,
        canCreateFolder: widget.onCreateFolderRequested != null,
        canRename: false,
        canMove: false,
        canDeleteFolder: false,
      ),
    );
    final action = await _showContextMenuAtPosition(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
    );
    if (action == null || !mounted) {
      return;
    }
    await _runContextAction(
      context: context,
      action: action,
      target: _ExplorerContextTarget.blankArea(),
    );
  }

  Future<void> _showBlankAreaContextMenuDeferred({
    required Offset globalPosition,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 24));
    if (!mounted) {
      return;
    }
    if (_rowContextMenuPending ||
        _shouldSuppressBlankAreaContextMenu(globalPosition)) {
      return;
    }
    await _showBlankAreaContextMenu(globalPosition: globalPosition);
  }

  Widget _buildRootDropLane(BuildContext context) {
    return DragTarget<ExplorerDragPayload>(
      key: const Key('notes_tree_root_drop_lane'),
      onWillAcceptWithDetails: (details) =>
          _dragController.planForRootDrop(payload: details.data) != null,
      onAcceptWithDetails: (details) {
        final plan = _dragController.planForRootDrop(payload: details.data);
        if (plan == null) {
          return;
        }
        unawaited(
          _performDragMove(context: context, payload: details.data, plan: plan),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 10, 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: active
                  ? kNotesItemSelectedColor
                  : kNotesItemHoverColor.withValues(alpha: 0.45),
              border: Border.all(
                color: active
                    ? kNotesSecondaryText.withValues(alpha: 0.65)
                    : kNotesDividerColor,
                width: 1,
              ),
            ),
            child: Text(
              'Drop here to move to root',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: kNotesSecondaryText,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _wrapWorkspaceRowWithDrag({
    required BuildContext context,
    required rust_api.WorkspaceNodeItem node,
    required int depth,
    required Widget child,
  }) {
    if (widget.onMoveNodeRequested == null) {
      return child;
    }

    final isSyntheticRoot = _isSyntheticRootNodeId(node.nodeId);
    final canDrag = _dragController.canDragNode(
      node: node,
      isSyntheticRootNodeId: isSyntheticRoot,
      isStableNodeId: _looksLikeUuid(node.nodeId),
    );
    final payload = canDrag
        ? ExplorerDragPayload(
            nodeId: node.nodeId,
            kind: node.kind,
            sourceParentNodeId: _normalizeParentForMutation(node.parentNodeId),
          )
        : null;

    Widget draggableChild = child;
    if (payload != null) {
      draggableChild = Draggable<ExplorerDragPayload>(
        data: payload,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _buildDragFeedback(context, node: node, depth: depth),
        childWhenDragging: Opacity(opacity: 0.45, child: child),
        maxSimultaneousDrags: 1,
        onDragStarted: () {
          if (!_dragInProgress && mounted) {
            setState(() {
              _dragInProgress = true;
            });
          }
        },
        onDragEnd: (_) {
          if (_dragInProgress && mounted) {
            setState(() {
              _dragInProgress = false;
            });
          }
        },
        child: child,
      );
    }

    return DragTarget<ExplorerDragPayload>(
      onWillAcceptWithDetails: (details) =>
          _resolveRowDropPlan(payload: details.data, targetNode: node) != null,
      onAcceptWithDetails: (details) {
        final plan = _resolveRowDropPlan(
          payload: details.data,
          targetNode: node,
        );
        if (plan == null) {
          return;
        }
        unawaited(
          _performDragMove(context: context, payload: details.data, plan: plan),
        );
      },
      builder: (context, candidateData, rejectedData) {
        ExplorerDragPayload? candidate;
        for (final entry in candidateData) {
          if (entry != null) {
            candidate = entry;
            break;
          }
        }
        final plan = candidate == null
            ? null
            : _resolveRowDropPlan(payload: candidate, targetNode: node);
        if (plan == null) {
          return draggableChild;
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: kNotesItemSelectedColor.withValues(alpha: 0.35),
          ),
          child: draggableChild,
        );
      },
    );
  }

  ExplorerDropPlan? _resolveRowDropPlan({
    required ExplorerDragPayload payload,
    required rust_api.WorkspaceNodeItem targetNode,
  }) {
    return _dragController.planForRowDrop(
      payload: payload,
      targetNode: targetNode,
      normalizeParent: _normalizeParentForMutation,
      isStableNodeId: (nodeId) => _looksLikeUuid(nodeId),
      isSyntheticRootNodeId: _isSyntheticRootNodeId,
    );
  }

  Widget _buildDragFeedback(
    BuildContext context, {
    required rust_api.WorkspaceNodeItem node,
    required int depth,
  }) {
    final icon = node.kind == 'folder'
        ? Icons.folder_outlined
        : kNotesItemPlaceholderIcon;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kNotesCanvasBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kNotesDividerColor),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10 + depth * 2, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: kNotesSecondaryText),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    node.displayName.trim().isEmpty
                        ? node.nodeId
                        : node.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kNotesPrimaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performDragMove({
    required BuildContext context,
    required ExplorerDragPayload payload,
    required ExplorerDropPlan plan,
  }) async {
    final invoker = widget.onMoveNodeRequested;
    if (invoker == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(
      payload.nodeId,
      plan.newParentNodeId,
      targetOrder: null,
    );
    if (!mounted) {
      return;
    }
    if (response.ok) {
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(force: true);
      }
      await _refreshDropBranches(
        sourceParentNodeId: plan.sourceParentNodeId,
        targetParentNodeId: plan.targetParentNodeId,
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Moved.'),
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

  Future<void> _refreshDropBranches({
    required String? sourceParentNodeId,
    required String? targetParentNodeId,
  }) async {
    var rootRefreshed = false;
    Future<void> refreshParent(String? parentNodeId) async {
      if (parentNodeId == null) {
        if (rootRefreshed) {
          return;
        }
        rootRefreshed = true;
        await _reloadRootTree(force: true);
        return;
      }
      await _refreshParentBranch(parentNodeId);
    }

    await refreshParent(sourceParentNodeId);
    if (targetParentNodeId != sourceParentNodeId) {
      await refreshParent(targetParentNodeId);
    }
  }

  Future<void> _showFolderContextMenu({
    required BuildContext context,
    required rust_api.WorkspaceNodeItem folderNode,
    required Offset globalPosition,
  }) async {
    final isSyntheticRoot = _isSyntheticRootNodeId(folderNode.nodeId);
    final entries = buildExplorerContextMenuEntries(
      ExplorerContextMenuConfig(
        targetKind: isSyntheticRoot
            ? ExplorerContextTargetKind.syntheticRoot
            : ExplorerContextTargetKind.folder,
        canCreateNote: widget.onCreateNoteInFolderRequested != null,
        canCreateFolder: widget.onCreateFolderRequested != null,
        canRename:
            widget.onRenameNodeRequested != null &&
            !isSyntheticRoot &&
            _looksLikeUuid(folderNode.nodeId),
        canMove:
            widget.onMoveNodeRequested != null &&
            !isSyntheticRoot &&
            _looksLikeUuid(folderNode.nodeId),
        canDeleteFolder:
            widget.onDeleteFolderRequested != null &&
            !isSyntheticRoot &&
            _looksLikeUuid(folderNode.nodeId),
      ),
    );
    if (entries.isEmpty) {
      return;
    }
    _rowContextMenuPending = true;
    ExplorerContextAction? action;
    try {
      action = await _showContextMenuAtPosition(
        context: context,
        globalPosition: globalPosition,
        entries: entries,
      );
    } finally {
      _rowContextMenuPending = false;
    }
    if (action == null || !mounted) {
      return;
    }
    await _runContextAction(
      context: this.context,
      action: action,
      target: _ExplorerContextTarget.folder(folderNode),
    );
  }

  Future<void> _showNoteContextMenu({
    required BuildContext context,
    required rust_api.WorkspaceNodeItem noteNode,
    required Offset globalPosition,
  }) async {
    final entries = buildExplorerContextMenuEntries(
      ExplorerContextMenuConfig(
        targetKind: ExplorerContextTargetKind.noteRef,
        canCreateNote: false,
        canCreateFolder: false,
        // v0.2 policy freeze: note_ref alias rename is not exposed.
        canRename: false,
        canMove:
            widget.onMoveNodeRequested != null &&
            _looksLikeUuid(noteNode.nodeId),
        canDeleteFolder: false,
      ),
    );
    if (entries.isEmpty) {
      return;
    }
    _rowContextMenuPending = true;
    ExplorerContextAction? action;
    try {
      action = await _showContextMenuAtPosition(
        context: context,
        globalPosition: globalPosition,
        entries: entries,
      );
    } finally {
      _rowContextMenuPending = false;
    }
    if (action == null || !mounted) {
      return;
    }
    await _runContextAction(
      context: this.context,
      action: action,
      target: _ExplorerContextTarget.noteRef(noteNode),
    );
  }

  Future<ExplorerContextAction?> _showContextMenuAtPosition({
    required BuildContext context,
    required Offset globalPosition,
    required List<PopupMenuEntry<ExplorerContextAction>> entries,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<ExplorerContextAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: entries,
    );
  }

  Future<void> _runContextAction({
    required BuildContext context,
    required ExplorerContextAction action,
    required _ExplorerContextTarget target,
  }) async {
    switch (action) {
      case ExplorerContextAction.newNote:
        await _handleCreateNoteFromContext(
          context,
          parentNodeId: switch (target.kind) {
            _ExplorerContextTargetKind.folder => target.node?.nodeId,
            _ExplorerContextTargetKind.blankArea => null,
            _ExplorerContextTargetKind.noteRef => target.node?.parentNodeId,
          },
        );
      case ExplorerContextAction.newFolder:
        await _showCreateFolderDialog(
          context,
          parentNodeId: switch (target.kind) {
            _ExplorerContextTargetKind.folder => target.node?.nodeId,
            _ExplorerContextTargetKind.blankArea => null,
            _ExplorerContextTargetKind.noteRef => target.node?.parentNodeId,
          },
        );
      case ExplorerContextAction.rename:
        final node = target.node;
        if (node == null) {
          return;
        }
        await _showRenameNodeDialog(context, node: node);
      case ExplorerContextAction.move:
        final node = target.node;
        if (node == null) {
          return;
        }
        await _showMoveNodeDialog(context, node: node);
      case ExplorerContextAction.deleteFolder:
        final node = target.node;
        if (node == null || node.kind != 'folder') {
          return;
        }
        await _showDeleteFolderDialog(
          context,
          ExplorerFolderNode(
            id: node.nodeId,
            label: node.displayName,
            parentId: node.parentNodeId,
            deletable: true,
          ),
        );
    }
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
        final isSyntheticRoot = _isSyntheticRootNodeId(item.nodeId);
        final canCreateChild =
            widget.onCreateFolderRequested != null &&
            (_looksLikeUuid(item.nodeId) || isSyntheticRoot);
        final canDelete =
            widget.onDeleteFolderRequested != null &&
            _looksLikeUuid(item.nodeId);
        final folderRow = ExplorerTreeItem.folder(
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
                    parentId: item.parentNodeId,
                    deletable: true,
                  ),
                )
              : null,
          onSecondaryTapDown: (details) {
            _recordRowContextMenuTrigger(details.globalPosition);
            unawaited(
              _showFolderContextMenu(
                context: context,
                folderNode: item,
                globalPosition: details.globalPosition,
              ),
            );
          },
        );
        rows.add(
          _wrapWorkspaceRowWithDrag(
            context: context,
            node: item,
            depth: depth,
            child: folderRow,
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
      // Keep note-row title projection unified across folders/uncategorized.
      // Fallback to node label only when note snapshot is unavailable.
      final projectedTitle = note == null
          ? null
          : widget.controller.titleForTab(noteId);
      final trimmedNodeLabel = item.displayName.trim();
      final displayName =
          projectedTitle ??
          (trimmedNodeLabel.isEmpty
              ? widget.controller.titleForTab(noteId)
              : item.displayName);
      final noteRow = ExplorerTreeItem.note(
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
        onTap: () => _handleNoteTap(noteId),
        onSecondaryTapDown: (details) {
          _recordRowContextMenuTrigger(details.globalPosition);
          unawaited(
            _showNoteContextMenu(
              context: context,
              noteNode: item,
              globalPosition: details.globalPosition,
            ),
          );
        },
      );
      rows.add(
        _wrapWorkspaceRowWithDrag(
          context: context,
          node: item,
          depth: depth + 1,
          child: noteRow,
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
          onTap: () => _handleNoteTap(noteId),
        ),
      );
    }
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

    final normalizedParent = _normalizeParentForMutation(parentNodeId);
    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(folderName.trim(), normalizedParent);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(
          force: true,
          refreshParentNodeId: normalizedParent,
        );
      } else if (normalizedParent != null && normalizedParent.isNotEmpty) {
        // Revision refresh reloads root; child create still needs explicit parent
        // branch refresh so new child folder appears immediately.
        await _refreshParentBranch(normalizedParent);
      } else {
        await _reloadRootTree(force: true);
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
      final deletedParent = _normalizeParentForMutation(node.parentId);
      final shouldRefreshParentBranch =
          deletedParent != null &&
          (_treeState.hasLoaded(deletedParent) ||
              _treeState.isExpanded(deletedParent));
      if (shouldRefreshParentBranch) {
        // Why: deleting a child folder does not alter root set; refreshing only
        // root can leave stale child cache visible and undeletable until reload.
        await _treeState.retryParent(deletedParent);
      } else if (deletedParent == null ||
          widget.controller.workspaceTreeRevision == revisionBefore) {
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

  Future<void> _handleCreateNoteFromContext(
    BuildContext context, {
    String? parentNodeId,
  }) async {
    final normalizedParent = _normalizeParentForMutation(parentNodeId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final invoker = widget.onCreateNoteInFolderRequested;
    if (invoker == null) {
      await widget.onCreateNoteRequested();
      return;
    }

    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(normalizedParent);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(
          force: true,
          refreshParentNodeId: normalizedParent,
        );
      } else if (normalizedParent != null) {
        await _refreshParentBranch(normalizedParent);
      } else {
        await _reloadRootTree(force: true);
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Note created.'),
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

  Future<void> _showRenameNodeDialog(
    BuildContext context, {
    required rust_api.WorkspaceNodeItem node,
  }) async {
    final invoker = widget.onRenameNodeRequested;
    if (invoker == null) {
      return;
    }
    if (node.kind != 'folder') {
      return;
    }
    if (_isSyntheticRootNodeId(node.nodeId)) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    var draftName = node.displayName;
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit =
                draftName.trim().isNotEmpty &&
                draftName.trim() != node.displayName.trim();
            return AlertDialog(
              key: const Key('notes_rename_node_dialog'),
              title: const Text('Rename'),
              content: TextFormField(
                key: const Key('notes_rename_node_input'),
                autofocus: true,
                initialValue: node.displayName,
                onChanged: (value) {
                  draftName = value;
                  setState(() {});
                },
                onFieldSubmitted: (_) {
                  if (canSubmit) {
                    Navigator.of(dialogContext).pop(draftName.trim());
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.tonal(
                  key: const Key('notes_rename_node_confirm_button'),
                  onPressed: canSubmit
                      ? () => Navigator.of(dialogContext).pop(draftName.trim())
                      : null,
                  child: const Text('Rename'),
                ),
              ],
            );
          },
        );
      },
    );
    if (renamed == null || !mounted) {
      return;
    }
    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(node.nodeId, renamed);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      final parentNodeId = _normalizeParentForMutation(node.parentNodeId);
      final shouldRefreshParentBranch =
          parentNodeId != null &&
          (_treeState.hasLoaded(parentNodeId) ||
              _treeState.isExpanded(parentNodeId));
      if (shouldRefreshParentBranch) {
        // Why: rename on child folders only affects one parent branch. Relying
        // on root refresh alone can leave stale child labels in cached rows.
        await _treeState.retryParent(parentNodeId);
      } else if (parentNodeId == null ||
          widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(force: true, refreshParentNodeId: parentNodeId);
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Renamed.'),
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

  Future<void> _showMoveNodeDialog(
    BuildContext context, {
    required rust_api.WorkspaceNodeItem node,
  }) async {
    final invoker = widget.onMoveNodeRequested;
    if (invoker == null) {
      return;
    }
    if (_isSyntheticRootNodeId(node.nodeId)) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final options = await _loadMoveTargetOptions(node: node);
    if (!mounted) {
      return;
    }
    if (options.isEmpty) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No available move targets.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      return;
    }
    if (!context.mounted) {
      return;
    }
    var selectedTargetId =
        _normalizeParentForMutation(node.parentNodeId) ?? _rootTargetNodeId;
    if (!options.any((entry) => entry.nodeId == selectedTargetId)) {
      selectedTargetId = _rootTargetNodeId;
    }

    final targetId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              key: const Key('notes_move_node_dialog'),
              title: const Text('Move node'),
              content: DropdownButtonFormField<String>(
                key: const Key('notes_move_node_target_dropdown'),
                initialValue: selectedTargetId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Target folder'),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.nodeId,
                        child: Text(option.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    selectedTargetId = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.tonal(
                  key: const Key('notes_move_node_confirm_button'),
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selectedTargetId),
                  child: const Text('Move'),
                ),
              ],
            );
          },
        );
      },
    );

    if (targetId == null || !mounted) {
      return;
    }
    final normalizedTarget = _normalizeParentForMutation(targetId);
    final currentParent = _normalizeParentForMutation(node.parentNodeId);
    if (normalizedTarget == currentParent) {
      return;
    }
    final revisionBefore = widget.controller.workspaceTreeRevision;
    final response = await invoker(node.nodeId, normalizedTarget);
    if (!mounted) {
      return;
    }
    if (response.ok) {
      if (widget.controller.workspaceTreeRevision == revisionBefore) {
        await _reloadRootTree(force: true);
      }
      if (currentParent != null) {
        await _refreshParentBranch(currentParent);
      }
      if (normalizedTarget != null && normalizedTarget != currentParent) {
        await _refreshParentBranch(normalizedTarget);
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Moved.'),
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

  Future<List<_MoveTargetOption>> _loadMoveTargetOptions({
    required rust_api.WorkspaceNodeItem node,
  }) async {
    final options = <_MoveTargetOption>[
      const _MoveTargetOption(nodeId: _rootTargetNodeId, label: 'Root'),
    ];
    final visitedFolders = <String>{};
    final pendingParents = <String?>[null];

    while (pendingParents.isNotEmpty) {
      final parentNodeId = pendingParents.removeAt(0);
      final response = await widget.controller.listWorkspaceChildren(
        parentNodeId: parentNodeId,
      );
      if (!response.ok) {
        break;
      }
      for (final item in response.items) {
        if (item.kind != 'folder') {
          continue;
        }
        if (_isSyntheticRootNodeId(item.nodeId)) {
          continue;
        }
        if (!visitedFolders.add(item.nodeId)) {
          continue;
        }
        if (item.nodeId == node.nodeId) {
          continue;
        }
        options.add(
          _MoveTargetOption(
            nodeId: item.nodeId,
            label: item.displayName.trim().isEmpty
                ? item.nodeId
                : item.displayName,
          ),
        );
        pendingParents.add(item.nodeId);
      }
    }
    return options;
  }
}

enum _ExplorerContextTargetKind { blankArea, folder, noteRef }

class _ExplorerContextTarget {
  const _ExplorerContextTarget._({required this.kind, this.node});

  const _ExplorerContextTarget.blankArea()
    : this._(kind: _ExplorerContextTargetKind.blankArea);

  const _ExplorerContextTarget.folder(rust_api.WorkspaceNodeItem node)
    : this._(kind: _ExplorerContextTargetKind.folder, node: node);

  const _ExplorerContextTarget.noteRef(rust_api.WorkspaceNodeItem node)
    : this._(kind: _ExplorerContextTargetKind.noteRef, node: node);

  final _ExplorerContextTargetKind kind;
  final rust_api.WorkspaceNodeItem? node;
}

class _MoveTargetOption {
  const _MoveTargetOption({required this.nodeId, required this.label});

  final String nodeId;
  final String label;
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
