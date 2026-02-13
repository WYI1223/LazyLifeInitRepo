import 'package:flutter/foundation.dart';

/// Parses single-entry command text into strongly-typed command intents.
///
/// v0.1 grammar:
/// - `> new note <content>`
/// - `> task <content>`
/// - `> schedule <MM/DD/YYYY HH:mm> <title>`
/// - `> schedule <MM/DD/YYYY HH:mm-HH:mm> <title>`
@immutable
class CommandParser {
  const CommandParser();

  static final RegExp _scheduleRangePattern = RegExp(
    r'^(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})-(\d{2}:\d{2})\s+(.+)$',
  );
  static final RegExp _schedulePointPattern = RegExp(
    r'^(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})\s+(.+)$',
  );

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

    final lowerBody = body.toLowerCase();
    if (_matchesKeyword(lowerBody, 'new note')) {
      return _parseNewNote(body);
    }
    if (_matchesKeyword(lowerBody, 'task')) {
      return _parseTask(body);
    }
    if (_matchesKeyword(lowerBody, 'schedule')) {
      return _parseSchedule(body);
    }

    return const CommandParseFailure(
      code: 'unknown_command',
      message: 'Unknown command. Supported: new note, task, schedule.',
    );
  }

  bool _matchesKeyword(String body, String keyword) {
    return body == keyword || body.startsWith('$keyword ');
  }

  CommandParseResult _parseNewNote(String body) {
    final content = body.substring('new note'.length).trim();
    if (content.isEmpty) {
      return const CommandParseFailure(
        code: 'note_content_empty',
        message: 'Note content cannot be empty.',
      );
    }
    return CommandParseSuccess(command: NewNoteCommand(content: content));
  }

  CommandParseResult _parseTask(String body) {
    final content = body.substring('task'.length).trim();
    if (content.isEmpty) {
      return const CommandParseFailure(
        code: 'task_content_empty',
        message: 'Task content cannot be empty.',
      );
    }
    return CommandParseSuccess(command: CreateTaskCommand(content: content));
  }

  CommandParseResult _parseSchedule(String body) {
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

  final EntryCommand command;
}

/// Failed parse with stable code and human-readable message.
@immutable
final class CommandParseFailure extends CommandParseResult {
  const CommandParseFailure({required this.code, required this.message});

  final String code;
  final String message;
}

/// Base type for parsed command payloads.
@immutable
sealed class EntryCommand {
  const EntryCommand();
}

/// Command payload for note creation.
@immutable
final class NewNoteCommand extends EntryCommand {
  const NewNoteCommand({required this.content});

  final String content;
}

/// Command payload for task creation.
@immutable
final class CreateTaskCommand extends EntryCommand {
  const CreateTaskCommand({required this.content});

  final String content;
}

/// Command payload for schedule creation.
@immutable
final class ScheduleCommand extends EntryCommand {
  const ScheduleCommand({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
}
