import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_registry.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';

/// Async search executor for default (non-command) single-entry input.
typedef EntrySearchInvoker =
    Future<rust_api.EntrySearchResponse> Function({
      required String text,
      required int limit,
    });

/// Async command executor for `> new note`.
typedef EntryCreateNoteInvoker =
    Future<rust_api.EntryActionResponse> Function({required String content});

/// Async command executor for `> task`.
typedef EntryCreateTaskInvoker =
    Future<rust_api.EntryActionResponse> Function({required String content});

/// Async command executor for `> schedule` (point/range).
typedef EntryScheduleInvoker =
    Future<rust_api.EntryActionResponse> Function({
      required String title,
      required int startEpochMs,
      int? endEpochMs,
    });

/// Pre-search hook used to guarantee prerequisites (for example DB path setup).
typedef EntrySearchPrepare = Future<void> Function();

/// Pre-command hook used to guarantee prerequisites before command execution.
typedef EntryCommandPrepare = Future<void> Function();

/// Stateful controller for the Single Entry panel.
///
/// Responsibilities:
/// - Route every input change through parser/router.
/// - Keep detail output hidden until Enter/send is explicitly triggered.
/// - Preserve user input on parse/execution error states.
class SingleEntryController extends ChangeNotifier {
  /// Creates a controller for Single Entry search + command flows.
  ///
  /// Contract:
  /// - `onChanged` path stays realtime and non-destructive.
  /// - Enter/send path performs explicit detail open or command execution.
  /// - Injected invokers/hooks are intended for tests and diagnostics.
  SingleEntryController({
    CommandRouter? router,
    EntryCommandRegistry? commandRegistry,
    EntrySearchInvoker? searchInvoker,
    EntryCreateNoteInvoker? createNoteInvoker,
    EntryCreateTaskInvoker? createTaskInvoker,
    EntryScheduleInvoker? scheduleInvoker,
    EntrySearchPrepare? prepareSearch,
    EntryCommandPrepare? prepareCommand,
    Duration searchDebounce = const Duration(milliseconds: 150),
  }) : _router = router ?? const CommandRouter(),
       _searchInvoker = searchInvoker ?? _defaultEntrySearch,
       _prepareSearch =
           // Why: when tests inject a custom search invoker we should not
           // implicitly touch real bridge/bootstrap side effects unless
           // a test explicitly asks for that behavior.
           prepareSearch ??
           (searchInvoker != null ? _noopPrepareSearch : _defaultPrepareSearch),
       _prepareCommand =
           // Why: command tests can inject fake command invokers without
           // coupling to bridge/bootstrap prerequisites.
           prepareCommand ??
           (createNoteInvoker != null ||
                   createTaskInvoker != null ||
                   scheduleInvoker != null
               ? _noopPrepareCommand
               : _defaultPrepareCommand),
       _searchDebounce = searchDebounce,
       _commandRegistry =
           commandRegistry ??
           EntryCommandRegistry.firstParty(
             createNoteInvoker: createNoteInvoker ?? _defaultEntryCreateNote,
             createTaskInvoker: createTaskInvoker ?? _defaultEntryCreateTask,
             scheduleInvoker: scheduleInvoker ?? _defaultEntrySchedule,
           ) {
    inputFocusNode.addListener(_handleFocusChanged);
  }

  final CommandRouter _router;
  final EntrySearchInvoker _searchInvoker;
  final EntryCommandRegistry _commandRegistry;
  final EntrySearchPrepare _prepareSearch;
  final EntryCommandPrepare _prepareCommand;
  final Duration _searchDebounce;

  /// Input controller shared with Single Entry panel text field.
  final TextEditingController textController = TextEditingController();

  /// Focus node used by Workbench "open/focus" actions.
  final FocusNode inputFocusNode = FocusNode();

  EntryState _state = const EntryState.idle();
  bool _isDetailVisible = false;
  List<rust_api.EntrySearchItem> _searchItems = const [];
  int? _searchAppliedLimit;
  int _searchRequestSequence = 0;
  int _commandRequestSequence = 0;
  Timer? _searchDebounceTimer;

  /// Current immutable state snapshot rendered by the panel.
  EntryState get state => _state;

  /// Whether detail payload card is currently visible.
  bool get isDetailVisible => _isDetailVisible;

  /// Whether trimmed input is non-empty (send icon highlight contract).
  bool get hasInput => textController.text.trim().isNotEmpty;

  /// Whether entry input field is currently focused.
  bool get isInputFocused => inputFocusNode.hasFocus;

