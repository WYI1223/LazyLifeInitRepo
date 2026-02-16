import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';

/// Async section list loader returning [rust_api.AtomListResponse].
typedef TasksListInboxInvoker =
    Future<rust_api.AtomListResponse> Function({int? limit, int? offset});

/// Async today list loader with device-local day boundaries.
typedef TasksListTodayInvoker =
    Future<rust_api.AtomListResponse> Function({
      required int bodMs,
      required int eodMs,
      int? limit,
      int? offset,
    });

/// Async upcoming list loader with end-of-day boundary.
typedef TasksListUpcomingInvoker =
    Future<rust_api.AtomListResponse> Function({
      required int eodMs,
      int? limit,
      int? offset,
    });

/// Async status updater returning [rust_api.EntryActionResponse].
typedef AtomUpdateStatusInvoker =
    Future<rust_api.EntryActionResponse> Function({
      required String atomId,
      String? status,
    });

/// Async note creator for inline inbox creation.
typedef InboxCreateInvoker =
    Future<rust_api.EntryActionResponse> Function({required String content});

/// Pre-load hook used to ensure bridge/db prerequisites.
typedef TasksPrepare = Future<void> Function();

/// Section loading phase.
enum TasksPhase {
  /// No load has started yet.
  idle,

  /// Request is currently in flight.
  loading,

  /// Request succeeded.
  success,

  /// Request failed and carries an error message.
  error,
}

/// Stateful controller for Tasks page (Inbox / Today / Upcoming).
///
/// Contract:
/// - Owns three independent section list states.
/// - Handles checkbox toggle (status update) with immediate list removal.
/// - Handles inline inbox note creation.
/// - Calls [notifyListeners] after every externally visible state transition.
class TasksController extends ChangeNotifier {
  TasksController({
    TasksListInboxInvoker? inboxInvoker,
    TasksListTodayInvoker? todayInvoker,
    TasksListUpcomingInvoker? upcomingInvoker,
    AtomUpdateStatusInvoker? statusInvoker,
    InboxCreateInvoker? createInvoker,
    TasksPrepare? prepare,
  }) : _inboxInvoker = inboxInvoker ?? _defaultInboxInvoker,
       _todayInvoker = todayInvoker ?? _defaultTodayInvoker,
       _upcomingInvoker = upcomingInvoker ?? _defaultUpcomingInvoker,
       _statusInvoker = statusInvoker ?? _defaultStatusInvoker,
       _createInvoker = createInvoker ?? _defaultCreateInvoker,
       _prepare = prepare ?? _defaultPrepare;

  final TasksListInboxInvoker _inboxInvoker;
  final TasksListTodayInvoker _todayInvoker;
  final TasksListUpcomingInvoker _upcomingInvoker;
  final AtomUpdateStatusInvoker _statusInvoker;
  final InboxCreateInvoker _createInvoker;
  final TasksPrepare _prepare;

  // -- Inbox state --
  TasksPhase _inboxPhase = TasksPhase.idle;
  List<rust_api.AtomListItem> _inboxItems = const [];
  String? _inboxError;
  int _inboxRequestId = 0;

  // -- Today state --
  TasksPhase _todayPhase = TasksPhase.idle;
  List<rust_api.AtomListItem> _todayItems = const [];
  String? _todayError;
  int _todayRequestId = 0;

  // -- Upcoming state --
  TasksPhase _upcomingPhase = TasksPhase.idle;
  List<rust_api.AtomListItem> _upcomingItems = const [];
  String? _upcomingError;
  int _upcomingRequestId = 0;

  // -- Inline create state --
  bool _creating = false;
  String? _createError;

  // -- Public getters --
  TasksPhase get inboxPhase => _inboxPhase;
  List<rust_api.AtomListItem> get inboxItems => List.unmodifiable(_inboxItems);
  String? get inboxError => _inboxError;

  TasksPhase get todayPhase => _todayPhase;
  List<rust_api.AtomListItem> get todayItems => List.unmodifiable(_todayItems);
  String? get todayError => _todayError;

  TasksPhase get upcomingPhase => _upcomingPhase;
  List<rust_api.AtomListItem> get upcomingItems =>
      List.unmodifiable(_upcomingItems);
  String? get upcomingError => _upcomingError;

  bool get creating => _creating;
  String? get createError => _createError;

  /// Loads all three sections in parallel.
  Future<void> loadAll() async {
    await Future.wait([_loadInbox(), _loadToday(), _loadUpcoming()]);
  }

  /// Reloads all three sections.
  Future<void> reload() => loadAll();

