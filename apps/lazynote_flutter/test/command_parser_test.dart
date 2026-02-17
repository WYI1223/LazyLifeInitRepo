import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';

void main() {
  const parser = CommandParser();

  test('parses new note command', () {
    final result = parser.parse('> new note ship the parser');
    expect(result, isA<CommandParseSuccess>());

    final success = result as CommandParseSuccess;
    expect(success.command, isA<NewNoteCommand>());
    final command = success.command as NewNoteCommand;
    expect(command.content, 'ship the parser');
  });

  test('parses task command', () {
    final result = parser.parse('> task buy milk');
    expect(result, isA<CommandParseSuccess>());

    final success = result as CommandParseSuccess;
    expect(success.command, isA<CreateTaskCommand>());
    final command = success.command as CreateTaskCommand;
    expect(command.content, 'buy milk');
  });

  test('parses schedule point command', () {
    final result = parser.parse('> schedule 03/15/2026 09:30 planning');
    expect(result, isA<CommandParseSuccess>());

    final success = result as CommandParseSuccess;
    expect(success.command, isA<ScheduleCommand>());
    final command = success.command as ScheduleCommand;
    expect(command.title, 'planning');
    expect(command.start, DateTime(2026, 3, 15, 9, 30));
    expect(command.end, isNull);
  });

  test('parses schedule range command', () {
    final result = parser.parse(
      '> schedule 03/15/2026 09:30-10:45 weekly sync',
    );
    expect(result, isA<CommandParseSuccess>());

    final success = result as CommandParseSuccess;
    final command = success.command as ScheduleCommand;
    expect(command.title, 'weekly sync');
    expect(command.start, DateTime(2026, 3, 15, 9, 30));
    expect(command.end, DateTime(2026, 3, 15, 10, 45));
  });

  test('rejects unknown command', () {
    final result = parser.parse('> email team');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'unknown_command');
  });

  test('rejects note with empty content', () {
    final result = parser.parse('> new note');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'note_content_empty');
  });

  test('rejects malformed schedule format', () {
    final result = parser.parse('> schedule tomorrow 10am standup');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'schedule_format_invalid');
  });

  test('rejects schedule range when end is before start', () {
    final result = parser.parse('> schedule 03/15/2026 10:45-09:30 bad range');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'schedule_range_invalid');
  });

  test('rejects schedule with invalid month', () {
    final result = parser.parse('> schedule 13/01/2026 09:30 invalid month');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'schedule_datetime_invalid');
  });

  test('rejects schedule with invalid calendar day', () {
    final result = parser.parse('> schedule 02/30/2026 09:30 invalid day');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'schedule_datetime_invalid');
  });

  test('rejects schedule range crossing midnight in same-day contract', () {
    final result = parser.parse('> schedule 03/15/2026 23:00-01:00 overnight');
    expect(result, isA<CommandParseFailure>());

    final failure = result as CommandParseFailure;
    expect(failure.code, 'schedule_range_invalid');
  });
}
