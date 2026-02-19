import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/features/workspace/workspace_models.dart';

/// Async saver used by workspace buffers.
typedef WorkspaceSaveInvoker =
    Future<bool> Function({required String noteId, required String content});

/// Async tag mutation used by workspace queue.
typedef WorkspaceTagMutationInvoker =
    Future<bool> Function({required String noteId, required List<String> tags});

/// Timer factory for autosave debounce.
typedef WorkspaceDebounceTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Workspace runtime owner for pane/tab/buffer/save state.
class WorkspaceProvider extends ChangeNotifier {
  WorkspaceProvider({
    WorkspaceSaveInvoker? saveInvoker,
    WorkspaceTagMutationInvoker? tagMutationInvoker,
    WorkspaceDebounceTimerFactory? debounceTimerFactory,
    this.autosaveDebounce = const Duration(milliseconds: 800),
    this.flushMaxRetries = 5,
    this.autosaveEnabled = true,
  }) : _saveInvoker = saveInvoker ?? _defaultSaveInvoker,
       _tagMutationInvoker = tagMutationInvoker ?? _defaultTagMutationInvoker,
       _debounceTimerFactory = debounceTimerFactory ?? Timer.new {
    final paneId = _layoutState.primaryPaneId;
    _activePaneId = paneId;
    _openTabsByPane[paneId] = <String>[];
    _activeTabByPane[paneId] = null;
  }

  final WorkspaceSaveInvoker _saveInvoker;
  final WorkspaceTagMutationInvoker _tagMutationInvoker;
  final WorkspaceDebounceTimerFactory _debounceTimerFactory;

  /// Debounce delay before autosave starts.
  final Duration autosaveDebounce;

  /// Maximum flush retry attempts for one request.
  final int flushMaxRetries;

  /// Whether draft updates should schedule internal autosave.
  final bool autosaveEnabled;

  final WorkspaceLayoutState _layoutState = WorkspaceLayoutState.singlePane();
  String _activePaneId = '';

  final Map<String, List<String>> _openTabsByPane = <String, List<String>>{};
  final Map<String, String?> _activeTabByPane = <String, String?>{};
  final Map<String, WorkspaceNoteBuffer> _buffersByNoteId =
      <String, WorkspaceNoteBuffer>{};
  final Map<String, WorkspaceSaveState> _saveStateByNoteId =
      <String, WorkspaceSaveState>{};
  final Map<String, Timer> _saveDebounceByNoteId = <String, Timer>{};
  final Map<String, Future<bool>> _saveInFlightByNoteId =
      <String, Future<bool>>{};
  final Map<String, Future<void>> _tagMutationQueueByNoteId =
      <String, Future<void>>{};

  WorkspaceLayoutState get layoutState => _layoutState;

  String get activePaneId => _activePaneId;

  String? get activeNoteId => _activeTabByPane[_activePaneId];

  /// Active editor draft is always derived from note buffer map.
  String get activeDraftContent {
    final active = activeNoteId;
    if (active == null) {
      return '';
    }
    return _buffersByNoteId[active]?.draftContent ?? '';
  }

  Map<String, List<String>> get openTabsByPane => UnmodifiableMapView(
    _openTabsByPane.map(
      (key, value) =>
          MapEntry<String, List<String>>(key, List.unmodifiable(value)),
    ),
  );

  Map<String, String?> get activeTabByPane =>
      UnmodifiableMapView(_activeTabByPane);

  Map<String, WorkspaceNoteBuffer> get buffersByNoteId =>
      UnmodifiableMapView(_buffersByNoteId);

  Map<String, WorkspaceSaveState> get saveStateByNoteId =>
      UnmodifiableMapView(_saveStateByNoteId);

  @override
  void dispose() {
    for (final timer in _saveDebounceByNoteId.values) {
      timer.cancel();
    }
    _saveDebounceByNoteId.clear();
    super.dispose();
  }

  void switchActivePane(String paneId) {
    if (_activePaneId == paneId) {
      return;
    }
    _openTabsByPane.putIfAbsent(paneId, () => <String>[]);
    _activeTabByPane.putIfAbsent(paneId, () => null);
    _activePaneId = paneId;
    notifyListeners();
  }

