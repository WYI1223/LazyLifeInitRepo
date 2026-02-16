import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';

/// Async range query returning [rust_api.AtomListResponse].
typedef CalendarListByRangeInvoker = Future<rust_api.AtomListResponse> Function({
  required int startMs,
  required int endMs,
  int? limit,
  int? offset,
});

/// Async schedule invoker returning [rust_api.EntryActionResponse].
typedef CalendarScheduleInvoker = Future<rust_api.EntryActionResponse> Function({
  required String title,
  required int startEpochMs,
  int? endEpochMs,
});

/// Async update event times invoker returning [rust_api.EntryActionResponse].
typedef CalendarUpdateEventInvoker = Future<rust_api.EntryActionResponse> Function({
  required String atomId,
  required int startMs,
  required int endMs,
});

/// Pre-load hook used to ensure bridge/db prerequisites.
typedef CalendarPrepare = Future<void> Function();

/// Loading phase for the calendar week view.
enum CalendarPhase { idle, loading, success, error }

/// Stateful controller for the weekly calendar view.
///
/// Manages week navigation, data loading, and event list state.
/// Follows the same injectable invoker pattern as [TasksController].
class CalendarController extends ChangeNotifier {
  CalendarController({
    CalendarListByRangeInvoker? rangeInvoker,
    CalendarScheduleInvoker? scheduleInvoker,
    CalendarUpdateEventInvoker? updateEventInvoker,
    CalendarPrepare? prepare,
    DateTime? initialDate,
  }) : _rangeInvoker = rangeInvoker ?? _defaultRangeInvoker,
       _scheduleInvoker = scheduleInvoker ?? _defaultScheduleInvoker,
       _updateEventInvoker = updateEventInvoker ?? _defaultUpdateEventInvoker,
       _prepare = prepare ?? _defaultPrepare {
    _weekStart = _mondayOf(initialDate ?? DateTime.now());
  }

  final CalendarListByRangeInvoker _rangeInvoker;
  final CalendarScheduleInvoker _scheduleInvoker;
  final CalendarUpdateEventInvoker _updateEventInvoker;
  final CalendarPrepare _prepare;

  late DateTime _weekStart;
  CalendarPhase _phase = CalendarPhase.idle;
  List<rust_api.AtomListItem> _events = const [];
  String? _error;
  int _requestId = 0;

  // -- Public getters --

  /// Monday of the currently displayed week.
  DateTime get weekStart => _weekStart;

  /// Sunday (end) of the currently displayed week.
  DateTime get weekEnd => _weekStart.add(const Duration(days: 6));

  CalendarPhase get phase => _phase;
  List<rust_api.AtomListItem> get events => List.unmodifiable(_events);
  String? get error => _error;

  /// Loads events for the current week.
  Future<void> loadWeek() async {
    final requestId = ++_requestId;
    _phase = CalendarPhase.loading;
    _error = null;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _requestId) return;

      final startMs = _weekStart.millisecondsSinceEpoch;
      // End of Sunday: Monday + 7 days
      final endMs =
          _weekStart.add(const Duration(days: 7)).millisecondsSinceEpoch;

      final response = await _rangeInvoker(
        startMs: startMs,
        endMs: endMs,
        limit: 50,
        offset: 0,
      );
      if (requestId != _requestId) return;

      if (!response.ok) {
        _phase = CalendarPhase.error;
        _error = response.errorCode != null
            ? '[${response.errorCode}] ${response.message}'
            : response.message;
        notifyListeners();
        return;
      }

      _events = List.unmodifiable(response.items);
      _phase = CalendarPhase.success;
      notifyListeners();
    } catch (e) {
      if (requestId != _requestId) return;
      _phase = CalendarPhase.error;
      _error = 'Calendar load failed: $e';
      notifyListeners();
    }
  }

  /// Navigate to the previous week.
  void previousWeek() {
    _weekStart = _weekStart.subtract(const Duration(days: 7));
    notifyListeners();
    loadWeek();
  }

  /// Navigate to the next week.
  void nextWeek() {
    _weekStart = _weekStart.add(const Duration(days: 7));
    notifyListeners();
    loadWeek();
  }

  /// Navigate to the week containing [date].
  void goToWeekOf(DateTime date) {
    _weekStart = _mondayOf(date);
    notifyListeners();
    loadWeek();
  }

  /// Reload the current week.
  Future<void> reload() => loadWeek();

  /// Create a new calendar event and reload the week.
  Future<bool> createEvent(String title, int startMs, int endMs) async {
    try {
      await _prepare();
      final response = await _scheduleInvoker(
        title: title,
        startEpochMs: startMs,
        endEpochMs: endMs,
      );
      if (!response.ok) return false;
      await loadWeek();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update an existing event's times and reload the week.
  Future<bool> updateEvent(String atomId, int startMs, int endMs) async {
    try {
      await _prepare();
      final response = await _updateEventInvoker(
        atomId: atomId,
        startMs: startMs,
        endMs: endMs,
      );
      if (!response.ok) return false;
      await loadWeek();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns Monday (start of week) for the given date.
  static DateTime _mondayOf(DateTime date) {
    final daysFromMonday = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }
}

// -- Default invokers --

Future<rust_api.AtomListResponse> _defaultRangeInvoker({
  required int startMs,
  required int endMs,
  int? limit,
  int? offset,
}) {
  return rust_api.calendarListByRange(
    startMs: startMs,
    endMs: endMs,
    limit: limit,
    offset: offset,
  );
}

Future<rust_api.EntryActionResponse> _defaultScheduleInvoker({
  required String title,
  required int startEpochMs,
  int? endEpochMs,
}) {
  return rust_api.entrySchedule(
    title: title,
    startEpochMs: startEpochMs,
    endEpochMs: endEpochMs,
  );
}

Future<rust_api.EntryActionResponse> _defaultUpdateEventInvoker({
  required String atomId,
  required int startMs,
  required int endMs,
}) {
  return rust_api.calendarUpdateEvent(
    atomId: atomId,
    startMs: startMs,
    endMs: endMs,
  );
}

Future<void> _defaultPrepare() async {
  await RustBridge.ensureEntryDbPathConfigured();
}