  /// Unified panel expansion policy for PR-0010A.
  ///
  /// Contract:
  /// - Expand on focus.
  /// - Expand while non-empty input is present.
  /// - Collapse only when unfocused and input is empty.
  bool get shouldExpandUnifiedPanel => isInputFocused || hasInput;

  /// Visible detail payload; `null` when detail panel is hidden.
  String? get visibleDetail => _isDetailVisible ? _state.detailPayload : null;

  /// Current realtime search items.
  List<rust_api.EntrySearchItem> get searchItems =>
      List.unmodifiable(_searchItems);

  /// Effective search limit returned by backend for latest search response.
  int? get searchAppliedLimit => _searchAppliedLimit;

  /// Whether current intent is search-mode.
  bool get isSearchIntentActive => _state.intent is SearchIntent;

  /// Search-mode loading state flag.
  bool get isSearchLoading =>
      _state.intent is SearchIntent && _state.phase == EntryPhase.loading;

  /// Search-mode error state flag.
  bool get hasSearchError =>
      _state.intent is SearchIntent && _state.phase == EntryPhase.error;

  /// Search-mode error text, when present.
  String? get searchErrorMessage =>
      hasSearchError ? _state.statusMessage?.text : null;

  /// Whether a command submission is currently in-flight.
  bool get isCommandSubmitting =>
      _state.intent is CommandIntent && _state.phase == EntryPhase.loading;

  /// Handles realtime routing for each input change.
  void handleInputChanged(String value) {
    final intent = _router.route(value);
    _isDetailVisible = false;
    switch (intent) {
      case NoopIntent():
        _cancelPendingSearch();
        _searchItems = const [];
        _searchAppliedLimit = null;
        _state = const EntryState.idle();
        notifyListeners();
      case SearchIntent():
        _startRealtimeSearch(rawInput: value, intent: intent);
      case CommandIntent():
        _cancelPendingSearch();
        _searchItems = const [];
        _searchAppliedLimit = null;
        _state = EntryState.idle().toSuccess(
          rawInput: value,
          intent: intent,
          message: 'Command preview ready. Press Enter or Send for details.',
          detailPayload: _detailForIntent(intent),
        );
        notifyListeners();
      case ParseErrorIntent(:final message):
        _cancelPendingSearch();
        _searchItems = const [];
        _searchAppliedLimit = null;
        _state = EntryState.idle().toError(
          rawInput: value,
          intent: intent,
          message: message,
        );
        notifyListeners();
    }
  }

  /// Handles explicit "open detail" action (Enter/send button).
  void handleDetailAction() {
    if (isCommandSubmitting) {
      return;
    }

    final rawInput = textController.text;
    final intent = _router.route(rawInput);
    _isDetailVisible = false;

    switch (intent) {
      case NoopIntent():
        _state = EntryState.idle().toError(
          rawInput: rawInput,
          intent: intent,
          message: 'Please type something first.',
        );
      case ParseErrorIntent(:final message):
        _state = EntryState.idle().toError(
          rawInput: rawInput,
          intent: intent,
          message: message,
        );
      case SearchIntent():
        final canOpenSearchDetail =
            _state.intent is SearchIntent &&
            _state.rawInput == rawInput &&
            _state.phase != EntryPhase.loading &&
            _state.detailPayload != null;
        if (!canOpenSearchDetail) {
          _state = EntryState.idle().toError(
            rawInput: rawInput,
            intent: intent,
            message: 'Search detail is not ready yet. Keep typing or wait.',
          );
          break;
        }
        _state = EntryState.idle().toSuccess(
          rawInput: rawInput,
          intent: intent,
          message: 'Detail opened.',
          detailPayload: _state.detailPayload,
        );
        _isDetailVisible = true;
      case CommandIntent():
        final requestId = ++_commandRequestSequence;
        _state = EntryState.idle().toLoading(
          rawInput: rawInput,
          intent: intent,
          message: 'Executing command...',
        );
        notifyListeners();
        unawaited(
          _runCommandRequest(
            requestId: requestId,
            rawInput: rawInput,
            intent: intent,
          ),
        );
        return;
    }

    notifyListeners();
  }

  /// Requests focus for entry input after panel is shown.
  void requestFocus() {
    inputFocusNode.requestFocus();
  }

  /// Opens detail panel for a selected realtime search item.
  void openSearchResultDetail(rust_api.EntrySearchItem item) {
    final intent = _state.intent;
    if (intent is! SearchIntent) {
      return;
    }
    _state = EntryState.idle().toSuccess(
      rawInput: _state.rawInput,
      intent: intent,
      message: 'Detail opened from selected result.',
      detailPayload: _searchItemDetailPayload(intent: intent, item: item),
    );
    _isDetailVisible = true;
    notifyListeners();
  }

