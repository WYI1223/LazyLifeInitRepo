import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';

void main() {
  test('search success maps to success state with results detail', () async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit}) async {
        return EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: const [
            EntrySearchItem(
              atomId: 'atom-1',
              kind: 'note',
              snippet: 'hello world',
            ),
          ],
          message: 'Found 1 result(s).',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.handleInputChanged('hello');
    expect(controller.state.phase, EntryPhase.loading);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.phase, EntryPhase.success);
    expect(controller.state.statusMessage?.text, 'Found 1 result(s).');
    expect(controller.state.detailPayload, contains('atom-1'));
  });

  test('empty input clears to idle state', () async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit}) async {
        return const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [],
          message: 'No results.',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.handleInputChanged('something');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, EntryPhase.success);

    controller.handleInputChanged('   ');
    expect(controller.state.phase, EntryPhase.idle);
    expect(controller.state.rawInput, isEmpty);
  });

  test('search error response maps to error state with code', () async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit}) async {
        return const EntrySearchResponse(
          ok: false,
          errorCode: 'search_failed',
          items: [],
          message: 'backend failed',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.handleInputChanged('boom');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.phase, EntryPhase.error);
    expect(
      controller.state.statusMessage?.text,
      '[search_failed] backend failed',
    );
    expect(controller.state.rawInput, 'boom');
  });

  test(
    'latest search response wins when earlier request finishes late',
    () async {
      final first = Completer<EntrySearchResponse>();
      final second = Completer<EntrySearchResponse>();

      final controller = SingleEntryController(
        searchInvoker: ({required text, required limit}) {
          if (text == 'first') {
            return first.future;
          }
          return second.future;
        },
        searchDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.handleInputChanged('first');
      await Future<void>.delayed(Duration.zero);
      controller.handleInputChanged('second');
      await Future<void>.delayed(Duration.zero);

      second.complete(
        const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-second',
              kind: 'note',
              snippet: 'second',
            ),
          ],
          message: 'Found 1 result(s).',
          appliedLimit: 10,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, EntryPhase.success);
      expect(controller.state.detailPayload, contains('atom-second'));

      first.complete(
        const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [
            EntrySearchItem(
              atomId: 'atom-first',
              kind: 'note',
              snippet: 'first',
            ),
          ],
          message: 'Found 1 result(s).',
          appliedLimit: 10,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.detailPayload, contains('atom-second'));
      expect(controller.state.detailPayload, isNot(contains('atom-first')));
    },
  );

  test('command path remains preview-only in C phase', () {
    final controller = SingleEntryController(searchDebounce: Duration.zero);
    addTearDown(controller.dispose);

    controller.handleInputChanged('> task ship C1');
    expect(controller.state.phase, EntryPhase.success);
    expect(
      controller.state.statusMessage?.text,
      'Command preview ready. Press Enter or Send for details.',
    );
    expect(controller.state.intent, isA<CommandIntent>());
  });

  test('search waits for prepare step before invoking search call', () async {
    final prepareGate = Completer<void>();
    var prepareCalls = 0;
    var prepareFinished = false;
    var searchCalledBeforePrepare = false;

    final controller = SingleEntryController(
      prepareSearch: () async {
        prepareCalls += 1;
        await prepareGate.future;
        prepareFinished = true;
      },
      searchInvoker: ({required text, required limit}) async {
        if (!prepareFinished) {
          searchCalledBeforePrepare = true;
        }
        return const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [],
          message: 'No results.',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.handleInputChanged('race');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, EntryPhase.loading);
    expect(prepareCalls, 1);

    prepareGate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(searchCalledBeforePrepare, isFalse);
    expect(controller.state.phase, EntryPhase.success);
  });

  test('prepare failure blocks search call and surfaces error', () async {
    var searchCalls = 0;

    final controller = SingleEntryController(
      prepareSearch: () async => throw StateError('db config failed'),
      searchInvoker: ({required text, required limit}) async {
        searchCalls += 1;
        return const EntrySearchResponse(
          ok: true,
          errorCode: null,
          items: [],
          message: 'No results.',
          appliedLimit: 10,
        );
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.handleInputChanged('needs-db');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(searchCalls, 0);
    expect(controller.state.phase, EntryPhase.error);
    expect(controller.state.statusMessage?.text, contains('db config failed'));
  });
}
