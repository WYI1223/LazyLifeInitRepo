import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/notes/note_editor.dart';
import 'package:lazynote_flutter/features/notes/notes_controller.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';

/// Center editor/content area for active note.
class NoteContentArea extends StatelessWidget {
  const NoteContentArea({
    super.key,
    required this.controller,
    this.activeNoteIdOverride,
    this.activeDraftContentOverride,
    this.noteSaveStateOverride,
  });

  /// Shared notes controller used to read list/detail snapshots.
  final NotesController controller;
  final String? activeNoteIdOverride;
  final String? activeDraftContentOverride;
  final NoteSaveState? noteSaveStateOverride;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: kNotesCanvasBackground),
      child: _buildContent(context),
    );
  }

  Widget _statusPlaceholder(
    BuildContext context, {
    required String text,
    Key? key,
  }) {
    return Center(
      child: Text(
        text,
        key: key,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: kNotesSecondaryText),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final atomId = activeNoteIdOverride ?? controller.activeNoteId;
    final noteSaveState = noteSaveStateOverride ?? controller.noteSaveState;
    final activeDraftContent =
        activeDraftContentOverride ?? controller.activeDraftContent;
    switch (controller.listPhase) {
      case NotesListPhase.idle:
      case NotesListPhase.loading:
        if (atomId == null) {
          return _statusPlaceholder(context, text: 'Loading notes...');
        }
        break;
      case NotesListPhase.error:
        if (atomId == null) {
          return _statusPlaceholder(
            context,
            text: 'Cannot load detail while list is unavailable.',
          );
        }
        break;
      case NotesListPhase.empty:
        if (atomId == null) {
          return _statusPlaceholder(
            context,
            text: 'Create your first note in C2.',
          );
        }
        break;
      case NotesListPhase.success:
        break;
    }

    if (atomId == null) {
      return _statusPlaceholder(context, text: 'Select a note to continue.');
    }
    if (controller.detailErrorMessage case final error?) {
      return _detailErrorState(context, error: error);
    }
    final note = controller.selectedNote;
    if (note == null && controller.detailLoading) {
      return const Center(
        child: SizedBox(
          key: Key('notes_detail_loading'),
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (note == null) {
      return _statusPlaceholder(
        context,
        text: 'Detail data is not available yet.',
      );
    }

    final saveError = controller.saveErrorMessage;
    return Center(
      child: ConstrainedBox(
        // Why: keep readable document line length on wide desktop windows.
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
          child: Column(
            key: const Key('notes_detail_editor'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Why: in narrow windows keep action area stable by
                  // collapsing secondary actions into one overflow menu.
                  final compactActions = constraints.maxWidth < 520;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vibe Coding for LazyLife > Private',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: kNotesSecondaryText),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TopActionCluster(
                        controller: controller,
                        compact: compactActions,
                        noteSaveState: noteSaveState,
                      ),
                      if (controller.detailLoading)
                        const SizedBox(
                          key: Key('notes_detail_loading'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  );
                },
              ),
              if (controller.switchBlockErrorMessage
                  case final guardError?) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('notes_switch_block_error_banner'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: kNotesErrorBackground,
                  child: Text(
                    guardError,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (noteSaveState == NoteSaveState.error &&
                  saveError != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('notes_save_error_banner'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: kNotesErrorBackground,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          saveError,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(label: 'Add icon', onPressed: () {}),
                  _MetaChip(label: 'Add cover', onPressed: () {}),
                  _MetaChip(label: 'Add comment', onPressed: () {}),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                controller.titleForTab(note.atomId),
                key: const Key('notes_detail_title'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: kNotesPrimaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Updated ${_formatAbsoluteTime(note.updatedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: kNotesSecondaryText),
              ),
              const SizedBox(height: 12),
              _NoteTagsSection(
                tags: note.tags,
                onAddTag: (tag) {
                  unawaited(controller.addTagToActiveNote(tag));
                },
                onRemoveTag: (tag) {
                  unawaited(controller.removeTagFromActiveNote(tag));
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: NoteEditor(
                  key: ValueKey<String>('note_editor_$atomId'),
                  content: activeDraftContent,
                  focusRequestId: controller.editorFocusRequestId,
                  onChanged: controller.updateActiveDraft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailErrorState(BuildContext context, {required String error}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            key: const Key('notes_detail_error_center'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                key: const Key('notes_detail_error'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kNotesPrimaryText),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('notes_detail_retry_button'),
                onPressed: controller.refreshSelectedDetail,
                child: const Text('Retry detail'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    this.buttonKey,
    this.label,
    this.icon,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (label case final value?) {
      return TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: kNotesSecondaryText,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(value),
      );
    }
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon, color: kNotesSecondaryText),
      iconSize: 18,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      visualDensity: VisualDensity.compact,
      tooltip: '',
    );
  }
}

class _SaveStatusWidget extends StatelessWidget {
  const _SaveStatusWidget({
    required this.controller,
    required this.compact,
    required this.noteSaveState,
  });

  final NotesController controller;
  final bool compact;
  final NoteSaveState noteSaveState;

  @override
  Widget build(BuildContext context) {
    switch (noteSaveState) {
      case NoteSaveState.clean:
        if (!controller.showSavedBadge) {
          return const SizedBox(
            key: Key('notes_save_status_idle'),
            width: 1,
            height: 1,
          );
        }
        return Row(
          key: const Key('notes_save_status_saved'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, size: 14, color: Color(0xFF2E7D32)),
            if (!compact) ...const [SizedBox(width: 4), Text('Saved')],
          ],
        );
      case NoteSaveState.dirty:
        return Row(
          key: const Key('notes_save_status_dirty'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 7, color: kNotesSecondaryText),
            if (!compact) ...const [SizedBox(width: 5), Text('Unsaved')],
          ],
        );
      case NoteSaveState.saving:
        return Row(
          key: const Key('notes_save_status_saving'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
            if (!compact) ...const [SizedBox(width: 6), Text('Saving...')],
          ],
        );
      case NoteSaveState.error:
        final fullError = controller.saveErrorMessage ?? 'Save failed';
        if (compact) {
          return Row(
            key: const Key('notes_save_status_error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: fullError,
                child: const Icon(
                  Icons.error_outline,
                  size: 14,
                  color: Colors.redAccent,
                ),
              ),
              IconButton(
                key: const Key('notes_save_retry_button'),
                onPressed: () {
                  controller.retrySaveCurrentDraft();
                },
                icon: const Icon(
                  Icons.refresh,
                  size: 14,
                  color: Colors.redAccent,
                ),
                tooltip: 'Retry save',
                visualDensity: VisualDensity.compact,
              ),
            ],
          );
        }
        return Row(
          key: const Key('notes_save_status_error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: fullError,
              child: const Icon(
                Icons.error_outline,
                size: 14,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              // Why: keep top-right action row stable; long backend error text
              // is rendered by the dedicated save-error banner below.
              'Save failed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            ),
            const SizedBox(width: 6),
            TextButton(
              key: const Key('notes_save_retry_button'),
              onPressed: () {
                controller.retrySaveCurrentDraft();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              child: const Text('Retry'),
            ),
          ],
        );
    }
  }
}

enum _TopOverflowAction { share, star, more }

class _TopActionCluster extends StatelessWidget {
  const _TopActionCluster({
    required this.controller,
    required this.compact,
    required this.noteSaveState,
  });

  final NotesController controller;
  final bool compact;
  final NoteSaveState noteSaveState;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SaveStatusWidget(
          controller: controller,
          compact: compact,
          noteSaveState: noteSaveState,
        ),
        const SizedBox(width: 6),
        IconButton(
          key: const Key('notes_detail_refresh_button'),
          tooltip: 'Refresh detail',
          onPressed: controller.refreshSelectedDetail,
          icon: const Icon(Icons.refresh, color: kNotesSecondaryText),
          iconSize: 18,
          visualDensity: VisualDensity.compact,
        ),
        if (compact)
          const _MoreActionsMenuButton(
            buttonKey: Key('notes_detail_overflow_menu_button'),
          )
        else ...[
          _TopActionButton(
            buttonKey: const Key('notes_detail_share_button'),
            label: 'Share',
            onPressed: () {},
          ),
          _TopActionButton(
            buttonKey: const Key('notes_detail_star_button'),
            icon: Icons.star_border,
            onPressed: () {},
          ),
          const _MoreActionsMenuButton(
            buttonKey: Key('notes_detail_more_menu_button'),
          ),
        ],
      ],
    );
  }
}

class _MoreActionsMenuButton extends StatelessWidget {
  const _MoreActionsMenuButton({required this.buttonKey});

  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TopOverflowAction>(
      key: buttonKey,
      tooltip: 'More actions',
      onSelected: (_) {},
      itemBuilder: (context) {
        return const [
          PopupMenuItem(value: _TopOverflowAction.share, child: Text('Share')),
          PopupMenuItem(value: _TopOverflowAction.star, child: Text('Star')),
          PopupMenuItem(value: _TopOverflowAction.more, child: Text('More')),
        ];
      },
      icon: const Icon(Icons.more_horiz, size: 18, color: kNotesSecondaryText),
    );
  }
}

class _NoteTagsSection extends StatelessWidget {
  const _NoteTagsSection({
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  final List<String> tags;
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('notes_tags_section'),
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          InputChip(
            key: Key('notes_tag_chip_$tag'),
            label: Text('#$tag'),
            onDeleted: () {
              onRemoveTag(tag);
            },
            deleteIcon: const Icon(Icons.close, size: 14),
            visualDensity: VisualDensity.compact,
            backgroundColor: kNotesItemHoverColor,
            side: BorderSide.none,
            labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: kNotesPrimaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        TextButton.icon(
          key: const Key('notes_add_tag_button'),
          onPressed: () async {
            final entered = await _promptTagInput(context);
            if (entered == null) {
              return;
            }
            onAddTag(entered);
          },
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Tag'),
          style: TextButton.styleFrom(
            foregroundColor: kNotesSecondaryText,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: kNotesSecondaryText,
        backgroundColor: kNotesItemHoverColor,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(label),
    );
  }
}

Future<String?> _promptTagInput(BuildContext context) async {
  var draft = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Add tag'),
        content: TextField(
          key: const Key('notes_add_tag_input'),
          autofocus: true,
          decoration: const InputDecoration(hintText: 'tag'),
          onChanged: (value) {
            draft = value;
          },
          onSubmitted: (value) {
            Navigator.of(dialogContext).pop(value);
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
            key: const Key('notes_add_tag_submit_button'),
            onPressed: () {
              Navigator.of(dialogContext).pop(draft);
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );
}

String _formatAbsoluteTime(int epochMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
