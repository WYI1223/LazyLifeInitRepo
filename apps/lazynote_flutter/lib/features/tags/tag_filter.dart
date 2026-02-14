import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/notes/notes_style.dart';

const int _kCollapsedVisibleTagCount = 6;

/// Single-select tag filter used by Notes explorer.
///
/// Contract:
/// - `selectedTag == null` means unfiltered.
/// - Chips render sorted tags from controller state.
/// - Error state is explicit and retryable.
/// - When tags overflow the collapsed budget, user can expand downward.
class TagFilter extends StatefulWidget {
  const TagFilter({
    super.key,
    required this.loading,
    required this.tags,
    required this.selectedTag,
    required this.errorMessage,
    required this.onSelectTag,
    required this.onClearTag,
    required this.onRetry,
  });

  /// Whether tag catalog request is currently in flight.
  final bool loading;

  /// Available normalized tags.
  final List<String> tags;

  /// Currently selected single filter tag.
  final String? selectedTag;

  /// Error message shown when tag loading fails.
  final String? errorMessage;

  /// Emits one tag selection request.
  final ValueChanged<String> onSelectTag;

  /// Clears active tag filter.
  final VoidCallback onClearTag;

  /// Retries loading available tags.
  final VoidCallback onRetry;

  @override
  State<TagFilter> createState() => _TagFilterState();
}

class _TagFilterState extends State<TagFilter> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant TagFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final canCollapse = widget.tags.length > _kCollapsedVisibleTagCount;
    if (!canCollapse && _expanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_offer_outlined,
                size: 13,
                color: kNotesSecondaryText,
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: kNotesSecondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                key: Key('notes_tag_filter_loading'),
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (widget.errorMessage case final error?)
            Row(
              children: [
                Expanded(
                  child: Text(
                    error,
                    key: const Key('notes_tag_filter_error'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  key: const Key('notes_tag_filter_retry_button'),
                  onPressed: widget.onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: kNotesPrimaryText,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (widget.tags.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'No tags',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: kNotesSecondaryText),
              ),
            )
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _buildTagWrap(context),
            ),
        ],
      ),
    );
  }

  Widget _buildTagWrap(BuildContext context) {
    final canCollapse = widget.tags.length > _kCollapsedVisibleTagCount;
    final visibleTags = _computeVisibleTags(canCollapse: canCollapse);
    final collapsedTagCount = widget.tags.length - visibleTags.length;

    return Wrap(
      key: const Key('notes_tag_filter_wrap'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in visibleTags) _buildTagChip(context, tag),
        if (canCollapse && !_expanded && collapsedTagCount > 0)
          ActionChip(
            key: const Key('notes_tag_filter_expand_button'),
            onPressed: () {
              setState(() {
                _expanded = true;
              });
            },
            side: BorderSide.none,
            backgroundColor: kNotesItemHoverColor,
            label: Text('+$collapsedTagCount more'),
            labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: kNotesSecondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (canCollapse && _expanded)
          ActionChip(
            key: const Key('notes_tag_filter_collapse_button'),
            onPressed: () {
              setState(() {
                _expanded = false;
              });
            },
            side: BorderSide.none,
            backgroundColor: kNotesItemHoverColor,
            label: const Text('Collapse'),
            labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: kNotesSecondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(BuildContext context, String tag) {
    final selected = widget.selectedTag == tag;
    return ChoiceChip(
      key: Key('notes_tag_filter_chip_$tag'),
      selected: selected,
      label: Text('#$tag'),
      onSelected: (enabled) {
        if (!enabled) {
          if (selected) {
            widget.onClearTag();
          }
          return;
        }
        widget.onSelectTag(tag);
      },
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: kNotesItemHoverColor,
      selectedColor: kNotesItemSelectedColor,
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: selected ? kNotesPrimaryText : kNotesSecondaryText,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  List<String> _computeVisibleTags({required bool canCollapse}) {
    if (!canCollapse || _expanded) {
      return widget.tags;
    }

    final selectedTag = widget.selectedTag;
    final base = widget.tags.take(_kCollapsedVisibleTagCount).toList();
    if (selectedTag == null ||
        !widget.tags.contains(selectedTag) ||
        base.contains(selectedTag)) {
      return base;
    }

    // Why: keep currently selected tag visible even in collapsed mode so the
    // active filter state never becomes hidden behind the "+N more" affordance.
    if (base.isNotEmpty) {
      base.removeLast();
    }
    base.add(selectedTag);
    return base;
  }
}