  /// Handles escape-key quick reset behavior for v0.1 entry shell.
  ///
  /// Contract:
  /// - If input is non-empty, clear input and return to idle state.
  /// - If detail is visible, close detail panel.
  /// - Always release input focus so unified panel can collapse.
  void handleEscapePressed() {
    final hadInput = hasInput;
    final hadDetail = _isDetailVisible;

    if (hadInput) {
      textController.clear();
      handleInputChanged('');
    } else if (hadDetail) {
      _isDetailVisible = false;
      notifyListeners();
    }

    if (inputFocusNode.hasFocus) {
      inputFocusNode.unfocus();
    }
  }

  void _handleFocusChanged() {
    // Why: focus transitions should trigger panel expand/collapse animation
    // even when no text-change event occurs.
    notifyListeners();
  }

  void _startRealtimeSearch({
    required String rawInput,
    required SearchIntent intent,
  }) {
    _searchDebounceTimer?.cancel();
    final requestId = ++_searchRequestSequence;
    _searchItems = const [];
    _searchAppliedLimit = null;

    _state = EntryState.idle().toLoading(
      rawInput: rawInput,
      intent: intent,
      message: 'Searching...',
    );
    notifyListeners();

    _searchDebounceTimer = Timer(_searchDebounce, () {
      unawaited(
        _runSearchRequest(
          requestId: requestId,
          rawInput: rawInput,
          intent: intent,
        ),
      );
    });
  }

  Future<void> _runSearchRequest({
    required int requestId,
    required String rawInput,
    required SearchIntent intent,
  }) async {
    try {
      await _prepareSearch();
      // Why: if input changed while prerequisites were running, this request
      // is stale and must not overwrite newer state.
      if (requestId != _searchRequestSequence) {
        return;
      }

      final response = await _searchInvoker(
        text: intent.text,
        limit: intent.limit,
      );
      if (requestId != _searchRequestSequence) {
        return;
      }

      if (!response.ok) {
        final errorText = response.errorCode == null
            ? response.message
            : '[${response.errorCode}] ${response.message}';
        _searchItems = const [];
        _searchAppliedLimit = null;
        _state = EntryState.idle().toError(
          rawInput: rawInput,
          intent: intent,
          message: errorText,
        );
        notifyListeners();
        return;
      }

      final itemCount = response.items.length;
      final message = itemCount == 0
          ? 'No results.'
          : 'Found $itemCount result(s).';
      _searchItems = response.items;
      _searchAppliedLimit = response.appliedLimit;
      _state = EntryState.idle().toSuccess(
        rawInput: rawInput,
        intent: intent,
        message: message,
        detailPayload: _searchDetailPayload(intent: intent, response: response),
      );
      notifyListeners();
    } catch (error) {
      if (requestId != _searchRequestSequence) {
        return;
      }
      _searchItems = const [];
      _searchAppliedLimit = null;
      _state = EntryState.idle().toError(
        rawInput: rawInput,
        intent: intent,
        message: 'Search failed unexpectedly: $error',
      );
      notifyListeners();
    }
  }

