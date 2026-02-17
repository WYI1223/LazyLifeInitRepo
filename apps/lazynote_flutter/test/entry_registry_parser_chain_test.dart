import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_registry.dart';

CommandParseResult? _lowPriorityAliasParser(String body) {
  if (body.toLowerCase().startsWith('alias ')) {
    return const CommandParseSuccess(
      command: NewNoteCommand(content: 'low-priority'),
    );
  }
  return null;
}

CommandParseResult? _highPriorityAliasParser(String body) {
  if (body.toLowerCase().startsWith('alias ')) {
    return const CommandParseSuccess(
      command: NewNoteCommand(content: 'high-priority'),
    );
  }
  return null;
}

CommandParseResult? _slowNoMatchParser(String body) {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsedMilliseconds < 3) {
    // Busy loop for deterministic timeout testing.
  }
  return null;
}

CommandParseResult? _fastTaskParser(String body) {
  if (body.toLowerCase().startsWith('task ')) {
    return const CommandParseSuccess(
      command: CreateTaskCommand(content: 'fast'),
    );
  }
  return null;
}

void main() {
  test(
    'parser chain applies priority and short-circuits deterministically',
    () {
      final chain = EntryParserChain(
        parsers: const <EntryParserDefinition>[
          EntryParserDefinition(
            parserId: 'test.alias.low',
            priority: 10,
            tryParse: _lowPriorityAliasParser,
          ),
          EntryParserDefinition(
            parserId: 'test.alias.high',
            priority: 20,
            tryParse: _highPriorityAliasParser,
          ),
        ],
      );
      final parser = CommandParser(chain: chain);
      final result = parser.parse('> alias demo');
      expect(result, isA<CommandParseSuccess>());

      final command = (result as CommandParseSuccess).command as NewNoteCommand;
      expect(command.content, 'high-priority');
    },
  );

  test('parser chain returns explicit conflict on duplicate parser ids', () {
    expect(
      () => EntryParserChain(
        parsers: const <EntryParserDefinition>[
          EntryParserDefinition(
            parserId: 'test.dup',
            priority: 1,
            tryParse: _lowPriorityAliasParser,
          ),
          EntryParserDefinition(
            parserId: 'test.dup',
            priority: 2,
            tryParse: _highPriorityAliasParser,
          ),
        ],
      ),
      throwsA(
        isA<ParserChainConflictError>().having(
          (error) => error.code,
          'code',
          'duplicate_parser_id',
        ),
      ),
    );
  });

  test('parser chain rejects blank parser id', () {
    expect(
      () => EntryParserChain(
        parsers: const <EntryParserDefinition>[
          EntryParserDefinition(
            parserId: '   ',
            priority: 1,
            tryParse: _lowPriorityAliasParser,
          ),
        ],
      ),
      throwsA(
        isA<ParserChainConflictError>().having(
          (error) => error.code,
          'code',
          'invalid_parser_id',
        ),
      ),
    );
  });

  test('parser chain timeout budget is deterministic', () {
    final chain = EntryParserChain(
      parsers: const <EntryParserDefinition>[
        EntryParserDefinition(
          parserId: 'test.slow',
          priority: 100,
          tryParse: _slowNoMatchParser,
        ),
        EntryParserDefinition(
          parserId: 'test.fast',
          priority: 10,
          tryParse: _fastTaskParser,
        ),
      ],
    );
    final parser = CommandParser(
      chain: chain,
      timeoutBudget: const Duration(milliseconds: 1),
    );
    final result = parser.parse('> task hello');
    expect(result, isA<CommandParseFailure>());
    expect((result as CommandParseFailure).code, 'parser_timeout');
  });

  test('command registry rejects duplicate command ids', () {
    final registry = EntryCommandRegistry();
    registry.register(
      CommandRegistryEntry(
        commandId: NewNoteCommand.id,
        actionLabel: 'new_note',
        execute: (command) async {
          return const rust_api.EntryActionResponse(
            ok: true,
            atomId: null,
            message: 'ok',
          );
        },
      ),
    );

    expect(
      () => registry.register(
        CommandRegistryEntry(
          commandId: NewNoteCommand.id,
          actionLabel: 'new_note_dup',
          execute: (command) async {
            return const rust_api.EntryActionResponse(
              ok: true,
              atomId: null,
              message: 'ok',
            );
          },
        ),
      ),
      throwsA(
        isA<CommandRegistryError>().having(
          (error) => error.code,
          'code',
          'duplicate_command_id',
        ),
      ),
    );
  });

  test('command registry rejects blank command id', () {
    final registry = EntryCommandRegistry();
    expect(
      () => registry.register(
        CommandRegistryEntry(
          commandId: '   ',
          actionLabel: 'invalid',
          execute: (command) async {
            return const rust_api.EntryActionResponse(
              ok: true,
              atomId: null,
              message: 'ok',
            );
          },
        ),
      ),
      throwsA(
        isA<CommandRegistryError>().having(
          (error) => error.code,
          'code',
          'invalid_command_id',
        ),
      ),
    );
  });

  test(
    'first-party command registry executes registered command handlers',
    () async {
      var noteCalls = 0;
      final registry = EntryCommandRegistry.firstParty(
        createNoteInvoker: ({required content}) async {
          noteCalls += 1;
          return const rust_api.EntryActionResponse(
            ok: true,
            atomId: 'a1',
            message: 'created',
          );
        },
        createTaskInvoker: ({required content}) async {
          return const rust_api.EntryActionResponse(
            ok: true,
            atomId: 't1',
            message: 'task',
          );
        },
        scheduleInvoker:
            ({required title, required startEpochMs, endEpochMs}) async {
              return const rust_api.EntryActionResponse(
                ok: true,
                atomId: 's1',
                message: 'schedule',
              );
            },
      );

      final response = await registry.execute(
        const NewNoteCommand(content: 'from registry'),
      );

      expect(response.ok, isTrue);
      expect(noteCalls, 1);
    },
  );

  test(
    'command registry returns explicit error response for unregistered command',
    () async {
      final registry = EntryCommandRegistry();
      final response = await registry.execute(
        const NewNoteCommand(content: 'not-registered'),
      );
      expect(response.ok, isFalse);
      expect(response.message, contains('unknown_command_id'));
      expect(response.message, contains(NewNoteCommand.id));
    },
  );

  test('actionLabelFor falls back to command id when entry is missing', () {
    final registry = EntryCommandRegistry();
    expect(
      registry.actionLabelFor('test.command.missing'),
      'test.command.missing',
    );
  });
}
