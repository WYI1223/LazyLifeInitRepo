import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazynote_flutter/core/debug/log_reader.dart';

/// Inline live logs panel used across Workbench shell pages.
class DebugLogsPanel extends StatefulWidget {
  const DebugLogsPanel({super.key});

  /// Test hook to disable periodic refresh and keep pump flows stable.
  static bool autoRefreshEnabled = true;

  @override
  State<DebugLogsPanel> createState() => _DebugLogsPanelState();
}

class _DebugLogsPanelState extends State<DebugLogsPanel> {
  final ScrollController _scrollController = ScrollController();

  DebugLogSnapshot? _snapshot;
  Object? _error;
  String? _actionMessage;
  bool _loading = false;
  DateTime? _lastRefreshAt;
  Timer? _refreshTimer;

  static const Duration _refreshInterval = Duration(seconds: 3);
  static const double _fallbackLogHeight = 320;
  static const int _maxActionMessageChars = 180;

  @override
  void initState() {
    super.initState();
    _refreshLogs(showLoading: true);
    if (_shouldEnableAutoRefresh()) {
      _refreshTimer = Timer.periodic(_refreshInterval, (_) {
        _refreshLogs(showLoading: false);
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool _shouldEnableAutoRefresh() {
    if (!DebugLogsPanel.autoRefreshEnabled) {
      return false;
    }
    // Why: periodic setState keeps test pump cycles from settling.
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return !bindingName.contains('TestWidgetsFlutterBinding');
  }

  Future<void> _refreshLogs({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _actionMessage = null;
      });
    }

    try {
      final snapshot = await LogReader.readLatestTail();
      if (!mounted) {
        return;
      }
      final changed = !_sameSnapshot(_snapshot, snapshot);
      if (!showLoading && !changed && _error == null) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
        _lastRefreshAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  bool _sameSnapshot(DebugLogSnapshot? left, DebugLogSnapshot right) {
    if (left == null) {
      return false;
    }
    // Why: skip repaint when source file and visible tail text are unchanged,
    // reducing unnecessary frame churn during periodic refresh.
    return left.logDir == right.logDir &&
        left.tailText == right.tailText &&
        left.warningMessage == right.warningMessage &&
        left.activeFile?.path == right.activeFile?.path &&
        left.activeFile?.modifiedAt == right.activeFile?.modifiedAt &&
        left.files.length == right.files.length;
  }

  void _setActionMessage(String message) {
    final normalized = message.replaceAll('\n', ' ').replaceAll('\r', ' ');
    final truncated = normalized.length > _maxActionMessageChars
        ? '${normalized.substring(0, _maxActionMessageChars)}...'
        : normalized;
    setState(() {
      _actionMessage = truncated;
    });
  }

  Future<void> _copyVisibleLogs() async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.tailText.isEmpty) {
      _setActionMessage('No visible logs to copy.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: snapshot.tailText));
    if (!mounted) {
      return;
    }
    _setActionMessage('Visible logs copied.');
  }

  Future<void> _openLogFolder() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    try {
      await LogReader.openLogFolder(snapshot.logDir);
      if (!mounted) {
        return;
      }
      _setActionMessage('Opened log folder.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setActionMessage('Open folder failed: $error');
    }
  }

  String _formatRefreshTime(DateTime? value) {
    if (value == null) {
      return 'never';
    }

    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Widget _buildLogContent() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SelectableText('Failed to load logs: $_error');
    }

    final snapshot = _snapshot;
    if (snapshot == null || snapshot.tailText.isEmpty) {
      return const SelectableText('No log content available yet.');
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: SelectableText(
          snapshot.tailText,
          key: const Key('workbench_debug_logs_text'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight =
                constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

            final headerChildren = <Widget>[
              Text(
                'Debug Logs (Live)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Auto refresh: every ${_refreshInterval.inSeconds}s',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Last refresh: ${_formatRefreshTime(_lastRefreshAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ];

            if (snapshot != null) {
              headerChildren.addAll([
                const SizedBox(height: 8),
                Text(
                  'Directory: ${snapshot.logDir}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Active file: ${snapshot.activeFile?.name ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]);
            }

            final actionChildren = <Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _refreshLogs(showLoading: true),
                    child: const Text('Refresh'),
                  ),
                  OutlinedButton(
                    onPressed: _copyVisibleLogs,
                    child: const Text('Copy Visible Logs'),
                  ),
                  OutlinedButton(
                    onPressed: _openLogFolder,
                    child: const Text('Open Log Folder'),
                  ),
                ],
              ),
            ];

            if (_actionMessage != null) {
              actionChildren.addAll([
                const SizedBox(height: 8),
                Text(
                  _actionMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]);
            }

            final logArea = hasBoundedHeight
                ? Expanded(child: _buildLogContent())
                : SizedBox(
                    height: _fallbackLogHeight,
                    child: _buildLogContent(),
                  );

            return Column(
              mainAxisSize: hasBoundedHeight
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...headerChildren,
                ...actionChildren,
                const SizedBox(height: 12),
                logArea,
              ],
            );
          },
        ),
      ),
    );
  }
}
