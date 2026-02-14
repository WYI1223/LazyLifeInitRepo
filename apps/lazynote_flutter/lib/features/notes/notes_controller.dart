import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';

/// Async list loader for Notes v0.1 UI flow.
typedef NotesListInvoker =
    Future<rust_api.NotesListResponse> Function({
      String? tag,
      int? limit,
      int? offset,
    });

/// Async detail loader for one selected note.
typedef NoteGetInvoker =
    Future<rust_api.NoteResponse> Function({required String atomId});

/// Async creator for one new note atom.
typedef NoteCreateInvoker =
    Future<rust_api.NoteResponse> Function({required String content});

/// Async updater for persisted note content.
typedef NoteUpdateInvoker =
    Future<rust_api.NoteResponse> Function({
      required String atomId,
      required String content,
    });

/// Async loader for normalized tag list snapshots.
typedef TagsListInvoker = Future<rust_api.TagsListResponse> Function();

/// Async mutator that atomically replaces tags for one note.
typedef NoteSetTagsInvoker =
    Future<rust_api.NoteResponse> Function({
      required String atomId,
      required List<String> tags,
    });

/// Timer factory for autosave debounce scheduling.
typedef DebounceTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Pre-load hook used to ensure bridge/db prerequisites.
typedef NotesPrepare = Future<void> Function();

/// Stable phase set for C1 list lifecycle.
enum NotesListPhase {
  /// No load has started yet.
  idle,

  /// List request is currently in flight.
  loading,

  /// List request succeeded with non-empty items.
  success,

  /// List request succeeded with zero items.
  empty,

  /// List request failed and carries an error message.
  error,
}

/// Save lifecycle for active note draft persistence.
enum NoteSaveState {
  /// Draft content matches persisted content.
  clean,

  /// Draft content has unsaved edits.
  dirty,

  /// Save call is currently in flight.
  saving,

  /// Last save attempt failed.
  error,
}

/// Stateful controller for Notes page list/detail baseline.
///
/// Contract:
/// - Owns list + detail lifecycle state for Notes shell.
/// - Handles tab-open/activate/close operations in-memory.
/// - Calls [notifyListeners] after every externally visible state transition.
class NotesController extends ChangeNotifier {
  /// Creates controller with injectable bridge hooks for testability.
  ///
  /// Input semantics:
  /// - [notesListInvoker]: loads list snapshot (`notes_list` contract).
  /// - [noteGetInvoker]: loads one note detail (`note_get` contract).
  /// - [noteCreateInvoker]: creates one new note (`note_create` contract).
  /// - [noteUpdateInvoker]: persists full content replacement (`note_update`).
  /// - [debounceTimerFactory]: timer scheduler used by autosave debounce.
  /// - [prepare]: prerequisite hook before each bridge request.
  /// - [listLimit]: requested list page size for C1 baseline.
  /// - [autosaveDebounce]: quiet window before autosave starts.
  NotesController({
    NotesListInvoker? notesListInvoker,
    NoteGetInvoker? noteGetInvoker,
    NoteCreateInvoker? noteCreateInvoker,
    NoteUpdateInvoker? noteUpdateInvoker,
    TagsListInvoker? tagsListInvoker,
    NoteSetTagsInvoker? noteSetTagsInvoker,
    DebounceTimerFactory? debounceTimerFactory,
    NotesPrepare? prepare,
    this.listLimit = 50,
    this.autosaveDebounce = const Duration(milliseconds: 1500),
  }) : _notesListInvoker = notesListInvoker ?? _defaultNotesListInvoker,
       _noteGetInvoker = noteGetInvoker ?? _defaultNoteGetInvoker,
       _noteCreateInvoker = noteCreateInvoker ?? _defaultNoteCreateInvoker,
       _noteUpdateInvoker = noteUpdateInvoker ?? _defaultNoteUpdateInvoker,
       _tagsListInvoker = tagsListInvoker ?? _defaultTagsListInvoker,
       _noteSetTagsInvoker = noteSetTagsInvoker ?? _defaultNoteSetTagsInvoker,
       _debounceTimerFactory = debounceTimerFactory ?? Timer.new,
       _prepare = prepare ?? _defaultPrepare;

  final NotesListInvoker _notesListInvoker;
  final NoteGetInvoker _noteGetInvoker;
  final NoteCreateInvoker _noteCreateInvoker;
  final NoteUpdateInvoker _noteUpdateInvoker;
  final TagsListInvoker _tagsListInvoker;
  final NoteSetTagsInvoker _noteSetTagsInvoker;
  final DebounceTimerFactory _debounceTimerFactory;
  final NotesPrepare _prepare;

  /// Requested list limit for C1 list baseline.
  final int listLimit;

  /// Debounce window used by autosave pipeline.
  final Duration autosaveDebounce;

  NotesListPhase _listPhase = NotesListPhase.idle;
  List<rust_api.NoteItem> _items = const [];
  String? _listErrorMessage;
  bool _tagsLoading = false;
  List<String> _availableTags = const [];
  String? _tagsErrorMessage;
  String? _selectedTag;

  rust_api.NoteItem? _selectedNote;
  bool _detailLoading = false;
  String? _detailErrorMessage;
  bool _creatingNote = false;
  String? _createErrorMessage;

