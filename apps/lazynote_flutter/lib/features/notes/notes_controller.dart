import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';
import 'package:lazynote_flutter/features/workspace/workspace_models.dart';
import 'package:lazynote_flutter/features/workspace/workspace_provider.dart';

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

/// Async workspace folder delete mutator.
typedef WorkspaceDeleteFolderInvoker =
    Future<rust_api.WorkspaceActionResponse> Function({
      required String nodeId,
      required String mode,
    });

/// Async workspace folder create mutator.
typedef WorkspaceCreateFolderInvoker =
    Future<rust_api.WorkspaceNodeResponse> Function({
      String? parentNodeId,
      required String name,
    });

/// Async workspace note_ref create mutator.
typedef WorkspaceCreateNoteRefInvoker =
    Future<rust_api.WorkspaceNodeResponse> Function({
      String? parentNodeId,
      required String atomId,
      String? displayName,
    });

/// Async workspace node rename mutator.
typedef WorkspaceRenameNodeInvoker =
    Future<rust_api.WorkspaceActionResponse> Function({
      required String nodeId,
      required String newName,
    });

/// Async workspace node move mutator.
typedef WorkspaceMoveNodeInvoker =
    Future<rust_api.WorkspaceActionResponse> Function({
      required String nodeId,
      String? newParentId,
      int? targetOrder,
    });

