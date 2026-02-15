import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazynote_flutter/core/debug/log_reader.dart';
import 'package:lazynote_flutter/features/diagnostics/log_line_meta.dart';

/// Inline live logs panel used across Workbench shell pages.
class DebugLogsPanel extends StatefulWidget {
  const DebugLogsPanel({super.key, this.snapshotLoader});

  /// Test hook to disable periodic refresh and keep pump flows stable.
  static bool autoRefreshEnabled = true;

  /// Optional loader override for widget tests.
  final Future<DebugLogSnapshot> Function()? snapshotLoader;

  @override
  State<DebugLogsPanel> createState() => _DebugLogsPanelState();
}

class _DebugLogsPanelState extends State<DebugLogsPanel>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  DebugLogSnapshot? _snapshot;
  Object? _error;
  String? _actionMessage;
  bool _loading = false;
  DateTime? _lastRefreshAt;
  Timer? _refreshTimer;
  int _latestRefreshRequestId = 0;
  bool _refreshInFlight = false;
  bool _hasQueuedRefresh = false;
  bool _queuedShowLoading = false;

  static const Duration _refreshInterval = Duration(seconds: 3);
  static const double _fallbackLogHeight = 320;
  static const int _maxActionMessageChars = 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLogs(showLoading: true);
    _startAutoRefreshTimerIfNeeded();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_shouldEnableAutoRefresh()) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _startAutoRefreshTimerIfNeeded();
        _refreshLogs(showLoading: false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _refreshTimer?.cancel();
        _refreshTimer = null;
        break;
    }
  }

  bool _shouldEnableAutoRefresh() {
    if (!DebugLogsPanel.autoRefreshEnabled) {
      return false;
    }
    // Why: periodic setState keeps test pump cycles from settling.
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return !bindingName.contains('TestWidgetsFlutterBinding');
  }

  void _startAutoRefreshTimerIfNeeded() {
    if (!_shouldEnableAutoRefresh()) {
      return;
    }
    if (_refreshTimer != null) {
      return;
    }
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      _refreshLogs(showLoading: false);
    });
  }

  Future<void> _refreshLogs({required bool showLoading}) async {
    if (_refreshInFlight) {
      // Why: coalesce overlapping refresh requests into one trailing request
      // to avoid unbounded file-read backlog after long app inactivity.
      _hasQueuedRefresh = true;
      _queuedShowLoading = _queuedShowLoading || showLoading;
      return;
    }

    _refreshInFlight = true;
    final requestId = ++_latestRefreshRequestId;

    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _actionMessage = null;
      });
    }

    try {
      final loader = widget.snapshotLoader ?? LogReader.readLatestTail;
      final snapshot = await loader();
      if (!mounted) {
        return;
      }
      if (requestId != _latestRefreshRequestId) {
        // Ignore stale refresh completion from an older in-flight request.
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
      if (requestId != _latestRefreshRequestId) {
        // Ignore stale refresh failure from an older in-flight request.
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      _refreshInFlight = false;
      if (_hasQueuedRefresh) {
        final nextShowLoading = _queuedShowLoading;
        _hasQueuedRefresh = false;
        _queuedShowLoading = false;
        unawaited(_refreshLogs(showLoading: nextShowLoading));
      }
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

    final lines = const LineSplitter().convert(snapshot.tailText);
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final line in lines) _LogLineRow(line: line)],
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

/// Renders a single log line with a timestamp column and a severity-aware
/// level badge.  Falls back to plain text for lines that do not match the
/// expected [flexi_logger::detailed_format] format.
class _LogLineRow extends StatelessWidget {
  const _LogLineRow({required this.line});

  final String line;

  static const double _timestampWidth = 76;
  static const double _levelWidth = 40;
  static const double _fontSize = 12;

  @override
  Widget build(BuildContext context) {
    final meta = LogLineMeta.parse(line);
    final rowBg = _rowBackground(meta.level);
    final levelColor = _levelColor(context, meta.level);

    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _timestampWidth,
            child: SelectableText(
              meta.timestamp ?? '',
              style: const TextStyle(fontSize: _fontSize),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: _levelWidth,
            child: SelectableText(
              meta.level?.toUpperCase() ?? '',
              style: TextStyle(
                fontSize: _fontSize,
                color: levelColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText(
              meta.message,
              style: const TextStyle(fontSize: _fontSize),
            ),
          ),
        ],
      ),
    );
  }

  Color? _rowBackground(String? level) {
    return switch (level) {
      'error' => Colors.red.shade50,
      'warn' => Colors.amber.shade50,
      _ => null,
    };
  }

  Color _levelColor(BuildContext context, String? level) {
    return switch (level) {
      'error' => Colors.red.shade700,
      'warn' => Colors.orange.shade800,
      'info' => Colors.green.shade700,
      'debug' => Colors.blueGrey.shade600,
      'trace' => Colors.grey.shade600,
      _ => Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87,
    };
  }
}