  /// Toggles an atom's status between null/done.
  ///
  /// When `currentStatus` is `"done"`, clears status (demote).
  /// Otherwise sets status to `"done"`.
  /// On success, immediately removes the item from its section list.
  Future<bool> toggleStatus(String atomId, String? currentStatus) async {
    final nextStatus = currentStatus == 'done' ? null : 'done';
    try {
      await _prepare();
      final response = await _statusInvoker(atomId: atomId, status: nextStatus);
      if (!response.ok) {
        return false;
      }
      _removeItemFromAllSections(atomId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a new inbox note with the given content.
  ///
  /// On success, reloads inbox to reflect the new item.
  Future<bool> createInboxItem(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_creating) {
      return false;
    }
    _creating = true;
    _createError = null;
    notifyListeners();

    try {
      await _prepare();
      final response = await _createInvoker(content: trimmed);
      if (!response.ok) {
        _creating = false;
        _createError = response.message;
        notifyListeners();
        return false;
      }
      _creating = false;
      _createError = null;
      notifyListeners();
      await _loadInbox();
      return true;
    } catch (error) {
      _creating = false;
      _createError = 'Create failed: $error';
      notifyListeners();
      return false;
    }
  }

  // -- Private section loaders --

  Future<void> _loadInbox() async {
    final requestId = ++_inboxRequestId;
    _inboxPhase = TasksPhase.loading;
    _inboxError = null;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _inboxRequestId) return;

      final response = await _inboxInvoker(limit: 50, offset: 0);
      if (requestId != _inboxRequestId) return;

      if (!response.ok) {
        _inboxPhase = TasksPhase.error;
        _inboxError = _extractError(response);
        notifyListeners();
        return;
      }
      _inboxItems = List.unmodifiable(response.items);
      _inboxPhase = TasksPhase.success;
      notifyListeners();
    } catch (error) {
      if (requestId != _inboxRequestId) return;
      _inboxPhase = TasksPhase.error;
      _inboxError = 'Inbox load failed: $error';
      notifyListeners();
    }
  }

  Future<void> _loadToday() async {
    final requestId = ++_todayRequestId;
    _todayPhase = TasksPhase.loading;
    _todayError = null;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _todayRequestId) return;

      final now = DateTime.now();
      final bod = DateTime(now.year, now.month, now.day);
      final eod = bod
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final bodMs = bod.millisecondsSinceEpoch;
      final eodMs = eod.millisecondsSinceEpoch;

      final response = await _todayInvoker(
        bodMs: bodMs,
        eodMs: eodMs,
        limit: 50,
        offset: 0,
      );
      if (requestId != _todayRequestId) return;

      if (!response.ok) {
        _todayPhase = TasksPhase.error;
        _todayError = _extractError(response);
        notifyListeners();
        return;
      }
      _todayItems = List.unmodifiable(response.items);
      _todayPhase = TasksPhase.success;
      notifyListeners();
    } catch (error) {
      if (requestId != _todayRequestId) return;
      _todayPhase = TasksPhase.error;
      _todayError = 'Today load failed: $error';
      notifyListeners();
    }
  }

  Future<void> _loadUpcoming() async {
    final requestId = ++_upcomingRequestId;
    _upcomingPhase = TasksPhase.loading;
    _upcomingError = null;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _upcomingRequestId) return;

      final now = DateTime.now();
      final bod = DateTime(now.year, now.month, now.day);
      final eod = bod
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final eodMs = eod.millisecondsSinceEpoch;

      final response = await _upcomingInvoker(
        eodMs: eodMs,
        limit: 50,
        offset: 0,
      );
      if (requestId != _upcomingRequestId) return;

      if (!response.ok) {
        _upcomingPhase = TasksPhase.error;
        _upcomingError = _extractError(response);
        notifyListeners();
        return;
      }
      _upcomingItems = List.unmodifiable(response.items);
      _upcomingPhase = TasksPhase.success;
      notifyListeners();
    } catch (error) {
      if (requestId != _upcomingRequestId) return;
      _upcomingPhase = TasksPhase.error;
      _upcomingError = 'Upcoming load failed: $error';
      notifyListeners();
    }
  }

  void _removeItemFromAllSections(String atomId) {
    _inboxItems = List.unmodifiable(
      _inboxItems.where((item) => item.atomId != atomId),
    );
    _todayItems = List.unmodifiable(
      _todayItems.where((item) => item.atomId != atomId),
    );
    _upcomingItems = List.unmodifiable(
      _upcomingItems.where((item) => item.atomId != atomId),
    );
  }

  String _extractError(rust_api.AtomListResponse response) {
    final msg = response.message.trim();
    if (response.errorCode case final code?) {
      return '[$code] ${msg.isEmpty ? "Unknown error" : msg}';
    }
    return msg.isEmpty ? 'Unknown error' : msg;
  }
}

// -- Default invokers --

Future<rust_api.AtomListResponse> _defaultInboxInvoker({
  int? limit,
  int? offset,
}) {
  return rust_api.tasksListInbox(limit: limit, offset: offset);
}

Future<rust_api.AtomListResponse> _defaultTodayInvoker({
  required int bodMs,
  required int eodMs,
  int? limit,
  int? offset,
}) {
  return rust_api.tasksListToday(
    bodMs: bodMs,
    eodMs: eodMs,
    limit: limit,
    offset: offset,
  );
}

Future<rust_api.AtomListResponse> _defaultUpcomingInvoker({
  required int eodMs,
  int? limit,
  int? offset,
}) {
  return rust_api.tasksListUpcoming(eodMs: eodMs, limit: limit, offset: offset);
}

Future<rust_api.EntryActionResponse> _defaultStatusInvoker({
  required String atomId,
  String? status,
}) {
  return rust_api.atomUpdateStatus(atomId: atomId, status: status);
}

Future<rust_api.EntryActionResponse> _defaultCreateInvoker({
  required String content,
}) {
  return rust_api.entryCreateNote(content: content);
}

Future<void> _defaultPrepare() async {
  await RustBridge.ensureEntryDbPathConfigured();
}