/// Async workspace children loader for explorer lazy tree.
typedef WorkspaceListChildrenInvoker =
    Future<rust_api.WorkspaceListChildrenResponse> Function({
      String? parentNodeId,
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
  static const String _uncategorizedFolderNodeId = '__uncategorized__';
  static const String _uncategorizedFolderDisplayName = 'Uncategorized';
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

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
    WorkspaceDeleteFolderInvoker? workspaceDeleteFolderInvoker,
    WorkspaceCreateFolderInvoker? workspaceCreateFolderInvoker,
    WorkspaceCreateNoteRefInvoker? workspaceCreateNoteRefInvoker,
    WorkspaceRenameNodeInvoker? workspaceRenameNodeInvoker,
    WorkspaceMoveNodeInvoker? workspaceMoveNodeInvoker,
    WorkspaceListChildrenInvoker? workspaceListChildrenInvoker,
    WorkspaceProvider? workspaceProvider,
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
       _workspaceDeleteFolderInvoker =
           workspaceDeleteFolderInvoker ?? _defaultWorkspaceDeleteFolderInvoker,
       _workspaceCreateFolderInvoker =
           workspaceCreateFolderInvoker ?? _defaultWorkspaceCreateFolderInvoker,
       _workspaceCreateNoteRefInvoker =
           workspaceCreateNoteRefInvoker ??
           _defaultWorkspaceCreateNoteRefInvoker,
       _workspaceRenameNodeInvoker =
           workspaceRenameNodeInvoker ?? _defaultWorkspaceRenameNodeInvoker,
       _workspaceMoveNodeInvoker =
           workspaceMoveNodeInvoker ?? _defaultWorkspaceMoveNodeInvoker,
       _workspaceListChildrenInvoker =
           workspaceListChildrenInvoker ?? _defaultWorkspaceListChildrenInvoker,
       _debounceTimerFactory = debounceTimerFactory ?? Timer.new,
       _prepare = prepare ?? _defaultPrepare {
    _workspaceProvider =
        workspaceProvider ??
        WorkspaceProvider(
          autosaveDebounce: autosaveDebounce,
          autosaveEnabled: false,
        );
    _ownsWorkspaceProvider = workspaceProvider == null;
  }

  final NotesListInvoker _notesListInvoker;
  final NoteGetInvoker _noteGetInvoker;
  final NoteCreateInvoker _noteCreateInvoker;
  final NoteUpdateInvoker _noteUpdateInvoker;
  final TagsListInvoker _tagsListInvoker;
  final NoteSetTagsInvoker _noteSetTagsInvoker;
  final WorkspaceDeleteFolderInvoker _workspaceDeleteFolderInvoker;
  final WorkspaceCreateFolderInvoker _workspaceCreateFolderInvoker;
  final WorkspaceCreateNoteRefInvoker _workspaceCreateNoteRefInvoker;
  final WorkspaceRenameNodeInvoker _workspaceRenameNodeInvoker;
  final WorkspaceMoveNodeInvoker _workspaceMoveNodeInvoker;
  final WorkspaceListChildrenInvoker _workspaceListChildrenInvoker;
  final DebounceTimerFactory _debounceTimerFactory;
  final NotesPrepare _prepare;
  late final WorkspaceProvider _workspaceProvider;
  late final bool _ownsWorkspaceProvider;

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
  String? _createWarningMessage;
  Future<void>? _createTagApplyFuture;

  final List<String> _openNoteIds = <String>[];
  final Map<String, rust_api.NoteItem> _noteCache =
      <String, rust_api.NoteItem>{};
  final Map<String, String> _draftContentByAtomId = <String, String>{};
  final Map<String, String> _persistedContentByAtomId = <String, String>{};
  final Map<String, int> _draftVersionByAtomId = <String, int>{};
  String? _activeNoteId;
  String? _previewTabId;
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
  final Map<String, Future<void>> _tagMutationQueueByAtomId =
      <String, Future<void>>{};
  String? _switchBlockErrorMessage;
  bool _workspaceDeleteInFlight = false;
  String? _workspaceDeleteErrorMessage;
  bool _workspaceCreateFolderInFlight = false;
  String? _workspaceCreateFolderErrorMessage;
  bool _workspaceNodeMutationInFlight = false;
  String? _workspaceNodeMutationErrorMessage;
  int _workspaceTreeRevision = 0;

  int _listRequestId = 0;
  int _detailRequestId = 0;
  int _tagsRequestId = 0;
  bool _disposed = false;

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
  String? get activeNoteId {
    if (_workspaceProvider.layoutState.paneOrder.length > 1) {
      return _workspaceProvider.activeNoteId;
    }
    return _workspaceProvider.activeNoteId ?? _activeNoteId;
  }

  /// Current preview tab id (replaced by next explorer-open unless pinned).
  String? get previewTabId => _previewTabId;

  /// Currently opened tab ids in order.
  List<String> get openNoteIds {
    final workspaceTabs =
        _workspaceProvider.openTabsByPane[_workspaceProvider.activePaneId] ??
        const <String>[];
    if (_workspaceProvider.layoutState.paneOrder.length > 1) {
      return List.unmodifiable(workspaceTabs);
    }
    if (workspaceTabs.isEmpty) {
      return List.unmodifiable(_openNoteIds);
    }
    return List.unmodifiable(workspaceTabs);
  }

  /// Whether one tab is currently marked as preview.
  bool isPreviewTab(String atomId) => _previewTabId == atomId;

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

  /// Non-fatal create warning (e.g. contextual tag apply failed).
  String? get createWarningMessage => _createWarningMessage;

  /// Whether contextual create-tag apply is currently in flight.
  bool get createTagApplyInFlight => _createTagApplyFuture != null;

  /// Whether workspace folder delete request is currently in flight.
  bool get workspaceDeleteInFlight => _workspaceDeleteInFlight;

  /// Last workspace folder delete failure message.
  String? get workspaceDeleteErrorMessage => _workspaceDeleteErrorMessage;

  /// Whether workspace folder create request is currently in flight.
  bool get workspaceCreateFolderInFlight => _workspaceCreateFolderInFlight;

  /// Last workspace folder create failure message.
  String? get workspaceCreateFolderErrorMessage =>
      _workspaceCreateFolderErrorMessage;

  /// Whether workspace node mutation request is currently in flight.
  bool get workspaceNodeMutationInFlight => _workspaceNodeMutationInFlight;

  /// Last workspace node mutation failure message.
  String? get workspaceNodeMutationErrorMessage =>
      _workspaceNodeMutationErrorMessage;

  /// Monotonic revision bump for explorer tree refresh triggers.
  int get workspaceTreeRevision => _workspaceTreeRevision;

  /// Workspace state owner used by Notes bridge (M2).
  WorkspaceProvider get workspaceProvider => _workspaceProvider;

  /// Splits current active pane and keeps controller/editor routing aligned.
  WorkspaceSplitResult splitActivePane({
    required WorkspaceSplitDirection direction,
    required double containerExtent,
  }) {
    final result = _workspaceProvider.splitActivePane(
      direction: direction,
      containerExtent: containerExtent,
    );
    if (result != WorkspaceSplitResult.ok) {
      return result;
    }
    _syncWorkspaceFromControllerState();
    _adoptWorkspaceActivePaneState(loadDetail: false);
    notifyListeners();
    return result;
  }

  /// Closes active pane and merges it into adjacent pane.
  WorkspaceMergeResult closeActivePane() {
    final result = _workspaceProvider.closeActivePane();
    if (result != WorkspaceMergeResult.ok) {
      return result;
    }
    _syncWorkspaceFromControllerState();
    _adoptWorkspaceActivePaneState(loadDetail: false);
    notifyListeners();
    return result;
  }

  /// Switches active pane pointer and refreshes active editor target.
  bool switchActivePane(String paneId) {
    if (!_workspaceProvider.layoutState.paneOrder.contains(paneId)) {
      return false;
    }
    _workspaceProvider.switchActivePane(paneId);
    _adoptWorkspaceActivePaneState();
    return true;
  }

  /// Cycles active pane focus in layout order.
  void activateNextPane() {
    final order = _workspaceProvider.layoutState.paneOrder;
    if (order.length <= 1) {
      return;
    }
    final currentIndex = order.indexOf(_workspaceProvider.activePaneId);
    if (currentIndex < 0) {
      return;
    }
    final nextPaneId = order[(currentIndex + 1) % order.length];
    switchActivePane(nextPaneId);
  }

  /// Returns and clears the latest non-fatal create warning.
  String? takeCreateWarningMessage() {
    final warning = _createWarningMessage;
    _createWarningMessage = null;
    return warning;
  }

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
    if (_createTagApplyFuture != null) {
      return true;
    }
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
    final workspaceActive = _workspaceProvider.activeNoteId;
    if (workspaceActive != null &&
        _workspaceProvider.buffersByNoteId.containsKey(workspaceActive)) {
      return _workspaceProvider.activeDraftContent;
    }

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
    _disposed = true;
    _autosaveTimer?.cancel();
    _savedBadgeTimer?.cancel();
    if (_ownsWorkspaceProvider) {
      _workspaceProvider.dispose();
    }
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
    await _awaitCreateTagApply();
    await _awaitPendingTagMutations();
    await _loadNotes(
      resetSession: true,
      preserveActiveWhenFilteredOut: false,
      refreshTags: true,
    );
  }

  /// Retries notes list for current filter without resetting opened tabs.
  Future<void> retryLoad() async {
    await _awaitCreateTagApply();
    await _awaitPendingTagMutations();
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
  ///
  /// Explorer emits open intent only. Preview/pinned semantics are owned by
  /// tab model: explorer-open marks target as preview and may replace previous
  /// clean preview tab.
  Future<bool> openNoteFromExplorer(String atomId) async {
    final alreadyOpened = _openNoteIds.contains(atomId);
    String? replacePreviewId;
    if (!alreadyOpened) {
      final previousPreviewId = _previewTabId;
      if (previousPreviewId != null && previousPreviewId != atomId) {
        if (_hasPendingSaveFor(previousPreviewId)) {
          // Why: dirty/in-flight preview must be preserved to avoid silent
          // draft loss. Promote it to pinned and open new preview separately.
          _previewTabId = null;
        } else {
          replacePreviewId = previousPreviewId;
        }
      }
    }

    if (replacePreviewId != null) {
      return _selectFromExplorerByReplacingPreview(
        atomId: atomId,
        previewId: replacePreviewId,
      );
    }

    if (!alreadyOpened) {
      _previewTabId = atomId;
    }
    final switched = await selectNote(atomId);
    if (!switched) {
      if (!alreadyOpened && _previewTabId == atomId) {
        _previewTabId = null;
      }
      return false;
    }
    return true;
  }

  /// Handles explicit pinned-open request from explorer double-click.
  Future<bool> openNoteFromExplorerPinned(String atomId) async {
    if (_activeNoteId == atomId) {
      pinPreviewTab(atomId);
      return true;
    }
    if (_openNoteIds.contains(atomId)) {
      final switched = await selectNote(atomId);
      if (!switched) {
        return false;
      }
      pinPreviewTab(atomId);
      return true;
    }
    final opened = await openNoteFromExplorer(atomId);
    if (!opened) {
      return false;
    }
    pinPreviewTab(atomId);
    return true;
  }

  /// Pins one preview tab so it is not replaced by next explorer-open.
  void pinPreviewTab(String atomId) {
    if (_previewTabId != atomId) {
      return;
    }
    _previewTabId = null;
    notifyListeners();
  }

  Future<bool> _selectFromExplorerByReplacingPreview({
    required String atomId,
    required String previewId,
  }) async {
    final previewIndex = _openNoteIds.indexOf(previewId);
    if (previewIndex < 0) {
      _previewTabId = atomId;
      return selectNote(atomId);
    }
    if (_activeNoteId != null && _activeNoteId != atomId) {
      final flushed = await flushPendingSave();
      if (!flushed) {
        return false;
      }
    }

    // Why: replace preview tab in place to avoid transient tab-count jitter.
    _openNoteIds[previewIndex] = atomId;
    _evictNoteState(previewId);
    _activeNoteId = atomId;
    _selectedNote = _findListItem(atomId);
    _activeDraftAtomId = atomId;
    _activeDraftContent =
        _draftContentByAtomId[atomId] ?? _selectedNote?.content ?? '';
    _refreshSaveStateForActive();
    _requestEditorFocus();
    _switchBlockErrorMessage = null;
    _previewTabId = atomId;
    _syncWorkspaceFromControllerState();
    // Why: preview-replace can target a note currently owned by another pane;
    // enforce active-pane snapshot before async detail result returns.
    _syncWorkspaceActiveSnapshot();
    notifyListeners();

    await _loadSelectedDetail(atomId: atomId);
    return true;
  }

  /// Creates one workspace folder under root or one parent folder.
  Future<rust_api.WorkspaceNodeResponse> createWorkspaceFolder({
    required String name,
    String? parentNodeId,
  }) async {
    if (_workspaceCreateFolderInFlight) {
      return const rust_api.WorkspaceNodeResponse(
        ok: false,
        errorCode: 'busy',
        message: 'Workspace folder create is already in progress.',
        node: null,
      );
    }

    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return const rust_api.WorkspaceNodeResponse(
        ok: false,
        errorCode: 'invalid_display_name',
        message: 'Folder name is required.',
        node: null,
      );
    }
    final normalizedParent = parentNodeId?.trim();
    if (normalizedParent != null && normalizedParent.isEmpty) {
      return const rust_api.WorkspaceNodeResponse(
        ok: false,
        errorCode: 'invalid_parent_node_id',
        message: 'Parent node id is invalid.',
        node: null,
      );
    }
    if (normalizedParent != null && !_uuidPattern.hasMatch(normalizedParent)) {
      return const rust_api.WorkspaceNodeResponse(
        ok: false,
        errorCode: 'invalid_parent_node_id',
        message: 'Parent node id must be a UUID.',
        node: null,
      );
    }

    _workspaceCreateFolderInFlight = true;
    _workspaceCreateFolderErrorMessage = null;
    notifyListeners();

    try {
      await _prepare();
      final response = await _workspaceCreateFolderInvoker(
        parentNodeId: normalizedParent,
        name: normalizedName,
      );
      if (!response.ok) {
        _workspaceCreateFolderErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to create workspace folder.',
        );
        return response;
      }
      _workspaceCreateFolderErrorMessage = null;
      _bumpWorkspaceTreeRevision();
      return response;
    } catch (error) {
      final message = 'Workspace folder create failed unexpectedly: $error';
      _workspaceCreateFolderErrorMessage = message;
      return rust_api.WorkspaceNodeResponse(
        ok: false,
        errorCode: 'internal_error',
        message: message,
        node: null,
      );
    } finally {
      _workspaceCreateFolderInFlight = false;
      notifyListeners();
    }
  }

  /// Creates one note and links it into workspace tree under optional parent.
  ///
  /// Contract:
  /// - Parent id must be `null` or UUID (`__uncategorized__` is mapped to root).
  /// - Uses existing note create flow, then links note via `workspace_create_note_ref`.
  /// - On success, created note is active and tree revision is bumped.
  Future<rust_api.WorkspaceActionResponse> createWorkspaceNoteInFolder({
    String? parentNodeId,
  }) async {
    if (_workspaceNodeMutationInFlight) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'busy',
        message: 'Workspace node mutation is already in progress.',
      );
    }

    final normalizedParent = _normalizeWorkspaceParentId(parentNodeId);
    if (normalizedParent == _WorkspaceParentValidation.invalid) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_parent_node_id',
        message: 'Parent node id must be a UUID or null.',
      );
    }
    final parentForCreateRef = switch (normalizedParent) {
      _WorkspaceParentValidation.root => null,
      _WorkspaceParentValidation.value => parentNodeId?.trim(),
      _WorkspaceParentValidation.invalid => null,
    };

    _workspaceNodeMutationInFlight = true;
    _workspaceNodeMutationErrorMessage = null;
    notifyListeners();
    try {
      final created = await createNote();
      if (!created) {
        final message = _createErrorMessage?.trim().isNotEmpty == true
            ? _createErrorMessage!
            : 'Failed to create note before linking to workspace.';
        _workspaceNodeMutationErrorMessage = message;
        return rust_api.WorkspaceActionResponse(
          ok: false,
          errorCode: 'internal_error',
          message: message,
        );
      }
      final atomId = _activeNoteId;
      if (atomId == null || atomId.trim().isEmpty) {
        _workspaceNodeMutationErrorMessage =
            'Created note is missing atom id for workspace linking.';
        return const rust_api.WorkspaceActionResponse(
          ok: false,
          errorCode: 'internal_error',
          message: 'Created note is missing atom id for workspace linking.',
        );
      }

      await _prepare();
      final linkResponse = await _workspaceCreateNoteRefInvoker(
        parentNodeId: parentForCreateRef,
        atomId: atomId,
        displayName: null,
      );
      if (!linkResponse.ok) {
        final message = _envelopeError(
          errorCode: linkResponse.errorCode,
          message: linkResponse.message,
          fallback: 'Note created, but linking into workspace failed.',
        );
        _workspaceNodeMutationErrorMessage = message;
        return rust_api.WorkspaceActionResponse(
          ok: false,
          errorCode: linkResponse.errorCode,
          message: message,
        );
      }

      _workspaceNodeMutationErrorMessage = null;
      _bumpWorkspaceTreeRevision();
      return const rust_api.WorkspaceActionResponse(
        ok: true,
        errorCode: null,
        message: 'ok',
      );
    } catch (error) {
      final message = 'Workspace note create failed unexpectedly: $error';
      _workspaceNodeMutationErrorMessage = message;
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'internal_error',
        message: message,
      );
    } finally {
      _workspaceNodeMutationInFlight = false;
      notifyListeners();
    }
  }

  /// Renames one workspace node.
  Future<rust_api.WorkspaceActionResponse> renameWorkspaceNode({
    required String nodeId,
    required String newName,
  }) async {
    if (_workspaceNodeMutationInFlight) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'busy',
        message: 'Workspace node mutation is already in progress.',
      );
    }
    final normalizedNodeId = nodeId.trim();
    if (normalizedNodeId.isEmpty || !_uuidPattern.hasMatch(normalizedNodeId)) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_node_id',
        message: 'Node id must be a UUID.',
      );
    }
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_display_name',
        message: 'Node name is required.',
      );
    }

    _workspaceNodeMutationInFlight = true;
    _workspaceNodeMutationErrorMessage = null;
    notifyListeners();
    try {
      await _prepare();
      final response = await _workspaceRenameNodeInvoker(
        nodeId: normalizedNodeId,
        newName: normalizedName,
      );
      if (!response.ok) {
        _workspaceNodeMutationErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to rename workspace node.',
        );
        return response;
      }
      _workspaceNodeMutationErrorMessage = null;
      _bumpWorkspaceTreeRevision();
      return response;
    } catch (error) {
      final message = 'Workspace node rename failed unexpectedly: $error';
      _workspaceNodeMutationErrorMessage = message;
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'internal_error',
        message: message,
      );
    } finally {
      _workspaceNodeMutationInFlight = false;
      notifyListeners();
    }
  }

  /// Moves one workspace node under optional target parent.
  Future<rust_api.WorkspaceActionResponse> moveWorkspaceNode({
    required String nodeId,
    String? newParentNodeId,
    int? targetOrder,
  }) async {
    if (_workspaceNodeMutationInFlight) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'busy',
        message: 'Workspace node mutation is already in progress.',
      );
    }
    final normalizedNodeId = nodeId.trim();
    if (normalizedNodeId.isEmpty || !_uuidPattern.hasMatch(normalizedNodeId)) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_node_id',
        message: 'Node id must be a UUID.',
      );
    }
    final normalizedParent = _normalizeWorkspaceParentId(newParentNodeId);
    if (normalizedParent == _WorkspaceParentValidation.invalid) {
      return const rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_parent_node_id',
        message: 'Parent node id must be a UUID or null.',
      );
    }
    final parentForMove = switch (normalizedParent) {
      _WorkspaceParentValidation.root => null,
      _WorkspaceParentValidation.value => newParentNodeId?.trim(),
      _WorkspaceParentValidation.invalid => null,
    };
    final _ = targetOrder;

    _workspaceNodeMutationInFlight = true;
    _workspaceNodeMutationErrorMessage = null;
    notifyListeners();
    try {
      await _prepare();
      final response = await _workspaceMoveNodeInvoker(
        nodeId: normalizedNodeId,
        newParentId: parentForMove,
        // v0.2 transition freeze: UI move path is parent-change-only.
        // Keep `targetOrder` in API shape for compatibility, but do not pass it.
        targetOrder: null,
      );
      if (!response.ok) {
        _workspaceNodeMutationErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to move workspace node.',
        );
        return response;
      }
      _workspaceNodeMutationErrorMessage = null;
      _bumpWorkspaceTreeRevision();
      return response;
    } catch (error) {
      final message = 'Workspace node move failed unexpectedly: $error';
      _workspaceNodeMutationErrorMessage = message;
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'internal_error',
        message: message,
      );
    } finally {
      _workspaceNodeMutationInFlight = false;
      notifyListeners();
    }
  }

  /// Lists workspace tree children for explorer lazy rendering.
  ///
  /// Contract:
  /// - Returns core FFI response when call succeeds.
  /// - Synthetic `Uncategorized` children are projected as:
  ///   - root-level `note_ref` rows from workspace tree
  ///   - legacy notes with no workspace `note_ref` anywhere in tree
  /// - Uses synthetic fallback only when bridge is unavailable (e.g. Rust bridge
  ///   not initialized in test host).
  /// - Returns explicit error envelope when bridge call throws so UI can render
  ///   actionable error + retry state.
  Future<rust_api.WorkspaceListChildrenResponse> listWorkspaceChildren({
    String? parentNodeId,
  }) async {
    if (parentNodeId == _uncategorizedFolderNodeId) {
      return _listProjectedUncategorizedChildren();
    }
    try {
      await _prepare();
      final response = await _workspaceListChildrenInvoker(
        parentNodeId: parentNodeId,
      );
      return _decorateWorkspaceChildren(
        parentNodeId: parentNodeId,
        response: response,
      );
    } catch (error) {
      if (_shouldUseWorkspaceTreeSyntheticFallback(error)) {
        return _fallbackWorkspaceChildren(parentNodeId: parentNodeId);
      }
      return rust_api.WorkspaceListChildrenResponse(
        ok: false,
        errorCode: 'internal_error',
        message: 'Workspace tree load failed unexpectedly: $error',
        items: const <rust_api.WorkspaceNodeItem>[],
      );
    }
  }

  /// Deletes one workspace folder by explicit mode, then refreshes UI state.
  ///
  /// Contract:
  /// - `mode` must be `dissolve` or `delete_all`.
  /// - Flushes active draft before mutation to avoid local data loss.
  /// - Refreshes list and reconciles open tabs after successful delete.
  Future<rust_api.WorkspaceActionResponse> deleteWorkspaceFolder({
    required String folderId,
    required String mode,
  }) async {
    if (_workspaceDeleteInFlight) {
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'busy',
        message: 'Workspace delete is already in progress.',
      );
    }

    final normalizedFolderId = folderId.trim();
    if (normalizedFolderId.isEmpty) {
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_node_id',
        message: 'Folder id is required.',
      );
    }
    final normalizedMode = mode.trim();
    if (normalizedMode != 'dissolve' && normalizedMode != 'delete_all') {
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'invalid_delete_mode',
        message: 'Delete mode must be dissolve or delete_all.',
      );
    }

    final flushed = await flushPendingSave();
    if (!flushed) {
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'save_blocked',
        message: 'Save failed. Retry or back up content before folder delete.',
      );
    }

    _workspaceDeleteInFlight = true;
    _workspaceDeleteErrorMessage = null;
    notifyListeners();

    try {
      await _prepare();
      final response = await _workspaceDeleteFolderInvoker(
        nodeId: normalizedFolderId,
        mode: normalizedMode,
      );
      if (!response.ok) {
        _workspaceDeleteErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to delete workspace folder.',
        );
        return response;
      }

      await _loadNotes(
        resetSession: false,
        preserveActiveWhenFilteredOut: true,
        refreshTags: false,
      );
      await _reconcileOpenTabsAfterWorkspaceMutation();
      _workspaceDeleteErrorMessage = null;
      _bumpWorkspaceTreeRevision();
      return response;
    } catch (error) {
      final message = 'Workspace folder delete failed unexpectedly: $error';
      _workspaceDeleteErrorMessage = message;
      return rust_api.WorkspaceActionResponse(
        ok: false,
        errorCode: 'internal_error',
        message: message,
      );
    } finally {
      _workspaceDeleteInFlight = false;
      notifyListeners();
    }
  }

  /// Flushes pending save work for the currently active note.
  ///
  /// Contract:
  /// - Returns `true` when no pending write exists or persistence succeeds.
  /// - Returns `false` when latest draft cannot be persisted.
  /// - Keeps in-memory draft unchanged on failure.
  Future<bool> flushPendingSave() async {
    await _awaitCreateTagApply(timeout: const Duration(milliseconds: 800));
    final atomId = _activeNoteId;
    if (atomId == null) {
      return true;
    }
    _autosaveTimer?.cancel();

    while (true) {
      if (_tagMutationQueueByAtomId[atomId] case final queuedTagMutation?) {
        try {
          await queuedTagMutation;
        } catch (_) {}
        continue;
      }
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
    _createWarningMessage = null;
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
        final taggedFuture = _noteSetTagsInvoker(
          atomId: created.atomId,
          tags: <String>[activeTag],
        );
        final pendingMarker = taggedFuture.then(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        );
        _createTagApplyFuture = pendingMarker;
        notifyListeners();
        try {
          final tagged = await taggedFuture;
          if (tagged.ok && tagged.note != null) {
            createdNote = tagged.note!;
          } else {
            _createWarningMessage =
                'Note created, but applying active filter tag failed. Check All Notes.';
          }
        } finally {
          if (identical(_createTagApplyFuture, pendingMarker)) {
            _createTagApplyFuture = null;
            notifyListeners();
          }
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
      _syncWorkspaceFromControllerState();
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
    return _enqueueTagMutation(
      atomId: atomId,
      mutation: () => _setNoteTags(atomId: atomId, normalizedTags: normalized),
    );
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
    return _enqueueTagMutation(
      atomId: atomId,
      mutation: () async {
        final current = _noteCache[atomId] ?? _selectedNote;
        if (current == null) {
          return false;
        }
        if (current.tags.contains(normalized)) {
          return true;
        }
        return _setNoteTags(
          atomId: atomId,
          normalizedTags: _normalizeTags(<String>[...current.tags, normalized]),
        );
      },
    );
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
    return _enqueueTagMutation(
      atomId: atomId,
      mutation: () async {
        final current = _noteCache[atomId] ?? _selectedNote;
        if (current == null) {
          return false;
        }
        if (!current.tags.contains(normalized)) {
          return true;
        }
        final next = current.tags
            .where((entry) => entry != normalized)
            .toList();
        return _setNoteTags(
          atomId: atomId,
          normalizedTags: _normalizeTags(next),
        );
      },
    );
  }

  Future<bool> _enqueueTagMutation({
    required String atomId,
    required Future<bool> Function() mutation,
  }) {
    final previous = _tagMutationQueueByAtomId[atomId] ?? Future<void>.value();
    final completer = Completer<bool>();
    late final Future<void> queued;
    queued = previous
        .catchError((_) {})
        .then((_) async {
          try {
            final result = await mutation();
            completer.complete(result);
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_tagMutationQueueByAtomId[atomId], queued)) {
            _tagMutationQueueByAtomId.remove(atomId);
          }
        });
    _tagMutationQueueByAtomId[atomId] = queued;
    return completer.future;
  }

  Future<void> _awaitPendingTagMutations() async {
    while (true) {
      final snapshot = _tagMutationQueueByAtomId.values.toList();
      if (snapshot.isEmpty) {
        if (_tagSaveInFlightAtomIds.isEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 12));
        continue;
      }
      await Future.wait(snapshot.map((future) => future.catchError((_) {})));
    }
  }

  Future<void> _reconcileOpenTabsAfterWorkspaceMutation() async {
    if (_openNoteIds.isEmpty) {
      return;
    }

    final openSnapshot = List<String>.from(_openNoteIds);
    final removedAtomIds = <String>[];
    for (final atomId in openSnapshot) {
      try {
        final response = await _noteGetInvoker(atomId: atomId);
        if (!response.ok) {
          if (response.errorCode == 'note_not_found') {
            removedAtomIds.add(atomId);
          }
          continue;
        }
        if (response.note case final note?) {
          _insertOrReplaceListItem(note, updatePersisted: true);
        }
      } catch (_) {
        // Keep tab state unchanged when detail check fails unexpectedly.
      }
    }

    if (removedAtomIds.isEmpty) {
      return;
    }

    final previousActiveId = _activeNoteId;
    final previousActiveIndex = previousActiveId == null
        ? -1
        : openSnapshot.indexOf(previousActiveId);
    final activeRemoved =
        previousActiveId != null && removedAtomIds.contains(previousActiveId);

    _openNoteIds.removeWhere(removedAtomIds.contains);
    for (final atomId in removedAtomIds) {
      _evictNoteState(atomId);
    }
    _reconcilePreviewTabState();

    if (_openNoteIds.isEmpty) {
      _activeNoteId = null;
      _selectedNote = null;
      _detailLoading = false;
      _detailErrorMessage = null;
      _activeDraftAtomId = null;
      _activeDraftContent = '';
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
      _syncWorkspaceFromControllerState();
      notifyListeners();
      return;
    }

    if (!activeRemoved) {
      _syncWorkspaceFromControllerState();
      notifyListeners();
      return;
    }

    final fallbackIndex = previousActiveIndex <= 0
        ? 0
        : (previousActiveIndex - 1).clamp(0, _openNoteIds.length - 1);
    final fallbackId = _openNoteIds[fallbackIndex];
    _activeNoteId = fallbackId;
    _selectedNote = noteById(fallbackId);
    _activeDraftAtomId = fallbackId;
    _activeDraftContent =
        _draftContentByAtomId[fallbackId] ?? _selectedNote?.content ?? '';
    _refreshSaveStateForActive();
    _requestEditorFocus();
    _syncWorkspaceFromControllerState();
    notifyListeners();
    await _loadSelectedDetail(atomId: fallbackId);
  }

  void _evictNoteState(String atomId) {
    if (_previewTabId == atomId) {
      _previewTabId = null;
    }
    _noteCache.remove(atomId);
    _draftContentByAtomId.remove(atomId);
    _persistedContentByAtomId.remove(atomId);
    _draftVersionByAtomId.remove(atomId);
    _saveFutureByAtomId.remove(atomId);
    _saveQueuedByAtomId.remove(atomId);
    _tagSaveInFlightAtomIds.remove(atomId);
    _tagMutationQueueByAtomId.remove(atomId);
  }

  Future<void> _awaitCreateTagApply({Duration? timeout}) async {
    final pending = _createTagApplyFuture;
    if (pending == null) {
      return;
    }
    try {
      if (timeout == null) {
        await pending;
      } else {
        await pending.timeout(timeout, onTimeout: () {});
      }
    } catch (_) {}
  }

  Future<bool> _setNoteTags({
    required String atomId,
    required List<String> normalizedTags,
  }) async {
    final current = _noteCache[atomId] ?? _selectedNote;
    if (current == null) {
      return false;
    }
    if (listEquals(current.tags, normalizedTags)) {
      return true;
    }

    _tagSaveInFlightAtomIds.add(atomId);
    _setSaveState(NoteSaveState.saving);
    notifyListeners();

    try {
      await _prepare();
      final response = await _noteSetTagsInvoker(
        atomId: atomId,
        tags: normalizedTags,
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
        _syncWorkspaceActiveSnapshot();
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
    _syncWorkspaceFromControllerState();
    // Why: keep split-mode active pane projection aligned even when detail
    // request fails. Prevents controller/workspace active-note divergence.
    _syncWorkspaceActiveSnapshot();
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
  ///
  /// Split mode cycles inside active-pane tabs only.
  Future<void> activateNextOpenNote() async {
    final scopedOpenNoteIds = openNoteIds;
    final scopedActiveNoteId = activeNoteId;
    if (scopedOpenNoteIds.length <= 1 || scopedActiveNoteId == null) {
      return;
    }
    final currentIndex = scopedOpenNoteIds.indexOf(scopedActiveNoteId);
    if (currentIndex < 0) {
      return;
    }
    final nextIndex = (currentIndex + 1) % scopedOpenNoteIds.length;
    await activateOpenNote(scopedOpenNoteIds[nextIndex]);
  }

  /// Moves active tab backward (Ctrl+Shift+Tab behavior).
  ///
  /// Split mode cycles inside active-pane tabs only.
  Future<void> activatePreviousOpenNote() async {
    final scopedOpenNoteIds = openNoteIds;
    final scopedActiveNoteId = activeNoteId;
    if (scopedOpenNoteIds.length <= 1 || scopedActiveNoteId == null) {
      return;
    }
    final currentIndex = scopedOpenNoteIds.indexOf(scopedActiveNoteId);
    if (currentIndex < 0) {
      return;
    }
    final prevIndex =
        (currentIndex - 1 + scopedOpenNoteIds.length) %
        scopedOpenNoteIds.length;
    await activateOpenNote(scopedOpenNoteIds[prevIndex]);
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
    _reconcilePreviewTabState();
    if (_activeNoteId != atomId) {
      _syncWorkspaceFromControllerState();
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
      _syncWorkspaceFromControllerState();
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
    _syncWorkspaceFromControllerState();
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
    _reconcilePreviewTabState();
    _syncWorkspaceFromControllerState();
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
    _reconcilePreviewTabState();
    if (!_openNoteIds.contains(_activeNoteId)) {
      _activeNoteId = atomId;
      _selectedNote = noteById(atomId);
      _activeDraftAtomId = atomId;
      _activeDraftContent =
          _draftContentByAtomId[atomId] ?? _selectedNote?.content ?? '';
      _refreshSaveStateForActive();
      _requestEditorFocus();
      _syncWorkspaceFromControllerState();
      notifyListeners();
      await _loadSelectedDetail(atomId: atomId);
      return true;
    }
    _syncWorkspaceFromControllerState();
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
    if (_previewTabId == atomId) {
      // Why: once user edits preview content, replacing that tab on next open
      // is surprising and risks hidden draft loss. Promote to pinned.
      _previewTabId = null;
    }

    if (_isDirty(atomId)) {
      _setSaveState(NoteSaveState.dirty);
      _scheduleAutosave(atomId: atomId, version: version);
    } else {
      _autosaveTimer?.cancel();
      _setSaveState(NoteSaveState.clean);
    }
    _syncWorkspaceActiveSnapshot();
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
      _reconcilePreviewTabState();
      _syncWorkspaceFromControllerState();
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
    _tagMutationQueueByAtomId.clear();
    _activeNoteId = null;
    _previewTabId = null;
    _activeDraftAtomId = null;
    _activeDraftContent = '';
    _creatingNote = false;
    _createErrorMessage = null;
    _createWarningMessage = null;
    _createTagApplyFuture = null;
    _autosaveTimer?.cancel();
    _savedBadgeTimer?.cancel();
    _noteSaveState = NoteSaveState.clean;
    _saveErrorMessage = null;
    _showSavedBadge = false;
    _syncWorkspaceFromControllerState();
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

      final normalizedTags = List<String>.unmodifiable(
        _normalizeTags(response.tags),
      );
      _availableTags = normalizedTags;
      _tagsLoading = false;
      _tagsErrorMessage = null;
      notifyListeners();

      final staleSelectedTag = _selectedTag;
      if (staleSelectedTag != null &&
          !normalizedTags.contains(staleSelectedTag)) {
        // Why: selected filter can outlive its chip after tag pruning.
        // Auto-clear prevents hidden filter lock when no chip exists to toggle.
        _selectedTag = null;
        await _loadNotes(
          resetSession: false,
          preserveActiveWhenFilteredOut: false,
          refreshTags: false,
        );
      }
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
    if (_disposed) {
      return;
    }
    final requestId = ++_detailRequestId;
    _detailLoading = true;
    _detailErrorMessage = null;
    _selectedNote = _findListItem(atomId) ?? _selectedNote;
    if (_disposed) {
      return;
    }
    notifyListeners();

    try {
      await _prepare();
      if (_disposed ||
          requestId != _detailRequestId ||
          atomId != _activeNoteId) {
        return;
      }

      final response = await _noteGetInvoker(atomId: atomId);
      if (_disposed ||
          requestId != _detailRequestId ||
          atomId != _activeNoteId) {
        return;
      }

      if (!response.ok) {
        _detailLoading = false;
        _detailErrorMessage = _envelopeError(
          errorCode: response.errorCode,
          message: response.message,
          fallback: 'Failed to load note detail.',
        );
        if (_disposed) {
          return;
        }
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
        _syncWorkspaceActiveSnapshot();
        if (_disposed) {
          return;
        }
        notifyListeners();
        return;
      }

      _detailLoading = false;
      _detailErrorMessage = 'Note detail is empty.';
      if (_disposed) {
        return;
      }
      notifyListeners();
    } catch (error) {
      if (_disposed ||
          requestId != _detailRequestId ||
          atomId != _activeNoteId) {
        return;
      }
      _detailLoading = false;
      _detailErrorMessage = 'Note detail load failed unexpectedly: $error';
      if (_disposed) {
        return;
      }
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

  void _reconcilePreviewTabState() {
    final previewId = _previewTabId;
    if (previewId == null) {
      return;
    }
    if (_openNoteIds.contains(previewId)) {
      return;
    }
    _previewTabId = null;
  }

  bool _hasPendingSaveFor(String atomId) {
    return _isDirty(atomId) ||
        _saveFutureByAtomId.containsKey(atomId) ||
        _tagSaveInFlightAtomIds.contains(atomId) ||
        _tagMutationQueueByAtomId.containsKey(atomId);
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
        _syncWorkspaceActiveSnapshot();
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
    if (_activeNoteId case final activeId?) {
      _workspaceProvider.syncSaveState(
        noteId: activeId,
        saveState: _mapSaveStateToWorkspace(nextState),
      );
    }
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

  WorkspaceSaveState _mapSaveStateToWorkspace(NoteSaveState state) {
    switch (state) {
      case NoteSaveState.clean:
        return WorkspaceSaveState.clean;
      case NoteSaveState.dirty:
        return WorkspaceSaveState.dirty;
      case NoteSaveState.saving:
        return WorkspaceSaveState.saving;
      case NoteSaveState.error:
        return WorkspaceSaveState.saveError;
    }
  }

  WorkspaceSaveState _workspaceSaveStateForNote(String atomId) {
    if (_activeNoteId == atomId) {
      return _mapSaveStateToWorkspace(_noteSaveState);
    }
    return _isDirty(atomId)
        ? WorkspaceSaveState.dirty
        : WorkspaceSaveState.clean;
  }

  String _workspacePersistedContentFor(String atomId) {
    final persisted = _persistedContentByAtomId[atomId];
    if (persisted != null) {
      return persisted;
    }
    final cached = _noteCache[atomId];
    if (cached != null) {
      return cached.content;
    }
    if (_selectedNote?.atomId == atomId) {
      return _selectedNote?.content ?? '';
    }
    return '';
  }

  String _workspaceDraftContentFor(String atomId) {
    return _draftContentByAtomId[atomId] ??
        _workspacePersistedContentFor(atomId);
  }

  void _adoptWorkspaceActivePaneState({bool loadDetail = true}) {
    final paneActiveId = _workspaceProvider.activeNoteId;
    _activeNoteId = paneActiveId;
    if (paneActiveId == null) {
      _selectedNote = null;
      _activeDraftAtomId = null;
      _activeDraftContent = '';
      _detailLoading = false;
      _detailErrorMessage = null;
      _setSaveState(NoteSaveState.clean);
      return;
    }

    final selected = _selectedNote?.atomId == paneActiveId
        ? _selectedNote
        : null;
    final local =
        _noteCache[paneActiveId] ?? selected ?? _findListItem(paneActiveId);
    _selectedNote = local;
    _activeDraftAtomId = paneActiveId;
    _activeDraftContent = _workspaceDraftContentFor(paneActiveId);
    _refreshSaveStateForActive();
    _switchBlockErrorMessage = null;
    _requestEditorFocus();
    if (loadDetail) {
      unawaited(_loadSelectedDetail(atomId: paneActiveId));
    }
  }

  void _syncWorkspaceActiveSnapshot() {
    final activeId = _activeNoteId;
    if (activeId == null) {
      return;
    }
    _workspaceProvider.syncExternalNote(
      noteId: activeId,
      persistedContent: _workspacePersistedContentFor(activeId),
      draftContent: _workspaceDraftContentFor(activeId),
      saveState: _workspaceSaveStateForNote(activeId),
      activate: true,
    );
  }

  void _syncWorkspaceFromControllerState() {
    _workspaceProvider.beginBatchSync();
    try {
      final paneOrder = List<String>.from(
        _workspaceProvider.layoutState.paneOrder,
      );
      final activePaneId = _workspaceProvider.activePaneId;
      final paneTabsBeforeReset = <String, List<String>>{};
      for (final paneId in paneOrder) {
        paneTabsBeforeReset[paneId] = List<String>.from(
          _workspaceProvider.openTabsByPane[paneId] ?? const <String>[],
        );
      }

      _workspaceProvider.resetAll();
      final restoredNoteIds = <String>{};
      for (final paneId in paneOrder) {
        final paneTabs = paneTabsBeforeReset[paneId] ?? const <String>[];
        for (final atomId in paneTabs) {
          if (!_openNoteIds.contains(atomId) && _activeNoteId != atomId) {
            continue;
          }
          _workspaceProvider.syncExternalNote(
            noteId: atomId,
            paneId: paneId,
            persistedContent: _workspacePersistedContentFor(atomId),
            draftContent: _workspaceDraftContentFor(atomId),
            saveState: _workspaceSaveStateForNote(atomId),
            activate: activePaneId == paneId && _activeNoteId == atomId,
          );
          restoredNoteIds.add(atomId);
        }
      }

      if (_openNoteIds.isEmpty && _activeNoteId == null) {
        return;
      }

      for (final atomId in _openNoteIds) {
        if (restoredNoteIds.contains(atomId)) {
          continue;
        }
        _workspaceProvider.syncExternalNote(
          noteId: atomId,
          paneId: activePaneId,
          persistedContent: _workspacePersistedContentFor(atomId),
          draftContent: _workspaceDraftContentFor(atomId),
          saveState: _workspaceSaveStateForNote(atomId),
          activate: _activeNoteId == atomId,
        );
        restoredNoteIds.add(atomId);
      }
      if (_activeNoteId case final activeId?) {
        if (!restoredNoteIds.contains(activeId)) {
          _workspaceProvider.syncExternalNote(
            noteId: activeId,
            paneId: activePaneId,
            persistedContent: _workspacePersistedContentFor(activeId),
            draftContent: _workspaceDraftContentFor(activeId),
            saveState: _workspaceSaveStateForNote(activeId),
            activate: true,
          );
        }
      }
    } finally {
      _workspaceProvider.endBatchSync();
    }
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

  _WorkspaceParentValidation _normalizeWorkspaceParentId(String? raw) {
    if (raw == null) {
      return _WorkspaceParentValidation.root;
    }
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return _WorkspaceParentValidation.invalid;
    }
    if (normalized == _uncategorizedFolderNodeId) {
      return _WorkspaceParentValidation.root;
    }
    if (!_uuidPattern.hasMatch(normalized)) {
      return _WorkspaceParentValidation.invalid;
    }
    return _WorkspaceParentValidation.value;
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

  void _bumpWorkspaceTreeRevision() {
    _workspaceTreeRevision += 1;
  }

  rust_api.WorkspaceListChildrenResponse _decorateWorkspaceChildren({
    required String? parentNodeId,
    required rust_api.WorkspaceListChildrenResponse response,
  }) {
    if (!response.ok || parentNodeId != null) {
      return response;
    }
    // Root note refs are projected under synthetic `Uncategorized` to avoid
    // duplicate rendering at both root and Uncategorized levels.
    final items = response.items
        .where((item) => item.kind != 'note_ref')
        .toList(growable: true);
    final hasUncategorized = items.any(
      (item) =>
          item.kind == 'folder' && item.nodeId == _uncategorizedFolderNodeId,
    );
    if (!hasUncategorized) {
      items.insert(
        0,
        const rust_api.WorkspaceNodeItem(
          nodeId: _uncategorizedFolderNodeId,
          kind: 'folder',
          parentNodeId: null,
          atomId: null,
          displayName: _uncategorizedFolderDisplayName,
          sortOrder: -1,
        ),
      );
    }
    return rust_api.WorkspaceListChildrenResponse(
      ok: response.ok,
      errorCode: response.errorCode,
      message: response.message,
      items: items,
    );
  }

  Future<rust_api.WorkspaceListChildrenResponse>
  _listProjectedUncategorizedChildren() async {
    try {
      await _prepare();
      final referencedAtomIds = <String>{};
      final visitedFolderIds = <String>{};
      final pendingParentIds = Queue<String?>()..add(null);
      List<rust_api.WorkspaceNodeItem>? rootItems;

      while (pendingParentIds.isNotEmpty) {
        final parentNodeId = pendingParentIds.removeFirst();
        final response = await _workspaceListChildrenInvoker(
          parentNodeId: parentNodeId,
        );
        if (!response.ok) {
          return rust_api.WorkspaceListChildrenResponse(
            ok: false,
            errorCode: response.errorCode,
            message: response.message,
            items: const <rust_api.WorkspaceNodeItem>[],
          );
        }
        if (parentNodeId == null) {
          rootItems = response.items;
        }
        for (final item in response.items) {
          if (item.kind == 'note_ref') {
            final atomId = item.atomId?.trim();
            if (atomId != null && atomId.isNotEmpty) {
              referencedAtomIds.add(atomId);
            }
            continue;
          }
          if (item.kind != 'folder') {
            continue;
          }
          final folderId = item.nodeId.trim();
          if (folderId.isEmpty || folderId == _uncategorizedFolderNodeId) {
            continue;
          }
          if (visitedFolderIds.add(folderId)) {
            pendingParentIds.add(folderId);
          }
        }
      }

      final projectedRows = <_ProjectedUncategorizedRow>[];
      final projectedAtomIds = <String>{};
      for (final item in rootItems ?? const <rust_api.WorkspaceNodeItem>[]) {
        if (item.kind != 'note_ref') {
          continue;
        }
        final atomId = item.atomId?.trim();
        if (atomId == null || atomId.isEmpty) {
          continue;
        }
        if (!projectedAtomIds.add(atomId)) {
          continue;
        }
        final note = noteById(atomId);
        final projectedDisplayName = note == null
            ? (item.displayName.trim().isEmpty ? 'Untitled' : item.displayName)
            : _titleFromContent(note.content);
        projectedRows.add(
          _ProjectedUncategorizedRow(
            nodeId: item.nodeId,
            atomId: atomId,
            displayName: projectedDisplayName,
            updatedAt: note?.updatedAt ?? 0,
          ),
        );
      }

      for (final note in _items) {
        final atomId = note.atomId.trim();
        if (atomId.isEmpty || referencedAtomIds.contains(atomId)) {
          continue;
        }
        if (!projectedAtomIds.add(atomId)) {
          continue;
        }
        projectedRows.add(
          _ProjectedUncategorizedRow(
            nodeId: 'note_ref_uncategorized_${note.atomId}',
            atomId: atomId,
            displayName: _titleFromContent(note.content),
            updatedAt: note.updatedAt,
          ),
        );
      }

      projectedRows.sort(_compareProjectedUncategorizedRow);
      final projectedItems = <rust_api.WorkspaceNodeItem>[];
      for (var index = 0; index < projectedRows.length; index += 1) {
        final row = projectedRows[index];
        projectedItems.add(
          rust_api.WorkspaceNodeItem(
            nodeId: row.nodeId,
            kind: 'note_ref',
            parentNodeId: _uncategorizedFolderNodeId,
            atomId: row.atomId,
            displayName: row.displayName,
            sortOrder: index,
          ),
        );
      }
      return rust_api.WorkspaceListChildrenResponse(
        ok: true,
        errorCode: null,
        message: 'synthetic_uncategorized',
        items: projectedItems,
      );
    } catch (error) {
      if (_shouldUseWorkspaceTreeSyntheticFallback(error)) {
        return _legacySyntheticUncategorizedChildren();
      }
      return rust_api.WorkspaceListChildrenResponse(
        ok: false,
        errorCode: 'internal_error',
        message: 'Workspace tree load failed unexpectedly: $error',
        items: const <rust_api.WorkspaceNodeItem>[],
      );
    }
  }

  rust_api.WorkspaceListChildrenResponse
  _legacySyntheticUncategorizedChildren() {
    final items = <rust_api.WorkspaceNodeItem>[];
    final sortedNotes = List<rust_api.NoteItem>.from(_items)
      ..sort((left, right) {
        final byUpdated = right.updatedAt.compareTo(left.updatedAt);
        if (byUpdated != 0) {
          return byUpdated;
        }
        return left.atomId.compareTo(right.atomId);
      });
    for (var index = 0; index < sortedNotes.length; index += 1) {
      final note = sortedNotes[index];
      items.add(
        rust_api.WorkspaceNodeItem(
          nodeId: 'note_ref_uncategorized_${note.atomId}',
          kind: 'note_ref',
          parentNodeId: _uncategorizedFolderNodeId,
          atomId: note.atomId,
          displayName: _titleFromContent(note.content),
          sortOrder: index,
        ),
      );
    }
    return rust_api.WorkspaceListChildrenResponse(
      ok: true,
      errorCode: null,
      message: 'synthetic_uncategorized_legacy',
      items: items,
    );
  }

  rust_api.WorkspaceListChildrenResponse _fallbackWorkspaceChildren({
    String? parentNodeId,
  }) {
    if (parentNodeId == null) {
      final rootItems = <rust_api.WorkspaceNodeItem>[
        const rust_api.WorkspaceNodeItem(
          nodeId: _uncategorizedFolderNodeId,
          kind: 'folder',
          parentNodeId: null,
          atomId: null,
          displayName: _uncategorizedFolderDisplayName,
          sortOrder: -1,
        ),
        const rust_api.WorkspaceNodeItem(
          nodeId: 'projects',
          kind: 'folder',
          parentNodeId: null,
          atomId: null,
          displayName: 'Projects',
          sortOrder: 0,
        ),
        const rust_api.WorkspaceNodeItem(
          nodeId: 'notes',
          kind: 'folder',
          parentNodeId: null,
          atomId: null,
          displayName: 'Notes',
          sortOrder: 1,
        ),
        const rust_api.WorkspaceNodeItem(
          nodeId: 'personal',
          kind: 'folder',
          parentNodeId: null,
          atomId: null,
          displayName: 'Personal',
          sortOrder: 2,
        ),
      ];
      return rust_api.WorkspaceListChildrenResponse(
        ok: true,
        errorCode: null,
        message: 'fallback',
        items: rootItems,
      );
    }

    if (parentNodeId == 'notes') {
      final noteItems = <rust_api.WorkspaceNodeItem>[];
      var order = 0;
      for (final item in _items) {
        noteItems.add(
          rust_api.WorkspaceNodeItem(
            nodeId: 'note_ref_notes_${item.atomId}',
            kind: 'note_ref',
            parentNodeId: 'notes',
            atomId: item.atomId,
            displayName: _titleFromContent(item.content),
            sortOrder: order,
          ),
        );
        order += 1;
      }
      return rust_api.WorkspaceListChildrenResponse(
        ok: true,
        errorCode: null,
        message: 'fallback',
        items: noteItems,
      );
    }

    return const rust_api.WorkspaceListChildrenResponse(
      ok: true,
      errorCode: null,
      message: 'fallback',
      items: <rust_api.WorkspaceNodeItem>[],
    );
  }

  bool _shouldUseWorkspaceTreeSyntheticFallback(Object error) {
    if (error is MissingPluginException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    final mentionsRustBridge =
        text.contains('rustlib') ||
        text.contains('rust bridge') ||
        text.contains('no implementation found for method');
    final looksLikeInitGap =
        text.contains('not initialized') ||
        text.contains('initialize') ||
        text.contains('init');
    return mentionsRustBridge && looksLikeInitGap;
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

class _ProjectedUncategorizedRow {
  const _ProjectedUncategorizedRow({
    required this.nodeId,
    required this.atomId,
    required this.displayName,
    required this.updatedAt,
  });

  final String nodeId;
  final String atomId;
  final String displayName;
  final int updatedAt;
}

int _compareProjectedUncategorizedRow(
  _ProjectedUncategorizedRow left,
  _ProjectedUncategorizedRow right,
) {
  final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
  if (byUpdatedAt != 0) {
    return byUpdatedAt;
  }
  final byAtomId = left.atomId.compareTo(right.atomId);
  if (byAtomId != 0) {
    return byAtomId;
  }
  return left.nodeId.compareTo(right.nodeId);
}

enum _WorkspaceParentValidation { root, value, invalid }

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

Future<rust_api.WorkspaceActionResponse> _defaultWorkspaceDeleteFolderInvoker({
  required String nodeId,
  required String mode,
}) {
  return rust_api.workspaceDeleteFolder(nodeId: nodeId, mode: mode);
}

Future<rust_api.WorkspaceNodeResponse> _defaultWorkspaceCreateFolderInvoker({
  String? parentNodeId,
  required String name,
}) {
  return rust_api.workspaceCreateFolder(parentNodeId: parentNodeId, name: name);
}

Future<rust_api.WorkspaceNodeResponse> _defaultWorkspaceCreateNoteRefInvoker({
  String? parentNodeId,
  required String atomId,
  String? displayName,
}) {
  return rust_api.workspaceCreateNoteRef(
    parentNodeId: parentNodeId,
    atomId: atomId,
    displayName: displayName,
  );
}

Future<rust_api.WorkspaceActionResponse> _defaultWorkspaceRenameNodeInvoker({
  required String nodeId,
  required String newName,
}) {
  return rust_api.workspaceRenameNode(nodeId: nodeId, newName: newName);
}

Future<rust_api.WorkspaceActionResponse> _defaultWorkspaceMoveNodeInvoker({
  required String nodeId,
  String? newParentId,
  int? targetOrder,
}) {
  return rust_api.workspaceMoveNode(
    nodeId: nodeId,
    newParentId: newParentId,
    targetOrder: targetOrder,
  );
}

Future<rust_api.WorkspaceListChildrenResponse>
_defaultWorkspaceListChildrenInvoker({String? parentNodeId}) {
  return rust_api.workspaceListChildren(parentNodeId: parentNodeId);
}

Future<void> _defaultPrepare() async {
  await RustBridge.ensureEntryDbPathConfigured();
}