  void _cancelPendingSearch() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    _searchRequestSequence += 1;
  }

  Future<void> _runCommandRequest({
    required int requestId,
    required String rawInput,
    required CommandIntent intent,
  }) async {
    try {
      await _prepareCommand();
      if (requestId != _commandRequestSequence) {
        return;
      }

      final response = await _executeCommand(intent.command);
      if (requestId != _commandRequestSequence) {
        return;
      }

      final detail = _commandResultDetail(
        rawInput: rawInput,
        command: intent.command,
        response: response,
      );
      if (response.ok) {
        _state = EntryState.idle().toSuccess(
          rawInput: rawInput,
          intent: intent,
          message: response.message,
          detailPayload: detail,
        );
      } else {
        _state = EntryState.idle().toError(
          rawInput: rawInput,
          intent: intent,
          message: response.message,
          detailPayload: detail,
        );
      }
      _isDetailVisible = true;
      notifyListeners();
    } catch (error) {
      if (requestId != _commandRequestSequence) {
        return;
      }

      final detail = _commandUnexpectedFailureDetail(
        rawInput: rawInput,
        command: intent.command,
        error: error,
      );
      _state = EntryState.idle().toError(
        rawInput: rawInput,
        intent: intent,
        message: 'Command failed unexpectedly: $error',
        detailPayload: detail,
      );
      _isDetailVisible = true;
      notifyListeners();
    }
  }

  Future<rust_api.EntryActionResponse> _executeCommand(EntryCommand command) {
    return _commandRegistry.execute(command);
  }

  String _commandResultDetail({
    required String rawInput,
    required EntryCommand command,
    required rust_api.EntryActionResponse response,
  }) {
    final buffer = StringBuffer()
      ..writeln('mode=command_result')
      ..writeln('raw_input="$rawInput"')
      ..writeln('action=${_actionLabel(command)}')
      ..writeln('ok=${response.ok}')
      ..writeln('message="${_normalizeSingleLine(response.message)}"');
    if (response.atomId case final atomId?) {
      buffer.writeln('atom_id=$atomId');
    }
    return buffer.toString().trimRight();
  }

  String _commandUnexpectedFailureDetail({
    required String rawInput,
    required EntryCommand command,
    required Object error,
  }) {
    return [
      'mode=command_result',
      'raw_input="$rawInput"',
      'action=${_actionLabel(command)}',
      'ok=false',
      'error="${_normalizeSingleLine(error.toString())}"',
    ].join('\n');
  }

  String _actionLabel(EntryCommand command) {
    return _commandRegistry.actionLabelFor(command.commandId);
  }

  String _searchDetailPayload({
    required SearchIntent intent,
    required rust_api.EntrySearchResponse response,
  }) {
    final buffer = StringBuffer()
      ..writeln('mode=search')
      ..writeln('query="${intent.text}"')
      ..writeln('limit=${intent.limit}')
      ..writeln('applied_limit=${response.appliedLimit}')
      ..writeln('items=${response.items.length}');

    for (final item in response.items) {
      buffer.writeln(
        '- [${item.kind}] ${item.atomId}: ${_normalizeSingleLine(item.snippet)}',
      );
    }
    return buffer.toString().trimRight();
  }

  String _searchItemDetailPayload({
    required SearchIntent intent,
    required rust_api.EntrySearchItem item,
  }) {
    return [
      'mode=search_item',
      'query="${intent.text}"',
      'limit=${intent.limit}',
      'kind=${item.kind}',
      'atom_id=${item.atomId}',
      'snippet="${_normalizeSingleLine(item.snippet)}"',
    ].join('\n');
  }

  String _normalizeSingleLine(String value) {
    return value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  String _detailForIntent(EntryIntent intent) {
    return switch (intent) {
      SearchIntent(:final text, :final limit) =>
        'mode=search\nquery="$text"\nlimit=$limit',
      CommandIntent(:final command) => _detailForCommand(command),
      NoopIntent() => 'mode=idle',
      ParseErrorIntent(:final code, :final message) =>
        'mode=parse_error\ncode=$code\nmessage="$message"',
    };
  }

  String _detailForCommand(EntryCommand command) {
    return switch (command) {
      NewNoteCommand(:final content) =>
        'mode=command\naction=new_note\ncontent="$content"',
      CreateTaskCommand(:final content) =>
        'mode=command\naction=create_task\ncontent="$content"\ndefault_status=todo',
      ScheduleCommand(:final title, :final start, :final end) =>
        'mode=command\naction=schedule\ntitle="$title"\nstart=${start.toIso8601String()}\nend=${end?.toIso8601String() ?? 'null'}',
    };
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    inputFocusNode.removeListener(_handleFocusChanged);
    textController.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }
}

Future<rust_api.EntrySearchResponse> _defaultEntrySearch({
  required String text,
  required int limit,
}) async {
  await RustBridge.init();
  return rust_api.entrySearch(text: text, limit: limit);
}

/// Default note command bridge call.
Future<rust_api.EntryActionResponse> _defaultEntryCreateNote({
  required String content,
}) async {
  await RustBridge.init();
  return rust_api.entryCreateNote(content: content);
}

/// Default task command bridge call.
Future<rust_api.EntryActionResponse> _defaultEntryCreateTask({
  required String content,
}) async {
  await RustBridge.init();
  return rust_api.entryCreateTask(content: content);
}

/// Default schedule command bridge call.
Future<rust_api.EntryActionResponse> _defaultEntrySchedule({
  required String title,
  required int startEpochMs,
  int? endEpochMs,
}) async {
  await RustBridge.init();
  return rust_api.entrySchedule(
    title: title,
    startEpochMs: startEpochMs,
    endEpochMs: endEpochMs,
  );
}

/// Default realtime-search prerequisite: ensure entry DB path configured.
Future<void> _defaultPrepareSearch() async {
  await RustBridge.ensureEntryDbPathConfigured();
}

/// Default command prerequisite: ensure entry DB path configured.
Future<void> _defaultPrepareCommand() async {
  await RustBridge.ensureEntryDbPathConfigured();
}

/// No-op hook for tests that inject custom search invokers.
Future<void> _noopPrepareSearch() async {}

/// No-op hook for tests that inject custom command invokers.
Future<void> _noopPrepareCommand() async {}
