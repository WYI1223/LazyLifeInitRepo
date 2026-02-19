import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';

enum _TabContextAction { close, closeOthers, closeRight }

/// Top tab strip managing currently opened notes.
class NoteTabManager extends StatefulWidget {
  const NoteTabManager({
    super.key,
    required this.controller,
    this.openNoteIdsOverride,
    this.activeNoteIdOverride,
  });

  /// Shared notes controller that owns open-tab and active-tab state.
  final NotesController controller;
  final List<String>? openNoteIdsOverride;
  final String? activeNoteIdOverride;

  @override
  State<NoteTabManager> createState() => _NoteTabManagerState();
}

class _NoteTabManagerState extends State<NoteTabManager> {
  final ScrollController _scrollController = ScrollController();
  // Why: keep the custom scroll rail hidden by default to reduce visual noise;
  // it only appears when the pointer is over the tab strip.
  bool _showScrollRail = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setScrollRailVisible(bool value) {
    if (_showScrollRail == value) {
      return;
    }
    setState(() {
      _showScrollRail = value;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }
    // Why: desktop mice often emit vertical-wheel deltas; mapping them to
    // horizontal movement keeps the tab strip scrollable without Shift+wheel.
    final primaryDelta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (primaryDelta == 0) {
      return;
    }
    final maxOffset = _scrollController.position.maxScrollExtent;
    final nextOffset = (_scrollController.offset + primaryDelta)
        .clamp(0.0, maxOffset)
        .toDouble();
    if (nextOffset == _scrollController.offset) {
      return;
    }
    _scrollController.jumpTo(nextOffset);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setScrollRailVisible(true),
      onExit: (_) => _setScrollRailVisible(false),
      child: ColoredBox(
        color: kNotesCanvasBackground,
        child: SizedBox(
          key: const Key('note_tab_manager'),
          height: kNotesTopStripHeight,
          child: _buildTabStrip(context),
        ),
      ),
    );
  }

  Widget _buildTabStrip(BuildContext context) {
    final openNoteIds =
        widget.openNoteIdsOverride ?? widget.controller.openNoteIds;
    final activeNoteId =
        widget.activeNoteIdOverride ?? widget.controller.activeNoteId;
    if (openNoteIds.isEmpty) {
      return Center(
        child: Text(
          'No open notes',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: kNotesSecondaryText),
        ),
      );
    }

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
              itemCount: openNoteIds.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final noteId = openNoteIds[index];
                final active = noteId == activeNoteId;
                return _buildTabChip(context, noteId: noteId, active: active);
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_showScrollRail,
              child: Opacity(
                opacity: _showScrollRail ? 1 : 0,
                child: _TabScrollRail(controller: _scrollController),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(
    BuildContext context, {
    required String noteId,
    required bool active,
  }) {
    final title = widget.controller.titleForTab(noteId);
    final background = active ? Colors.transparent : kNotesSidebarBackground;
    final foreground = active ? kNotesPrimaryText : kNotesSecondaryText;
    final side = active
        ? BorderSide.none
        : const BorderSide(color: kNotesDividerColor);

    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final action = await showMenu<_TabContextAction>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: const [
            PopupMenuItem(value: _TabContextAction.close, child: Text('Close')),
            PopupMenuItem(
              value: _TabContextAction.closeOthers,
              child: Text('Close Others'),
            ),
            PopupMenuItem(
              value: _TabContextAction.closeRight,
              child: Text('Close Right'),
            ),
          ],
        );
        await _handleTabContextAction(noteId: noteId, action: action);
      },
      child: Material(
        key: Key('note_tab_shell_$noteId'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: side,
        ),
        child: InkWell(
          key: Key('note_tab_$noteId'),
          borderRadius: BorderRadius.circular(8),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: kNotesItemHoverColor,
          onTap: () {
            widget.controller.activateOpenNote(noteId);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, maxWidth: 220),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(kNotesItemPlaceholderIcon, size: 13, color: foreground),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  InkWell(
                    key: Key('note_tab_close_$noteId'),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    onTap: () {
                      widget.controller.closeOpenNote(noteId);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 13, color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTabContextAction({
    required String noteId,
    required _TabContextAction? action,
  }) async {
    switch (action) {
      case _TabContextAction.close:
        await widget.controller.closeOpenNote(noteId);
      case _TabContextAction.closeOthers:
        await widget.controller.closeOtherOpenNotes(noteId);
      case _TabContextAction.closeRight:
        await widget.controller.closeOpenNotesToRight(noteId);
      case null:
        return;
    }
  }
}

class _TabScrollRail extends StatelessWidget {
  const _TabScrollRail({required this.controller});

  /// Scroll controller shared with the horizontal tab list.
  ///
  /// Contract:
  /// - Must be attached to the same `ListView` used by tabs.
  /// - When no overflow exists, this rail renders nothing.
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasClients = controller.hasClients;
        final hasDimensions =
            hasClients && controller.position.hasContentDimensions;
        final maxExtent = hasDimensions
            ? controller.position.maxScrollExtent
            : 0.0;
        final viewport = hasDimensions
            ? controller.position.viewportDimension
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              if (trackWidth <= 0) {
                return const SizedBox.shrink();
              }

              // Why: hide the rail when the tab strip has no overflow so users
              // do not see an inactive decoration that cannot be interacted with.
              if (!hasDimensions || maxExtent <= 0 || viewport <= 0) {
                return const SizedBox.shrink();
              }

              final totalExtent = maxExtent + viewport;
              final baseThumbWidth = viewport / totalExtent * trackWidth;
              final thumbWidth = (baseThumbWidth / 2).clamp(
                20.0,
                trackWidth / 2,
              );
              final movableRange = (trackWidth - thumbWidth).clamp(
                0.0,
                trackWidth,
              );
              final ratio = (controller.offset / maxExtent).clamp(0.0, 1.0);
              final thumbLeft = movableRange * ratio;

              double targetRatioForPosition(double localDx) {
                if (movableRange <= 0) {
                  return 0.0;
                }
                return ((localDx - thumbWidth / 2) / movableRange)
                    .clamp(0.0, 1.0)
                    .toDouble();
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final ratioAtTap = targetRatioForPosition(
                    details.localPosition.dx,
                  );
                  controller.jumpTo(ratioAtTap * maxExtent);
                },
                onHorizontalDragUpdate: (details) {
                  if (movableRange <= 0) {
                    return;
                  }
                  final nextOffset =
                      (controller.offset +
                              (details.delta.dx / movableRange) * maxExtent)
                          .clamp(0.0, maxExtent)
                          .toDouble();
                  controller.jumpTo(nextOffset);
                },
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 4,
                        width: trackWidth,
                        color: kNotesDividerColor,
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          height: 4,
                          width: thumbWidth,
                          color: kNotesSecondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