  void openNote({
    required String noteId,
    required String initialContent,
    String? paneId,
  }) {
    final targetPaneId = paneId ?? _activePaneId;
    final tabs = _openTabsByPane.putIfAbsent(targetPaneId, () => <String>[]);
    if (!tabs.contains(noteId)) {
      tabs.add(noteId);
    }
    _activeTabByPane[targetPaneId] = noteId;
    _activePaneId = targetPaneId;

    _buffersByNoteId.putIfAbsent(
      noteId,
      () => WorkspaceNoteBuffer(
        noteId: noteId,
        persistedContent: initialContent,
        draftContent: initialContent,
        version: 0,
      ),
    );
    _saveStateByNoteId.putIfAbsent(noteId, () => WorkspaceSaveState.clean);
    notifyListeners();
  }

  void activateNote({required String noteId, String? paneId}) {
    final targetPaneId = paneId ?? _activePaneId;
    final tabs = _openTabsByPane.putIfAbsent(targetPaneId, () => <String>[]);
    if (!tabs.contains(noteId)) {
      return;
    }
    _activeTabByPane[targetPaneId] = noteId;
    _activePaneId = targetPaneId;
    notifyListeners();
  }

  void closeNote({required String noteId, String? paneId}) {
    final targetPaneId = paneId ?? _activePaneId;
    final tabs = _openTabsByPane[targetPaneId];
    if (tabs == null || !tabs.remove(noteId)) {
      return;
    }
    final active = _activeTabByPane[targetPaneId];
    if (active == noteId) {
      _activeTabByPane[targetPaneId] = tabs.isEmpty ? null : tabs.last;
    }

    if (!_isNoteOpen(noteId)) {
      _saveDebounceByNoteId.remove(noteId)?.cancel();
      _saveInFlightByNoteId.remove(noteId);
      _saveStateByNoteId.remove(noteId);
      _buffersByNoteId.remove(noteId);
    }
    notifyListeners();
  }

  void updateDraft({required String noteId, required String content}) {
    final current = _buffersByNoteId[noteId];
    if (current == null) {
      return;
    }
    if (current.draftContent == content) {
      return;
    }
    _buffersByNoteId[noteId] = current.copyWith(
      draftContent: content,
      version: current.version + 1,
    );
    _saveStateByNoteId[noteId] = WorkspaceSaveState.dirty;
    if (autosaveEnabled) {
      _scheduleAutosave(noteId);
    }
    notifyListeners();
  }

  /// Sync one note snapshot from external owner (e.g. NotesController).
  void syncExternalNote({
    required String noteId,
    required String persistedContent,
    required String draftContent,
    WorkspaceSaveState? saveState,
    bool activate = false,
    String? paneId,
  }) {
    final targetPaneId = paneId ?? _activePaneId;
    final tabs = _openTabsByPane.putIfAbsent(targetPaneId, () => <String>[]);
    if (!tabs.contains(noteId)) {
      tabs.add(noteId);
    }
    if (activate) {
      _activePaneId = targetPaneId;
      _activeTabByPane[targetPaneId] = noteId;
    } else {
      _activeTabByPane.putIfAbsent(targetPaneId, () => null);
    }

    final previous = _buffersByNoteId[noteId];
    _buffersByNoteId[noteId] = WorkspaceNoteBuffer(
      noteId: noteId,
      persistedContent: persistedContent,
      draftContent: draftContent,
      version: previous?.version ?? 0,
    );
    _saveStateByNoteId[noteId] =
        saveState ??
        (draftContent == persistedContent
            ? WorkspaceSaveState.clean
            : WorkspaceSaveState.dirty);
    notifyListeners();
  }

  /// Sync save-state only for existing note buffer.
  void syncSaveState({
    required String noteId,
    required WorkspaceSaveState saveState,
  }) {
    if (!_buffersByNoteId.containsKey(noteId)) {
      return;
    }
    _saveStateByNoteId[noteId] = saveState;
    notifyListeners();
  }

  /// Clears pane/tab/buffer/save state.
  void resetAll() {
    for (final timer in _saveDebounceByNoteId.values) {
      timer.cancel();
    }
    _saveDebounceByNoteId.clear();
    _saveInFlightByNoteId.clear();
    _tagMutationQueueByNoteId.clear();
    _openTabsByPane
      ..clear()
      ..[_layoutState.primaryPaneId] = <String>[];
    _activeTabByPane
      ..clear()
      ..[_layoutState.primaryPaneId] = null;
    _buffersByNoteId.clear();
    _saveStateByNoteId.clear();
    _activePaneId = _layoutState.primaryPaneId;
    notifyListeners();
  }

