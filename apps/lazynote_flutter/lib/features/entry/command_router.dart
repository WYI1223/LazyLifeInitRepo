import 'package:flutter/foundation.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';

const int defaultSearchLimit = 10;
const int maxSearchLimit = 10;

/// Routes raw single-entry text to search or command intents.
@immutable
class CommandRouter {
  const CommandRouter({this.parser = const CommandParser()});

  final CommandParser parser;

  /// Returns intent by applying single-entry route rules.
  ///
  /// Rules:
  /// - empty -> [NoopIntent]
  /// - starts with `>` -> parser-driven command intent
  /// - otherwise -> [SearchIntent]
  EntryIntent route(
    String rawInput, {
    int requestedSearchLimit = defaultSearchLimit,
  }) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const NoopIntent();
    }
    if (!trimmed.startsWith('>')) {
      return SearchIntent(
        text: trimmed,
        limit: _normalizeSearchLimit(requestedSearchLimit),
      );
    }

    final parsed = parser.parse(trimmed);
    return switch (parsed) {
      CommandParseSuccess(:final command) => CommandIntent(command: command),
      CommandParseFailure(:final code, :final message) => ParseErrorIntent(
        code: code,
        message: message,
      ),
    };
  }

  int _normalizeSearchLimit(int requestedLimit) {
    if (requestedLimit <= 0) {
      return defaultSearchLimit;
    }
    if (requestedLimit > maxSearchLimit) {
      return maxSearchLimit;
    }
    return requestedLimit;
  }
}

/// Base type for single-entry route intents.
@immutable
sealed class EntryIntent {
  const EntryIntent();
}

/// No-op intent when input is empty.
@immutable
final class NoopIntent extends EntryIntent {
  const NoopIntent();
}

/// Search intent for non-command text.
@immutable
final class SearchIntent extends EntryIntent {
  const SearchIntent({required this.text, required this.limit});

  final String text;
  final int limit;
}

/// Command intent produced by successful command parsing.
@immutable
final class CommandIntent extends EntryIntent {
  const CommandIntent({required this.command});

  final EntryCommand command;
}

/// Parse error intent produced by command parse failure.
@immutable
final class ParseErrorIntent extends EntryIntent {
  const ParseErrorIntent({required this.code, required this.message});

  final String code;
  final String message;
}
