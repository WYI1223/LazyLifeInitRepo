import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';

void main() {
  test('idle constructor starts with empty neutral state', () {
    const state = EntryState.idle();
    expect(state.phase, EntryPhase.idle);
    expect(state.rawInput, isEmpty);
    expect(state.intent, isNull);
    expect(state.statusMessage, isNull);
  });

  test('toLoading sets phase and info message', () {
    const initial = EntryState.idle();
    final next = initial.toLoading(
      rawInput: 'query',
      intent: const SearchIntent(text: 'query', limit: 10),
    );

    expect(next.phase, EntryPhase.loading);
    expect(next.rawInput, 'query');
    expect(next.statusMessage?.type, EntryStatusMessageType.info);
  });

  test('toSuccess writes success state and detail payload', () {
    const initial = EntryState.idle();
    final next = initial.toSuccess(
      rawInput: '> task buy milk',
      intent: const CommandIntent(command: NewNoteCommand(content: 'buy milk')),
      message: 'Task created.',
      detailPayload: '{"ok":true}',
    );

    expect(next.phase, EntryPhase.success);
    expect(next.statusMessage?.type, EntryStatusMessageType.success);
    expect(next.detailPayload, '{"ok":true}');
  });

  test('toError preserves input and records error message', () {
    const initial = EntryState.idle();
    final next = initial.toError(
      rawInput: '> bad',
      intent: const ParseErrorIntent(
        code: 'unknown_command',
        message: 'Unknown command.',
      ),
      message: 'Unknown command.',
    );

    expect(next.phase, EntryPhase.error);
    expect(next.rawInput, '> bad');
    expect(next.hasError, isTrue);
    expect(next.statusMessage?.type, EntryStatusMessageType.error);
  });
}
