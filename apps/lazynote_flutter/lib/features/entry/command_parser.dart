import 'package:flutter/foundation.dart';

/// Parses single-entry command text into strongly-typed command intents.
///
/// v0.2 baseline:
/// - command parser chain with priority and deterministic short-circuit
/// - default first-party command parsers are registered via parser chain
@immutable
class CommandParser {
  const CommandParser({
    this.chain = EntryParserChain.firstParty,
    this.timeoutBudget = const Duration(milliseconds: 8),
  });

  /// Parser chain used when input enters command mode (`>` prefix).
  final EntryParserChain chain;

  /// Total parse budget across chain traversal.
  final Duration timeoutBudget;

  /// Parses one raw command string.
  ///
  /// Returns [CommandParseSuccess] when command is valid.
  /// Returns [CommandParseFailure] with stable code/message on validation error.
  CommandParseResult parse(String rawInput) {
    final trimmed = rawInput.trim();
    if (!trimmed.startsWith('>')) {
      return const CommandParseFailure(
        code: 'missing_prefix',
        message: 'Command must start with ">".',
      );
    }

    final body = trimmed.substring(1).trim();
    if (body.isEmpty) {
      return const CommandParseFailure(
        code: 'empty_command',
        message: 'Command cannot be empty.',
      );
    }

    return chain.parse(body: body, timeoutBudget: timeoutBudget);
  }
}

/// One parser registration in chain.
@immutable
class EntryParserDefinition {
  const EntryParserDefinition({
    required this.parserId,
    required this.priority,
    required this.tryParse,
  });

  /// Stable namespaced parser id.
  final String parserId;

  /// Higher value means earlier execution in chain.
  final int priority;

  /// Returns parsed result when parser claims this payload, otherwise null.
  final CommandParseResult? Function(String body) tryParse;
}

/// Parser chain declaration and deterministic parse execution.
@immutable
class EntryParserChain {
  const EntryParserChain._(this._orderedParsers);

  /// Baseline first-party parser chain.
  static const EntryParserChain firstParty =
      EntryParserChain._(<EntryParserDefinition>[
        EntryParserDefinition(
          parserId: 'builtin.entry.schedule',
          priority: 300,
          tryParse: _tryParseScheduleCommand,
        ),
        EntryParserDefinition(
          parserId: 'builtin.entry.new_note',
          priority: 200,
          tryParse: _tryParseNewNoteCommand,
        ),
        EntryParserDefinition(
          parserId: 'builtin.entry.task',
          priority: 100,
          tryParse: _tryParseTaskCommand,
        ),
      ]);

  /// Builds custom parser chain and validates duplicate parser ids.
  factory EntryParserChain({required List<EntryParserDefinition> parsers}) {
    final seen = <String>{};
    final normalized = <EntryParserDefinition>[];
    for (final parser in parsers) {
      final parserId = parser.parserId.trim();
      if (parserId.isEmpty) {
        throw const ParserChainConflictError(
          code: 'invalid_parser_id',
          message: 'Parser id must not be empty.',
        );
      }
      if (!seen.add(parserId)) {
        throw ParserChainConflictError(
          code: 'duplicate_parser_id',
          message: 'Duplicate parser id: $parserId',
        );
      }
      normalized.add(
        EntryParserDefinition(
          parserId: parserId,
          priority: parser.priority,
          tryParse: parser.tryParse,
        ),
      );
    }

    normalized.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) {
        return byPriority;
      }
      return a.parserId.compareTo(b.parserId);
    });

    return EntryParserChain._(List.unmodifiable(normalized));
  }

  final List<EntryParserDefinition> _orderedParsers;

  /// Deterministic parser-chain evaluation with timeout budget.
  CommandParseResult parse({
    required String body,
    required Duration timeoutBudget,
  }) {
    final stopwatch = Stopwatch()..start();
    for (final parser in _orderedParsers) {
      if (stopwatch.elapsed > timeoutBudget) {
        return const CommandParseFailure(
          code: 'parser_timeout',
          message: 'Command parsing timed out.',
        );
      }

      final result = parser.tryParse(body);
      if (result != null) {
        return result;
      }

      if (stopwatch.elapsed > timeoutBudget) {
        return const CommandParseFailure(
          code: 'parser_timeout',
          message: 'Command parsing timed out.',
        );
      }
    }

    return const CommandParseFailure(
      code: 'unknown_command',
      message: 'Unknown command. Supported: new note, task, schedule.',
    );
  }
}

/// Parser-chain registration/validation error.
class ParserChainConflictError implements Exception {
  const ParserChainConflictError({required this.code, required this.message});

  final String code;
  final String message;
}

final RegExp _scheduleRangePattern = RegExp(
  r'^(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})-(\d{2}:\d{2})\s+(.+)$',
);
final RegExp _schedulePointPattern = RegExp(
  r'^(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})\s+(.+)$',
);

CommandParseResult? _tryParseNewNoteCommand(String body) {
  if (!_matchesKeyword(body, 'new note')) {
    return null;
  }
  final content = body.substring('new note'.length).trim();
  if (content.isEmpty) {
    return const CommandParseFailure(
      code: 'note_content_empty',
      message: 'Note content cannot be empty.',
    );
  }
  return CommandParseSuccess(command: NewNoteCommand(content: content));
}

CommandParseResult? _tryParseTaskCommand(String body) {
  if (!_matchesKeyword(body, 'task')) {
    return null;
  }
  final content = body.substring('task'.length).trim();
  if (content.isEmpty) {
    return const CommandParseFailure(
      code: 'task_content_empty',
      message: 'Task content cannot be empty.',
    );
  }
  return CommandParseSuccess(command: CreateTaskCommand(content: content));
}