  final List<String> _openNoteIds = <String>[];
  final Map<String, rust_api.NoteItem> _noteCache =
      <String, rust_api.NoteItem>{};
  final Map<String, String> _draftContentByAtomId = <String, String>{};
  final Map<String, String> _persistedContentByAtomId = <String, String>{};
  final Map<String, int> _draftVersionByAtomId = <String, int>{};
  String? _activeNoteId;
  String? _activeDraftAtomId;
  String _activeDraftContent = '';
  int _editorFocusRequestId = 0;
  NoteSaveState _noteSaveState = NoteSaveState.clean;
  String? _saveErrorMessage;
  bool _showSavedBadge = false;
  Timer? _autosaveTimer;
  Timer? _savedBadgeTimer;
  final Map<String, Future<bool>> _saveFutureByAtomId =
      <String, Future<bool>>{};
  final Map<String, bool> _saveQueuedByAtomId = <String, bool>{};
  final Set<String> _tagSaveInFlightAtomIds = <String>{};
  String? _switchBlockErrorMessage;

  int _listRequestId = 0;
  int _detailRequestId = 0;
  int _tagsRequestId = 0;

  /// Current list phase.
  NotesListPhase get listPhase => _listPhase;

  /// Current list items from `notes_list`.
  List<rust_api.NoteItem> get items => List.unmodifiable(_items);

  /// Current list-level error message.
  String? get listErrorMessage => _listErrorMessage;

  /// Whether tag catalog request is currently in flight.
  bool get tagsLoading => _tagsLoading;

  /// Normalized tags sorted alphabetically for filter UI.
  List<String> get availableTags => List.unmodifiable(_availableTags);

  /// Current tag catalog failure message.
  String? get tagsErrorMessage => _tagsErrorMessage;

  /// Currently selected single-tag filter (`null` means unfiltered).
  String? get selectedTag => _selectedTag;

  /// Currently selected note atom id.
  String? get selectedAtomId => _activeNoteId;

  /// Currently active tab note id.
  String? get activeNoteId => _activeNoteId;

  /// Currently opened tab ids in order.
  List<String> get openNoteIds => List.unmodifiable(_openNoteIds);

  /// Selected note detail payload used by right pane.
  rust_api.NoteItem? get selectedNote => _selectedNote;

  /// Whether selected-note detail load is in flight.
  bool get detailLoading => _detailLoading;

  /// Current selected-note detail load error.
  String? get detailErrorMessage => _detailErrorMessage;

  /// Whether a create-note request is currently in flight.
  bool get creatingNote => _creatingNote;

  /// Current create-note failure message.
  String? get createErrorMessage => _createErrorMessage;

  /// Save lifecycle state for active note.
  NoteSaveState get noteSaveState => _noteSaveState;

  /// Last save error message for active note.
  String? get saveErrorMessage => _saveErrorMessage;

  /// Whether success badge should be visible for active note.
  bool get showSavedBadge => _showSavedBadge;

  /// Banner message shown when note switch is blocked by flush failure.
  String? get switchBlockErrorMessage => _switchBlockErrorMessage;

  /// Whether active note has pending save work before app close.
  ///
  /// Includes dirty drafts and in-flight save requests for all open tabs.
  bool get hasPendingSaveWork {
    if (_activeNoteId case final active?) {
      if (_hasPendingSaveFor(active)) {
        return true;
      }
    }
    for (final atomId in _openNoteIds) {
      if (_hasPendingSaveFor(atomId)) {
        return true;
      }
    }
    return false;
  }

  /// Monotonic token used by UI to request editor focus.
  int get editorFocusRequestId => _editorFocusRequestId;

  /// In-memory draft content for active editor instance.
  String get activeDraftContent {
    if (_activeNoteId == null) {
      return '';
    }
    final atomId = _activeNoteId!;
    if (_draftContentByAtomId[atomId] case final draft?) {
      return draft;
    }
    if (_activeDraftAtomId == atomId) {
      return _activeDraftContent;
    }
    return _selectedNote?.content ?? '';
  }

  /// Returns one cached/list note by id when available.
  rust_api.NoteItem? noteById(String atomId) {
    return _noteCache[atomId] ?? _findListItem(atomId);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _savedBadgeTimer?.cancel();
    super.dispose();
  }

  /// Tab title projection used by tab manager.
  String titleForTab(String atomId) {
    final item = noteById(atomId);
    if (item == null) {
      return 'Untitled';
    }
    return _titleFromContent(item.content);
  }

  /// Loads notes baseline and tag catalog on initial page entry.
  ///
  /// Side effects:
  /// - Resets existing tab/detail state before reloading.
  /// - Opens first loaded note as active tab when available.
  Future<void> loadNotes() async {
    await _loadNotes(
      resetSession: true,
      preserveActiveWhenFilteredOut: false,
      refreshTags: true,
    );
  }

  /// Retries notes list for current filter without resetting opened tabs.
  Future<void> retryLoad() async {
    await _loadNotes(
      resetSession: false,
      preserveActiveWhenFilteredOut: false,
      refreshTags: false,
    );
  }

  /// Retries tag catalog request for filter UI.
  Future<void> retryTagLoad() => _refreshAvailableTags();

  /// Applies one normalized single-tag filter.
  ///
  /// Returns `false` when input is invalid or flush guard blocks transition.
  Future<bool> applyTagFilter(String rawTag) async {
    final normalized = _normalizeTag(rawTag);
    if (normalized == null) {
      // Why: blank filter tokens are invalid but should be ignored silently
      // to keep UX stable when user submits whitespace accidentally.
      return false;
    }
    if (_selectedTag == normalized) {
      return true;
    }

    if (_activeNoteId != null) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }

