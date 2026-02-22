import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/notes/notes_style.dart';

/// One rendered node row in workspace explorer tree.
class ExplorerTreeItem extends StatelessWidget {
  const ExplorerTreeItem.folder({
    super.key,
    required this.node,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.canCreateChild,
    required this.canDelete,
    this.onCreateChildFolder,
    this.onDeleteFolder,
    this.onSecondaryTapDown,
  });

  const ExplorerTreeItem.note({
    super.key,
    required this.node,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.onSecondaryTapDown,
  }) : expanded = false,
       canCreateChild = false,
       canDelete = false,
       onCreateChildFolder = null,
       onDeleteFolder = null;

  final rust_api.WorkspaceNodeItem node;
  final int depth;
  final bool selected;
  final bool expanded;
  final bool canCreateChild;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback? onCreateChildFolder;
  final VoidCallback? onDeleteFolder;
  final GestureTapDownCallback? onSecondaryTapDown;

  bool get isFolder => node.kind == 'folder';

  @override
  Widget build(BuildContext context) {
    final leftPadding = 12.0 + depth * 12.0;
    if (isFolder) {
      return Padding(
        padding: EdgeInsets.fromLTRB(leftPadding, 8, 10, 2),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: onSecondaryTapDown == null
              ? null
              : (event) {
                  // Capture right-click at row-level so icon/text hit regions
                  // reliably open context menu.
                  if ((event.buttons & kSecondaryMouseButton) == 0) {
                    return;
                  }
                  onSecondaryTapDown!(
                    TapDownDetails(globalPosition: event.position),
                  );
                },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: onSecondaryTapDown == null
                ? null
                : (details) {
                    onSecondaryTapDown!(
                      TapDownDetails(globalPosition: details.globalPosition),
                    );
                  },
            child: Row(
              children: [
                InkWell(
                  key: Key('notes_tree_toggle_${node.nodeId}'),
                  borderRadius: BorderRadius.circular(4),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: kNotesItemHoverColor,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: kNotesSecondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: kNotesSecondaryText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.displayName,
                    key: Key('notes_tree_folder_${node.nodeId}'),
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
                    key: Key('notes_folder_create_button_${node.nodeId}'),
                    tooltip: 'New child folder',
                    onPressed: onCreateChildFolder,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 14,
                      color: kNotesSecondaryText,
                    ),
                  ),
                if (canDelete)
                  IconButton(
                    key: Key('notes_folder_delete_button_${node.nodeId}'),
                    tooltip: 'Delete folder',
                    onPressed: onDeleteFolder,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: kNotesSecondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final noteId = node.atomId;
    return Padding(
      padding: EdgeInsets.fromLTRB(leftPadding, 0, 8, 0),
      child: Material(
        color: selected ? kNotesItemSelectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: Key('notes_list_item_$noteId'),
          borderRadius: BorderRadius.circular(6),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: kNotesItemHoverColor,
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onLongPress: onSecondaryTapDown == null
              ? null
              : () {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox == null) {
                    return;
                  }
                  final center = renderBox.size.center(Offset.zero);
                  onSecondaryTapDown!(
                    TapDownDetails(
                      globalPosition: renderBox.localToGlobal(center),
                    ),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  kNotesItemPlaceholderIcon,
                  size: 16,
                  color: kNotesSecondaryText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: kNotesPrimaryText,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
}