CommandParseResult? _tryParseScheduleCommand(String body) {
  if (!_matchesKeyword(body, 'schedule')) {
    return null;
  }

  final payload = body.substring('schedule'.length).trim();
  if (payload.isEmpty) {
    return const CommandParseFailure(
      code: 'schedule_format_invalid',
      message:
          'Schedule format must be MM/DD/YYYY HH:mm <title> or MM/DD/YYYY HH:mm-HH:mm <title>.',
    );
  }

  final rangeMatch = _scheduleRangePattern.firstMatch(payload);
  if (rangeMatch != null) {
    return _parseScheduleRange(rangeMatch);
  }

  final pointMatch = _schedulePointPattern.firstMatch(payload);
  if (pointMatch != null) {
    return _parseSchedulePoint(pointMatch);
  }

  return const CommandParseFailure(
    code: 'schedule_format_invalid',
    message:
        'Schedule format must be MM/DD/YYYY HH:mm <title> or MM/DD/YYYY HH:mm-HH:mm <title>.',
  );
}

bool _matchesKeyword(String body, String keyword) {
  final lowerBody = body.toLowerCase();
  return lowerBody == keyword || lowerBody.startsWith('$keyword ');
}

CommandParseResult _parseSchedulePoint(RegExpMatch match) {
  final date = match.group(1)!;
  final startTime = match.group(2)!;
  final title = match.group(3)!.trim();
  if (title.isEmpty) {
    return const CommandParseFailure(
      code: 'schedule_title_empty',
      message: 'Schedule title cannot be empty.',
    );
  }

  final start = _parseDateTime(date, startTime);
  if (start == null) {
    return const CommandParseFailure(
      code: 'schedule_datetime_invalid',
      message: 'Schedule date/time is invalid.',
    );
  }

  return CommandParseSuccess(
    command: ScheduleCommand(title: title, start: start, end: null),
  );
}

CommandParseResult _parseScheduleRange(RegExpMatch match) {
  final date = match.group(1)!;
  final startTime = match.group(2)!;
  final endTime = match.group(3)!;
  final title = match.group(4)!.trim();
  if (title.isEmpty) {
    return const CommandParseFailure(
      code: 'schedule_title_empty',
      message: 'Schedule title cannot be empty.',
    );
  }

  final start = _parseDateTime(date, startTime);
  final end = _parseDateTime(date, endTime);
  if (start == null || end == null) {
    return const CommandParseFailure(
      code: 'schedule_datetime_invalid',
      message: 'Schedule date/time is invalid.',
    );
  }
  if (!end.isAfter(start)) {
    return const CommandParseFailure(
      code: 'schedule_range_invalid',
      message: 'Schedule end time must be after start time.',
    );
  }

  return CommandParseSuccess(
    command: ScheduleCommand(title: title, start: start, end: end),
  );
}

DateTime? _parseDateTime(String date, String time) {
  final dateParts = date.split('/');
  final timeParts = time.split(':');
  if (dateParts.length != 3 || timeParts.length != 2) {
    return null;
  }

  final month = int.tryParse(dateParts[0]);
  final day = int.tryParse(dateParts[1]);
  final year = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (month == null ||
      day == null ||
      year == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  final value = DateTime(year, month, day, hour, minute);
  if (value.year != year ||
      value.month != month ||
      value.day != day ||
      value.hour != hour ||
      value.minute != minute) {
    return null;
  }
  return value;
}

/// Parser output envelope.
@immutable
sealed class CommandParseResult {
  const CommandParseResult();
}

/// Successful parse.
@immutable
final class CommandParseSuccess extends CommandParseResult {
  const CommandParseSuccess({required this.command});

  /// Parsed command payload consumed by command execution layer.
  final EntryCommand command;
}

/// Failed parse with stable code and human-readable message.
@immutable
final class CommandParseFailure extends CommandParseResult {
  const CommandParseFailure({required this.code, required this.message});

  /// Stable parser error code for UI state machine and tests.
  final String code;

  /// Human-readable parser error for inline status rendering.
  final String message;
}

/// Base type for parsed command payloads.
@immutable
sealed class EntryCommand {
  const EntryCommand();

  /// Stable command id used by registry execution.
  String get commandId;
}

/// Command payload for note creation.
@immutable
final class NewNoteCommand extends EntryCommand {
  const NewNoteCommand({required this.content});

  static const String id = 'builtin.entry.new_note';

  /// Note content that will be persisted by command execution.
  final String content;

  @override
  String get commandId => id;
}

/// Command payload for task creation.
@immutable
final class CreateTaskCommand extends EntryCommand {
  const CreateTaskCommand({required this.content});

  static const String id = 'builtin.entry.create_task';

  /// Task content that will be persisted with default `todo` status.
  final String content;

  @override
  String get commandId => id;
}

/// Command payload for schedule creation.
@immutable
final class ScheduleCommand extends EntryCommand {
  const ScheduleCommand({
    required this.title,
    required this.start,
    required this.end,
  });

  static const String id = 'builtin.entry.schedule';

  /// Event title/content stored on the created event atom.
  final String title;

  /// Start time parsed from `MM/DD/YYYY HH:mm` input (local time).
  final DateTime start;

  /// Optional end time for range schedules; `null` means point event.
  final DateTime? end;

  @override
  String get commandId => id;
}