    _selectedTag = normalized;
    await _loadNotes(
      resetSession: false,
      preserveActiveWhenFilteredOut: false,
      refreshTags: false,
    );
    return _listPhase != NotesListPhase.error;
  }

  /// Clears active single-tag filter and returns to full list.
  ///
  /// Returns `false` when flush guard blocks transition.
  Future<bool> clearTagFilter() async {
    if (_selectedTag == null) {
      return true;
    }
    if (_activeNoteId != null) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }
    _selectedTag = null;
    await _loadNotes(
      resetSession: false,
      preserveActiveWhenFilteredOut: false,
      refreshTags: false,
    );
    return _listPhase != NotesListPhase.error;
  }

  /// Handles open-note request from explorer shell.
  Future<bool> openNoteFromExplorer(String atomId) => selectNote(atomId);

  /// Flushes pending save work for the currently active note.
  ///
  /// Contract:
  /// - Returns `true` when no pending write exists or persistence succeeds.
  /// - Returns `false` when latest draft cannot be persisted.
  /// - Keeps in-memory draft unchanged on failure.
  Future<bool> flushPendingSave() async {
    final atomId = _activeNoteId;
    if (atomId == null) {
      return true;
    }
    _autosaveTimer?.cancel();

    while (true) {
      if (_tagSaveInFlightAtomIds.contains(atomId)) {
        await Future<void>.delayed(const Duration(milliseconds: 12));
        continue;
      }

      final inflight = _saveFutureByAtomId[atomId];
      if (inflight != null) {
        await inflight;
        if (!_isDirty(atomId)) {
          _switchBlockErrorMessage = null;
          return true;
        }
        continue;
      }

      if (!_isDirty(atomId)) {
        _switchBlockErrorMessage = null;
        return true;
      }

      final version = _draftVersionByAtomId[atomId] ?? 0;
      final saved = await _saveDraft(atomId: atomId, version: version);
      if (saved && !_isDirty(atomId)) {
        _switchBlockErrorMessage = null;
        return true;
      }

      if ((_draftVersionByAtomId[atomId] ?? 0) != version) {
        continue;
      }

      _switchBlockErrorMessage = 'Save failed. Retry or back up content.';
      notifyListeners();
      return false;
    }
  }

  /// Retries saving current active draft immediately.
  ///
  /// Contract:
  /// - Saves the latest in-memory draft (not stale snapshot).
  /// - Returns `true` when active draft becomes persisted.
  /// - Returns `false` when save still fails.
  Future<bool> retrySaveCurrentDraft() async {
    final atomId = _activeNoteId;
    if (atomId == null) {
      return false;
    }
    _autosaveTimer?.cancel();
    final version = _draftVersionByAtomId[atomId] ?? 0;
    final saved = await _saveDraft(atomId: atomId, version: version);
    if (saved && !_isDirty(atomId)) {
      _switchBlockErrorMessage = null;
      notifyListeners();
      return true;
    }
    if ((_draftVersionByAtomId[atomId] ?? 0) != version) {
      return false;
    }
    return false;
  }

  /// Creates one new empty note and activates editor on success.
  ///
  /// Side effects:
  /// - Calls `note_create` with empty content in v0.1 C2.
  /// - Inserts created note into list/cache without reloading full list.
  /// - Sets created note as active tab and requests editor focus.
  Future<bool> createNote() async {
    if (_creatingNote) {
      return false;
    }
    _creatingNote = true;
    _createErrorMessage = null;
    notifyListeners();

    try {
      await _prepare();
      final response = await _noteCreateInvoker(content: '');
      if (!response.ok) {
        _creatingNote = false;
        _createErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to create note.',
        );
        notifyListeners();
        return false;
      }

      final created = response.note;
      if (created == null) {
        _creatingNote = false;
        _createErrorMessage =
            'Create note succeeded but returned empty payload.';
        notifyListeners();
        return false;
      }
      var createdNote = created;
      if (_selectedTag case final activeTag?) {
        final tagged = await _noteSetTagsInvoker(
          atomId: created.atomId,
          tags: <String>[activeTag],
        );
        if (tagged.ok && tagged.note != null) {
          createdNote = tagged.note!;
        } else {
          _createErrorMessage = _envelopeError(
            errorCode: tagged.errorCode,
            message: tagged.message,
            fallback: 'Created note but failed to apply active filter tag.',
          );
        }
      }

      _listPhase = NotesListPhase.success;
      _insertOrReplaceListItem(
        createdNote,
        insertFront: true,
        updatePersisted: true,
      );
      _activeNoteId = createdNote.atomId;
      _selectedNote = createdNote;
      _activeDraftAtomId = createdNote.atomId;
      _activeDraftContent = _draftContentByAtomId[createdNote.atomId] ?? '';
      _detailErrorMessage = null;
      if (!_openNoteIds.contains(createdNote.atomId)) {
        _openNoteIds.add(createdNote.atomId);
      }
      _creatingNote = false;
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
      _requestEditorFocus();
      notifyListeners();

      await _refreshAvailableTags(showLoading: false);
      await _loadSelectedDetail(atomId: createdNote.atomId);
      _requestEditorFocus();
      notifyListeners();
      return true;
    } catch (error) {
      _creatingNote = false;
      _createErrorMessage = 'Create note failed unexpectedly: $error';
      notifyListeners();
      return false;
    }
  }

  /// Replaces the active note tag set using immediate-save semantics.
  ///
  /// Returns `false` when active note is missing or mutation fails.
  Future<bool> setActiveNoteTags(List<String> rawTags) async {
    final atomId = _activeNoteId;
    if (atomId == null) {
      return false;
    }
    final normalized = _normalizeTags(rawTags);
    final current = _noteCache[atomId] ?? _selectedNote;
    if (current == null) {
      return false;
    }

    final sameTags = listEquals(current.tags, normalized);
    if (sameTags) {
      return true;
    }

    _tagSaveInFlightAtomIds.add(atomId);
    _setSaveState(NoteSaveState.saving);
    notifyListeners();

    try {
      await _prepare();
      final response = await _noteSetTagsInvoker(
        atomId: atomId,
        tags: normalized,
      );
      if (!response.ok) {
        _saveErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to update note tags.',
        );
        _setSaveState(NoteSaveState.error, preserveError: true);
        notifyListeners();
        return false;
      }
      final updated = response.note;
      if (updated == null) {
        _saveErrorMessage = 'Tag update succeeded without note payload.';
        _setSaveState(NoteSaveState.error, preserveError: true);
        notifyListeners();
        return false;
      }

      _insertOrReplaceListItem(updated, updatePersisted: true);
      if (_activeNoteId == atomId) {
        _selectedNote = _noteCache[atomId];
        _activeDraftContent = _draftContentByAtomId[atomId] ?? updated.content;
        _switchBlockErrorMessage = null;
        if (_isDirty(atomId)) {
          _setSaveState(NoteSaveState.dirty);
        } else {
          _setSaveState(NoteSaveState.clean, showSavedBadge: true);
        }
      }
      notifyListeners();

      await _refreshAvailableTags(showLoading: false);

      // Why: when active note no longer matches current filter, keep editor
      // alive but refresh explorer list to avoid stale left-pane entries.
      if (_selectedTag case final activeTag?) {
        if (!updated.tags.contains(activeTag)) {
          await _loadNotes(
            resetSession: false,
            preserveActiveWhenFilteredOut: true,
            refreshTags: false,
          );
        }
      }
      return true;
    } catch (error) {
      _saveErrorMessage = 'Tag update failed unexpectedly: $error';
      _setSaveState(NoteSaveState.error, preserveError: true);
      notifyListeners();
      return false;
    } finally {
      _tagSaveInFlightAtomIds.remove(atomId);
    }
  }

  /// Adds one tag to active note with normalization and de-duplication.
  Future<bool> addTagToActiveNote(String tag) async {
    final normalized = _normalizeTag(tag);
    if (normalized == null) {
      return false;
    }
    final atomId = _activeNoteId;
    if (atomId == null) {
      return false;
    }
    final current = _noteCache[atomId] ?? _selectedNote;
    if (current == null) {
      return false;
    }
    return setActiveNoteTags(<String>[...current.tags, normalized]);
  }

  /// Removes one tag from active note with normalization.
  Future<bool> removeTagFromActiveNote(String tag) async {
    final normalized = _normalizeTag(tag);
    if (normalized == null) {
      return false;
    }
    final atomId = _activeNoteId;
    if (atomId == null) {
      return false;
    }
    final current = _noteCache[atomId] ?? _selectedNote;
    if (current == null) {
      return false;
    }
    final next = current.tags.where((entry) => entry != normalized).toList();
    return setActiveNoteTags(next);
  }

  /// Selects one note and refreshes detail snapshot.
  ///
  /// Side effects:
  /// - Flushes pending save for current active note before switching.
  /// - Opens a new tab when [atomId] is not already opened.
  /// - Keeps existing tabs unchanged when [atomId] is already opened.
  ///
  /// Returns:
  /// - `true` when switch succeeds.
  /// - `false` when switch is blocked by flush failure.
  Future<bool> selectNote(String atomId) async {
    if (_activeNoteId == atomId &&
        _selectedNote != null &&
        !_detailLoading &&
        _detailErrorMessage == null) {
      return true;
    }

    if (_activeNoteId != null && _activeNoteId != atomId) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }

    _activeNoteId = atomId;
    if (!_openNoteIds.contains(atomId)) {
      _openNoteIds.add(atomId);
    }
    _selectedNote = _findListItem(atomId);
    _activeDraftAtomId = atomId;
    _activeDraftContent =
        _draftContentByAtomId[atomId] ?? _selectedNote?.content ?? '';
    _refreshSaveStateForActive();
    _requestEditorFocus();
    _switchBlockErrorMessage = null;
    notifyListeners();

    await _loadSelectedDetail(atomId: atomId);
    return true;
  }

  /// Activates an already opened note tab and refreshes its detail.
  ///
  /// Returns `false` when switch guard blocks the activation.
  Future<bool> activateOpenNote(String atomId) async {
    if (!_openNoteIds.contains(atomId)) {
      return selectNote(atomId);
    }
    return selectNote(atomId);
  }

  /// Moves active tab forward (Ctrl+Tab behavior).
  Future<void> activateNextOpenNote() async {
    if (_openNoteIds.length <= 1 || _activeNoteId == null) {
      return;
    }
    final currentIndex = _openNoteIds.indexOf(_activeNoteId!);
    if (currentIndex < 0) {
      return;
    }
    final nextIndex = (currentIndex + 1) % _openNoteIds.length;
    await activateOpenNote(_openNoteIds[nextIndex]);
  }

  /// Moves active tab backward (Ctrl+Shift+Tab behavior).
  Future<void> activatePreviousOpenNote() async {
    if (_openNoteIds.length <= 1 || _activeNoteId == null) {
      return;
    }
    final currentIndex = _openNoteIds.indexOf(_activeNoteId!);
    if (currentIndex < 0) {
      return;
    }
    final prevIndex =
        (currentIndex - 1 + _openNoteIds.length) % _openNoteIds.length;
    await activateOpenNote(_openNoteIds[prevIndex]);
  }

  /// Closes one opened tab.
  ///
  /// Side effects:
  /// - When closing active tab, selects deterministic fallback tab.
  /// - Flushes active draft before close to avoid data loss.
  /// - Clears selected detail state when the last tab is closed.
  ///
  /// Returns `false` when close is blocked by flush failure.
  Future<bool> closeOpenNote(String atomId) async {
    final closedIndex = _openNoteIds.indexOf(atomId);
    if (closedIndex < 0) {
      return false;
    }
    if (_activeNoteId == atomId) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }

    _openNoteIds.removeAt(closedIndex);
    if (_activeNoteId != atomId) {
      notifyListeners();
      return true;
    }

    if (_openNoteIds.isEmpty) {
      _activeNoteId = null;
      _selectedNote = null;
      _detailLoading = false;
      _detailErrorMessage = null;
      _activeDraftAtomId = null;
      _activeDraftContent = '';
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
      notifyListeners();
      return true;
    }

    final fallbackIndex = (closedIndex - 1).clamp(0, _openNoteIds.length - 1);
    final fallbackId = _openNoteIds[fallbackIndex];
    _activeNoteId = fallbackId;
    _selectedNote = noteById(fallbackId);
    _activeDraftAtomId = fallbackId;
    _activeDraftContent =
        _draftContentByAtomId[fallbackId] ?? _selectedNote?.content ?? '';
    _refreshSaveStateForActive();
    _requestEditorFocus();
    notifyListeners();
    await _loadSelectedDetail(atomId: fallbackId);
    return true;
  }

  /// Closes all tabs except [atomId], then activates [atomId].
  ///
  /// Returns `false` when switch/close is blocked by flush failure.
  Future<bool> closeOtherOpenNotes(String atomId) async {
    if (!_openNoteIds.contains(atomId)) {
      return false;
    }
    final switched = await activateOpenNote(atomId);
    if (!switched) {
      return false;
    }
    _openNoteIds
      ..clear()
      ..add(atomId);
    notifyListeners();
    return true;
  }

  /// Closes tabs to the right of [atomId].
  ///
  /// Side effects:
  /// - Flushes active draft when active tab would be removed.
  /// - Re-activates [atomId] if active tab was pruned by this operation.
  ///
  /// Returns `false` when close is blocked by flush failure.
  Future<bool> closeOpenNotesToRight(String atomId) async {
    final index = _openNoteIds.indexOf(atomId);
    if (index < 0) {
      return false;
    }
    if (index == _openNoteIds.length - 1) {
      return true;
    }

    final activeId = _activeNoteId;
    final willPruneActive =
        activeId != null && _openNoteIds.indexOf(activeId) > index;
    if (willPruneActive) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }
    _openNoteIds.removeRange(index + 1, _openNoteIds.length);
    if (!_openNoteIds.contains(_activeNoteId)) {
      _activeNoteId = atomId;
      _selectedNote = noteById(atomId);
      _activeDraftAtomId = atomId;
      _activeDraftContent =
          _draftContentByAtomId[atomId] ?? _selectedNote?.content ?? '';
      _refreshSaveStateForActive();
      _requestEditorFocus();
      notifyListeners();
      await _loadSelectedDetail(atomId: atomId);
      return true;
    }
    notifyListeners();
    return true;
  }

  /// Updates active note draft content in-memory.
  ///
  /// Side effects:
  /// - Updates selected note cache and list snapshot title projection.
  /// - Schedules debounced persistence through `note_update`.
  void updateActiveDraft(String content) {
    final atomId = _activeNoteId;
    if (atomId == null) {
      return;
    }
    final previous = _draftContentByAtomId[atomId] ?? _activeDraftContent;
    if (previous == content) {
      return;
    }

    _activeDraftAtomId = atomId;
    _activeDraftContent = content;
    _draftContentByAtomId[atomId] = content;
    final version = (_draftVersionByAtomId[atomId] ?? 0) + 1;
    _draftVersionByAtomId[atomId] = version;
    final current = _noteCache[atomId] ?? _selectedNote;
    if (current != null) {
      final updated = _withContent(current, content);
      _selectedNote = updated;
      _insertOrReplaceListItem(updated);
    }

    if (_isDirty(atomId)) {
      _setSaveState(NoteSaveState.dirty);
      _scheduleAutosave(atomId: atomId, version: version);
    } else {
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
    }
    notifyListeners();
  }

  Future<void> _loadNotes({
    required bool resetSession,
    required bool preserveActiveWhenFilteredOut,
    required bool refreshTags,
  }) async {
    final requestId = ++_listRequestId;
    if (refreshTags) {
      unawaited(_refreshAvailableTags());
    }

    if (resetSession) {
      _resetSessionForReload();
    }

    _listPhase = NotesListPhase.loading;
    _items = const [];
    _listErrorMessage = null;
    _switchBlockErrorMessage = null;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _listRequestId) {
        return;
      }

      final response = await _notesListInvoker(
        tag: _selectedTag,
        limit: listLimit,
        offset: 0,
      );
      if (requestId != _listRequestId) {
        return;
      }

      if (!response.ok) {
        _listPhase = NotesListPhase.error;
        _listErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to load notes.',
        );
        notifyListeners();
        return;
      }

      final loadedItems = List<rust_api.NoteItem>.unmodifiable(response.items);
      _items = loadedItems;
      for (final item in loadedItems) {
        // Why: during list fetch, `_items` already equals server-filtered
        // results. Cache/persisted maps still need refresh, but rewriting
        // visible list here can re-insert notes that no longer match filter.
        _insertOrReplaceListItem(
          item,
          updatePersisted: true,
          syncVisibleList: false,
        );
      }
      _listPhase = loadedItems.isEmpty
          ? NotesListPhase.empty
          : NotesListPhase.success;

      String? detailTargetId;
      final activeId = _activeNoteId;
      final activeInList =
          activeId != null && _findLoadedItem(loadedItems, activeId) != null;
      if (activeId == null) {
        if (loadedItems.isNotEmpty) {
          final first = loadedItems.first;
          _activeNoteId = first.atomId;
          _selectedNote = first;
          _activeDraftAtomId = first.atomId;
          _activeDraftContent =
              _draftContentByAtomId[first.atomId] ?? first.content;
          if (!_openNoteIds.contains(first.atomId)) {
            _openNoteIds.add(first.atomId);
          }
          _setSaveState(NoteSaveState.clean);
          detailTargetId = first.atomId;
        } else {
          _selectedNote = null;
          _detailLoading = false;
          _detailErrorMessage = null;
          _activeDraftAtomId = null;
          _activeDraftContent = '';
          _setSaveState(NoteSaveState.clean);
        }
      } else if (activeInList) {
        _selectedNote = _findLoadedItem(loadedItems, activeId) ?? _selectedNote;
        _activeDraftAtomId = activeId;
        _activeDraftContent =
            _draftContentByAtomId[activeId] ?? _selectedNote?.content ?? '';
        _refreshSaveStateForActive();
      } else if (preserveActiveWhenFilteredOut) {
        _selectedNote = _noteCache[activeId] ?? _selectedNote;
        _activeDraftAtomId = activeId;
        _activeDraftContent =
            _draftContentByAtomId[activeId] ?? _selectedNote?.content ?? '';
        _refreshSaveStateForActive();
      } else if (loadedItems.isNotEmpty) {
        final fallback = loadedItems.first;
        _activeNoteId = fallback.atomId;
        _selectedNote = fallback;
        _activeDraftAtomId = fallback.atomId;
        _activeDraftContent =
            _draftContentByAtomId[fallback.atomId] ?? fallback.content;
        if (!_openNoteIds.contains(fallback.atomId)) {
          _openNoteIds.add(fallback.atomId);
        }
        _refreshSaveStateForActive();
        _requestEditorFocus();
        detailTargetId = fallback.atomId;
      } else {
        _activeNoteId = null;
        _selectedNote = null;
        _detailLoading = false;
        _detailErrorMessage = null;
        _activeDraftAtomId = null;
        _activeDraftContent = '';
        _setSaveState(NoteSaveState.clean);
      }
      notifyListeners();

      if (detailTargetId != null) {
        await _loadSelectedDetail(atomId: detailTargetId);
      }
    } catch (error) {
      if (requestId != _listRequestId) {
        return;
      }
      _listPhase = NotesListPhase.error;
      _listErrorMessage = 'Notes load failed unexpectedly: $error';
      notifyListeners();
    }
  }

  void _resetSessionForReload() {
    _selectedNote = null;
    _detailLoading = false;
    _detailErrorMessage = null;
    _openNoteIds.clear();
    _noteCache.clear();
    _draftContentByAtomId.clear();
    _persistedContentByAtomId.clear();
    _draftVersionByAtomId.clear();
    _saveFutureByAtomId.clear();
    _saveQueuedByAtomId.clear();
    _tagSaveInFlightAtomIds.clear();
    _activeNoteId = null;
    _activeDraftAtomId = null;
    _activeDraftContent = '';
    _creatingNote = false;
    _createErrorMessage = null;
    _autosaveTimer?.cancel();
    _savedBadgeTimer?.cancel();
    _noteSaveState = NoteSaveState.clean;
    _saveErrorMessage = null;
    _showSavedBadge = false;
  }

  Future<void> _refreshAvailableTags({bool showLoading = true}) async {
    final requestId = ++_tagsRequestId;
    if (showLoading) {
      _tagsLoading = true;
      _tagsErrorMessage = null;
      notifyListeners();
    }

    try {
      await _prepare();
      if (requestId != _tagsRequestId) {
        return;
      }

      final response = await _tagsListInvoker();
      if (requestId != _tagsRequestId) {
        return;
      }

      if (!response.ok) {
        _tagsLoading = false;
        _tagsErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to load tags.',
        );
        notifyListeners();
        return;
      }

      _availableTags = List<String>.unmodifiable(_normalizeTags(response.tags));
      _tagsLoading = false;
      _tagsErrorMessage = null;
      notifyListeners();
    } catch (error) {
      if (requestId != _tagsRequestId) {
        return;
      }
      _tagsLoading = false;
      _tagsErrorMessage = 'Tags load failed unexpectedly: $error';
      notifyListeners();
    }
  }

  /// Retries loading current selected note detail.
  Future<void> refreshSelectedDetail() async {
    final atomId = _activeNoteId;
    if (atomId == null) {
      return;
    }
    await _loadSelectedDetail(atomId: atomId);
  }

  Future<void> _loadSelectedDetail({required String atomId}) async {
    final requestId = ++_detailRequestId;
    _detailLoading = true;
    _detailErrorMessage = null;
    _selectedNote = _findListItem(atomId) ?? _selectedNote;
    notifyListeners();

    try {
      await _prepare();
      if (requestId != _detailRequestId || atomId != _activeNoteId) {
        return;
      }

      final response = await _noteGetInvoker(atomId: atomId);
      if (requestId != _detailRequestId || atomId != _activeNoteId) {
        return;
      }

      if (!response.ok) {
        _detailLoading = false;
        _detailErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to load note detail.',
        );
        notifyListeners();
        return;
      }

      if (response.note case final note?) {
        _selectedNote = note;
        _insertOrReplaceListItem(note, updatePersisted: true);
        _activeDraftAtomId = note.atomId;
        _activeDraftContent =
            _draftContentByAtomId[note.atomId] ?? note.content;
        _detailLoading = false;
        _detailErrorMessage = null;
        _refreshSaveStateForActive();
        notifyListeners();
        return;
      }

      _detailLoading = false;
      _detailErrorMessage = 'Note detail is empty.';
      notifyListeners();
    } catch (error) {
      if (requestId != _detailRequestId || atomId != _activeNoteId) {
        return;
      }
      _detailLoading = false;
      _detailErrorMessage = 'Note detail load failed unexpectedly: $error';
      notifyListeners();
    }
  }

  rust_api.NoteItem? _findLoadedItem(
    List<rust_api.NoteItem> items,
    String atomId,
  ) {
    for (final item in items) {
      if (item.atomId == atomId) {
        return item;
      }
    }
    return null;
  }

  rust_api.NoteItem? _findListItem(String atomId) {
    for (final item in _items) {
      if (item.atomId == atomId) {
        return item;
      }
    }
    return null;
  }

  void _insertOrReplaceListItem(
    rust_api.NoteItem note, {
    bool insertFront = false,
    bool updatePersisted = false,
    bool syncVisibleList = true,
  }) {
    final wasDirty = _isDirty(note.atomId);
    _noteCache[note.atomId] = note;
    if (updatePersisted) {
      _persistedContentByAtomId[note.atomId] = note.content;
      _draftVersionByAtomId.putIfAbsent(note.atomId, () => 0);
      if (!_draftContentByAtomId.containsKey(note.atomId) || !wasDirty) {
        _draftContentByAtomId[note.atomId] = note.content;
      }
    }
    if (!syncVisibleList) {
      return;
    }

    final includeInVisibleList = _shouldIncludeInVisibleList(note);
    final mutable = List<rust_api.NoteItem>.from(_items);
    final existingIndex = mutable.indexWhere(
      (item) => item.atomId == note.atomId,
    );
    if (includeInVisibleList) {
      if (existingIndex >= 0) {
        mutable[existingIndex] = note;
      } else if (insertFront) {
        mutable.insert(0, note);
      } else {
        mutable.add(note);
      }
    } else if (existingIndex >= 0) {
      mutable.removeAt(existingIndex);
    }
    _items = List<rust_api.NoteItem>.unmodifiable(mutable);
  }

  rust_api.NoteItem _withContent(rust_api.NoteItem current, String content) {
    return rust_api.NoteItem(
      atomId: current.atomId,
      content: content,
      previewText: current.previewText,
      previewImage: current.previewImage,
      updatedAt: current.updatedAt,
      tags: current.tags,
    );
  }

  void _requestEditorFocus() {
    _editorFocusRequestId += 1;
  }

  bool _isDirty(String atomId) {
    final draft = _draftContentByAtomId[atomId];
    final persisted = _persistedContentByAtomId[atomId];
    if (draft == null || persisted == null) {
      return false;
    }
    return draft != persisted;
  }

  bool _hasPendingSaveFor(String atomId) {
    return _isDirty(atomId) ||
        _saveFutureByAtomId.containsKey(atomId) ||
        _tagSaveInFlightAtomIds.contains(atomId);
  }

  bool _shouldIncludeInVisibleList(rust_api.NoteItem note) {
    final selectedTag = _selectedTag;
    if (selectedTag == null) {
      return true;
    }
    return note.tags.contains(selectedTag);
  }

  void _scheduleAutosave({required String atomId, required int version}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = _debounceTimerFactory(autosaveDebounce, () {
      unawaited(_saveDraft(atomId: atomId, version: version));
    });
  }

  Future<bool> _saveDraft({required String atomId, required int version}) {
    if (_saveFutureByAtomId[atomId] case final inFlight?) {
      _saveQueuedByAtomId[atomId] = true;
      return inFlight;
    }
    final future = _performSaveDraft(atomId: atomId, version: version)
        .whenComplete(() {
          _saveFutureByAtomId.remove(atomId);
          final shouldQueue = _saveQueuedByAtomId.remove(atomId) ?? false;
          // Why: retry only when a newer write arrived during in-flight save.
          // Retrying on plain dirty state can loop forever on persistent I/O errors.
          if (shouldQueue) {
            final nextVersion = _draftVersionByAtomId[atomId] ?? 0;
            unawaited(_saveDraft(atomId: atomId, version: nextVersion));
          }
        });
    _saveFutureByAtomId[atomId] = future;
    return future;
  }

  Future<bool> _performSaveDraft({
    required String atomId,
    required int version,
  }) async {
    final draft = _draftContentByAtomId[atomId];
    if (draft == null) {
      return false;
    }
    final latestVersion = _draftVersionByAtomId[atomId] ?? 0;
    if (version != latestVersion || !_isDirty(atomId)) {
      if (_activeNoteId == atomId) {
        _refreshSaveStateForActive();
        notifyListeners();
      }
      return false;
    }

    if (_activeNoteId == atomId) {
      _setSaveState(NoteSaveState.saving);
      notifyListeners();
    }

    try {
      await _prepare();
      final response = await _noteUpdateInvoker(atomId: atomId, content: draft);
      final currentVersion = _draftVersionByAtomId[atomId] ?? 0;
      if (version != currentVersion) {
        if (_activeNoteId == atomId) {
          _refreshSaveStateForActive();
          notifyListeners();
        }
        return false;
      }

      if (!response.ok) {
        if (_activeNoteId == atomId) {
          _saveErrorMessage = _envelopeError(
            errorCode: response.errorCode,
            message: response.message,
            fallback: 'Failed to save note.',
          );
          _setSaveState(NoteSaveState.error, preserveError: true);
          notifyListeners();
        }
        return false;
      }

      final current = _noteCache[atomId];
      final saved =
          response.note ??
          (current == null ? null : _withContent(current, draft));
      if (saved == null) {
        if (_activeNoteId == atomId) {
          _saveErrorMessage = 'Save succeeded without note payload.';
          _setSaveState(NoteSaveState.error, preserveError: true);
          notifyListeners();
        }
        return false;
      }
      _insertOrReplaceListItem(saved, updatePersisted: true);
      if (_activeNoteId == atomId) {
        _selectedNote = _noteCache[atomId];
        _activeDraftContent = _draftContentByAtomId[atomId] ?? draft;
        _switchBlockErrorMessage = null;
        if (_isDirty(atomId)) {
          _setSaveState(NoteSaveState.dirty);
        } else {
          _setSaveState(NoteSaveState.clean, showSavedBadge: true);
        }
        notifyListeners();
      }
      return true;
    } catch (error) {
      final currentVersion = _draftVersionByAtomId[atomId] ?? 0;
      if (version != currentVersion) {
        if (_activeNoteId == atomId) {
          _refreshSaveStateForActive();
          notifyListeners();
        }
        return false;
      }
      if (_activeNoteId == atomId) {
        _saveErrorMessage = 'Save failed unexpectedly: $error';
        _setSaveState(NoteSaveState.error, preserveError: true);
        notifyListeners();
      }
      return false;
    }
  }

  void _refreshSaveStateForActive() {
    final atomId = _activeNoteId;
    if (atomId == null) {
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
      return;
    }
    if (_isDirty(atomId)) {
      _setSaveState(NoteSaveState.dirty);
      return;
    }
    _setSaveState(NoteSaveState.clean);
  }

  void _setSaveState(
    NoteSaveState nextState, {
    bool preserveError = false,
    bool showSavedBadge = false,
  }) {
    _noteSaveState = nextState;
    if (!preserveError) {
      _saveErrorMessage = null;
    }
    if (showSavedBadge) {
      _showSavedBadge = true;
      _savedBadgeTimer?.cancel();
      _savedBadgeTimer = _debounceTimerFactory(const Duration(seconds: 3), () {
        if (_noteSaveState != NoteSaveState.clean) {
          return;
        }
        _showSavedBadge = false;
        notifyListeners();
      });
      return;
    }
    _savedBadgeTimer?.cancel();
    _showSavedBadge = false;
  }

  String _envelopeError({
    required String? errorCode,
    required String message,
    required String fallback,
  }) {
    final normalized = message.trim();
    if (errorCode == null || errorCode.trim().isEmpty) {
      return normalized.isEmpty ? fallback : normalized;
    }
    if (normalized.isEmpty) {
      return '[$errorCode] $fallback';
    }
    return '[$errorCode] $normalized';
  }

  String? _normalizeTag(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  List<String> _normalizeTags(List<String> rawTags) {
    final set = SplayTreeSet<String>();
    for (final tag in rawTags) {
      final normalized = _normalizeTag(tag);
      if (normalized != null) {
        set.add(normalized);
      }
    }
    return List<String>.unmodifiable(set);
  }

  String _titleFromContent(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final withoutHeading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      return withoutHeading.isEmpty ? trimmed : withoutHeading;
    }
    return 'Untitled';
  }
}

Future<rust_api.NotesListResponse> _defaultNotesListInvoker({
  String? tag,
  int? limit,
  int? offset,
}) {
  return rust_api.notesList(tag: tag, limit: limit, offset: offset);
}

Future<rust_api.NoteResponse> _defaultNoteGetInvoker({required String atomId}) {
  return rust_api.noteGet(atomId: atomId);
}

Future<rust_api.NoteResponse> _defaultNoteCreateInvoker({
  required String content,
}) {
  return rust_api.noteCreate(content: content);
}

Future<rust_api.NoteResponse> _defaultNoteUpdateInvoker({
  required String atomId,
  required String content,
}) {
  return rust_api.noteUpdate(atomId: atomId, content: content);
}

Future<rust_api.TagsListResponse> _defaultTagsListInvoker() {
  return rust_api.tagsList();
}

Future<rust_api.NoteResponse> _defaultNoteSetTagsInvoker({
  required String atomId,
  required List<String> tags,
}) {
  return rust_api.noteSetTags(atomId: atomId, tags: tags);
}

Future<void> _defaultPrepare() async {
  await RustBridge.ensureEntryDbPathConfigured();
}