  Future<bool> flushActiveNote() async {
    final noteId = activeNoteId;
    if (noteId == null) {
      return true;
    }
    return flushNote(noteId);
  }

  Future<bool> flushNote(String noteId) async {
    _saveDebounceByNoteId.remove(noteId)?.cancel();
    for (var attempt = 0; attempt < flushMaxRetries; attempt += 1) {
      final buffer = _buffersByNoteId[noteId];
      if (buffer == null || !buffer.isDirty) {
        _saveStateByNoteId[noteId] = WorkspaceSaveState.clean;
        notifyListeners();
        return true;
      }
      final expectedVersion = buffer.version;
      final saved = await _saveDraftVersion(
        noteId: noteId,
        expectedVersion: expectedVersion,
      );
      final latest = _buffersByNoteId[noteId];
      if (saved && latest != null && !latest.isDirty) {
        return true;
      }
      if (latest != null && latest.version != expectedVersion) {
        continue;
      }
    }
    if (_buffersByNoteId.containsKey(noteId)) {
      _saveStateByNoteId[noteId] = WorkspaceSaveState.saveError;
      notifyListeners();
    }
    return false;
  }

  Future<bool> enqueueTagMutation({
    required String noteId,
    required List<String> tags,
  }) {
    if (!_isNoteOpen(noteId)) {
      return Future<bool>.value(false);
    }

    final previous = _tagMutationQueueByNoteId[noteId] ?? Future<void>.value();
    final completer = Completer<bool>();
    late final Future<void> queued;
    queued = previous
        .catchError((_) {})
        .then((_) async {
          if (!_isNoteOpen(noteId)) {
            completer.complete(false);
            return;
          }
          final ok = await _tagMutationInvoker(noteId: noteId, tags: tags);
          if (!_isNoteOpen(noteId)) {
            completer.complete(false);
            return;
          }
          completer.complete(ok);
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_tagMutationQueueByNoteId[noteId], queued)) {
            _tagMutationQueueByNoteId.remove(noteId);
          }
        });
    _tagMutationQueueByNoteId[noteId] = queued;
    return completer.future;
  }

  void _scheduleAutosave(String noteId) {
    _saveDebounceByNoteId.remove(noteId)?.cancel();
    _saveDebounceByNoteId[noteId] = _debounceTimerFactory(autosaveDebounce, () {
      unawaited(flushNote(noteId));
    });
  }

  Future<bool> _saveDraftVersion({
    required String noteId,
    required int expectedVersion,
  }) async {
    final current = _buffersByNoteId[noteId];
    if (current == null) {
      return false;
    }

    if (_saveInFlightByNoteId[noteId] case final inflight?) {
      await inflight;
      return false;
    }

    _saveStateByNoteId[noteId] = WorkspaceSaveState.saving;
    notifyListeners();

    final future = _saveInvoker(noteId: noteId, content: current.draftContent);
    _saveInFlightByNoteId[noteId] = future;
    final ok = await future;
    _saveInFlightByNoteId.remove(noteId);

    final latest = _buffersByNoteId[noteId];
    if (latest == null) {
      return false;
    }
    if (!ok) {
      _saveStateByNoteId[noteId] = WorkspaceSaveState.saveError;
      notifyListeners();
      return false;
    }
    if (latest.version != expectedVersion) {
      _saveStateByNoteId[noteId] = WorkspaceSaveState.dirty;
      notifyListeners();
      return false;
    }

    _buffersByNoteId[noteId] = latest.copyWith(
      persistedContent: latest.draftContent,
    );
    _saveStateByNoteId[noteId] = WorkspaceSaveState.clean;
    notifyListeners();
    return true;
  }

  bool _isNoteOpen(String noteId) {
    for (final tabs in _openTabsByPane.values) {
      if (tabs.contains(noteId)) {
        return true;
      }
    }
    return false;
  }
}

Future<bool> _defaultSaveInvoker({
  required String noteId,
  required String content,
}) async {
  return true;
}

Future<bool> _defaultTagMutationInvoker({
  required String noteId,
  required List<String> tags,
}) async {
  return true;
}
