import 'package:flutter/material.dart';
import 'package:lazynote_flutter/features/diagnostics/debug_logs_panel.dart';

/// Shared shell layout: left content area + right debug logs panel.
///
/// In wide mode, users can drag the vertical splitter to resize both panes.
class WorkbenchShellLayout extends StatefulWidget {
  const WorkbenchShellLayout({
    super.key,
    required this.title,
    required this.content,
  });

  final String title;
  final Widget content;

  @override
  State<WorkbenchShellLayout> createState() => _WorkbenchShellLayoutState();
}

class _WorkbenchShellLayoutState extends State<WorkbenchShellLayout> {
  static const double _defaultRightPaneWidth = 420;
  static const double _minLeftPaneWidth = 520;
  static const double _minRightPaneWidth = 320;
  static const double _maxRightPaneWidth = 760;
  static const double _splitterWidth = 12;

  double _rightPaneWidth = _defaultRightPaneWidth;

  double _maxRightPaneWidthByLayout(double totalWidth) {
    // Why: enforce a minimum left work area while allowing users to resize
    // right logs panel; this prevents splitter drag from collapsing content.
    final maxByLayout = totalWidth - _splitterWidth - _minLeftPaneWidth;
    final boundedMax = maxByLayout < _minRightPaneWidth
        ? _minRightPaneWidth
        : maxByLayout;
    return boundedMax < _maxRightPaneWidth ? boundedMax : _maxRightPaneWidth;
  }

  double _effectiveRightPaneWidth(double totalWidth) {
    final maxAllowed = _maxRightPaneWidthByLayout(totalWidth);
    return _rightPaneWidth.clamp(_minRightPaneWidth, maxAllowed).toDouble();
  }

  void _handleDragUpdate(DragUpdateDetails details, double totalWidth) {
    final maxAllowed = _maxRightPaneWidthByLayout(totalWidth);
    // Right pane width changes opposite to drag delta because splitter sits
    // between panes and we resize the trailing panel directly.
    final next = (_rightPaneWidth - details.delta.dx)
        .clamp(_minRightPaneWidth, maxAllowed)
        .toDouble();
    if (next == _rightPaneWidth) {
      return;
    }
    setState(() {
      _rightPaneWidth = next;
    });
  }

  Widget _buildWideLayout(double width) {
    final effectiveRightWidth = _effectiveRightPaneWidth(width);
    final leftWidth = width - _splitterWidth - effectiveRightWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: leftWidth,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: widget.content),
            ),
          ),
        ),
        SizedBox(
          width: _splitterWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  _handleDragUpdate(details, width),
              onDoubleTap: () {
                setState(() {
                  _rightPaneWidth = _defaultRightPaneWidth;
                });
              },
              child: const Center(child: VerticalDivider(width: 1)),
            ),
          ),
        ),
        SizedBox(width: effectiveRightWidth, child: const DebugLogsPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: widget.content,
            ),
          ),
          const SizedBox(height: 16),
          const DebugLogsPanel(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: appBarColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wideLayout = constraints.maxWidth >= 1200;
            final bodyPadding = const EdgeInsets.all(24);
            final maxWidth = wideLayout ? 1440.0 : 980.0;

            return Padding(
              padding: bodyPadding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: LayoutBuilder(
                    builder: (context, shellConstraints) {
                      return wideLayout
                          ? _buildWideLayout(shellConstraints.maxWidth)
                          : _buildNarrowLayout();
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
