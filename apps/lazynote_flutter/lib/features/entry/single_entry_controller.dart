import 'package:flutter/widgets.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';

/// Stateful controller for the Single Entry panel.
///
/// Responsibilities:
/// - Route every input change through parser/router.
/// - Keep detail output hidden until Enter/send is explicitly triggered.
/// - Preserve user input on parse/execution error states.
class SingleEntryController extends ChangeNotifier {
  SingleEntryController({CommandRouter? router})
    : _router = router ?? const CommandRouter();

  final CommandRouter _router;
  final TextEditingController textController = TextEditingController();
  final FocusNode inputFocusNode = FocusNode();

  EntryState _state = const EntryState.idle();
  bool _isDetailVisible = false;

  EntryState get state => _state;
  bool get isDetailVisible => _isDetailVisible;
  bool get hasInput => textController.text.trim().isNotEmpty;
  String? get visibleDetail => _isDetailVisible ? _state.detailPayload : null;

  /// Handles realtime routing for each input change.
  void handleInputChanged(String value) {
    final intent = _router.route(value);
    _isDetailVisible = false;
    _state = switch (intent) {
      NoopIntent() => const EntryState.idle(),
      SearchIntent() => EntryState.idle().toSuccess(
        rawInput: value,
        intent: intent,
        message: 'Search preview ready. Press Enter or Send for details.',
        detailPayload: _detailForIntent(intent),
      ),
      CommandIntent() => EntryState.idle().toSuccess(
        rawInput: value,
        intent: intent,
        message: 'Command preview ready. Press Enter or Send for details.',
        detailPayload: _detailForIntent(intent),
      ),
      ParseErrorIntent(:final message) => EntryState.idle().toError(
        rawInput: value,
        intent: intent,
        message: message,
      ),
    };
    notifyListeners();
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
      case CommandIntent():
        _state = EntryState.idle().toSuccess(
          rawInput: rawInput,
          intent: intent,
          message: 'Detail opened.',
          detailPayload: _detailForIntent(intent),
        );
        _isDetailVisible = true;
    }

    notifyListeners();
  }

  void requestFocus() {
    inputFocusNode.requestFocus();
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
    textController.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }
}
