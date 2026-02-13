import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/rust_bridge.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';

typedef EntrySearchInvoker =
    Future<rust_api.EntrySearchResponse> Function({
      required String text,
      required int limit,
    });

/// Stateful controller for the Single Entry panel.
///
/// Responsibilities:
/// - Route every input change through parser/router.
/// - Keep detail output hidden until Enter/send is explicitly triggered.
/// - Preserve user input on parse/execution error states.
class SingleEntryController extends ChangeNotifier {
  SingleEntryController({
    CommandRouter? router,
    EntrySearchInvoker? searchInvoker,
    Duration searchDebounce = const Duration(milliseconds: 150),
  }) : _router = router ?? const CommandRouter(),
       _searchInvoker = searchInvoker ?? _defaultEntrySearch,
       _searchDebounce = searchDebounce;

  final CommandRouter _router;
  final EntrySearchInvoker _searchInvoker;
  final Duration _searchDebounce;
  final TextEditingController textController = TextEditingController();
  final FocusNode inputFocusNode = FocusNode();

  EntryState _state = const EntryState.idle();
  bool _isDetailVisible = false;
  List<rust_api.EntrySearchItem> _searchItems = const [];
  int? _searchAppliedLimit;
  int _searchRequestSequence = 0;
  Timer? _searchDebounceTimer;

  EntryState get state => _state;
  bool get isDetailVisible => _isDetailVisible;
  bool get hasInput => textController.text.trim().isNotEmpty;
  String? get visibleDetail => _isDetailVisible ? _state.detailPayload : null;
  List<rust_api.EntrySearchItem> get searchItems =>
      List.unmodifiable(_searchItems);
  int? get searchAppliedLimit => _searchAppliedLimit;
  bool get isSearchIntentActive => _state.intent is SearchIntent;
  bool get isSearchLoading =>
      _state.intent is SearchIntent && _state.phase == EntryPhase.loading;
  bool get hasSearchError =>
      _state.intent is SearchIntent && _state.phase == EntryPhase.error;
  String? get searchErrorMessage =>
      hasSearchError ? _state.statusMessage?.text : null;

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
        final detail =
            _state.intent is CommandIntent && _state.rawInput == rawInput
            ? _state.detailPayload
            : _detailForIntent(intent);
        _state = EntryState.idle().toSuccess(
          rawInput: rawInput,
          intent: intent,
          message: 'Detail opened.',
          detailPayload: detail,
        );
        _isDetailVisible = true;
    }

    notifyListeners();
  }

  void requestFocus() {
    inputFocusNode.requestFocus();
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
