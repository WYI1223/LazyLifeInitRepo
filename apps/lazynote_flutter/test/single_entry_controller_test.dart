import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';
import 'package:lazynote_flutter/features/entry/entry_state.dart';
import 'package:lazynote_flutter/features/entry/single_entry_controller.dart';

void main() {
  test('search success maps to success state with results detail', () async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
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

  test('search kind filter is forwarded to search invoker', () async {
    final requestedKinds = <String?>[];
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
        requestedKinds.add(kind);
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

    controller.handleInputChanged('filter me');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requestedKinds, [null]);

    controller.setSearchKindFilter(EntrySearchKindFilter.task);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requestedKinds, [null, 'task']);
    expect(controller.state.detailPayload, contains('filter_kind=task'));
  });

  test('empty input clears to idle state', () async {
    final controller = SingleEntryController(
      searchInvoker: ({required text, required limit, String? kind}) async {
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
      searchInvoker: ({required text, required limit, String? kind}) async {
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
        searchInvoker: ({required text, required limit, String? kind}) {
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

  test('command path keeps preview-only behavior on input change', () {
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

  test(
    'detail action executes new note command and opens result detail',
    () async {
      var prepareCalls = 0;
      var createNoteCalls = 0;
      String? createdContent;

      final controller = SingleEntryController(
        prepareCommand: () async {
          prepareCalls += 1;
        },
        createNoteInvoker: ({required content}) async {
          createNoteCalls += 1;
          createdContent = content;
          return const EntryActionResponse(
            ok: true,
            atomId: 'atom-note-1',
            message: 'Note created.',
          );
        },
        searchDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      const commandText = '> new note ship D1';
      controller.textController.text = commandText;
      controller.handleInputChanged(commandText);
      controller.handleDetailAction();

      expect(controller.state.phase, EntryPhase.loading);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(prepareCalls, 1);
      expect(createNoteCalls, 1);
      expect(createdContent, 'ship D1');
      expect(controller.state.phase, EntryPhase.success);
      expect(controller.state.statusMessage?.text, 'Note created.');
      expect(controller.visibleDetail, contains('action=new_note'));
      expect(controller.visibleDetail, contains('atom_id=atom-note-1'));
      expect(controller.state.rawInput, commandText);
    },
  );

  test(
    'detail action executes task command and uses task action mapping',
    () async {
      String? taskContent;

      final controller = SingleEntryController(
        prepareCommand: () async {},
        createTaskInvoker: ({required content}) async {
          taskContent = content;
          return const EntryActionResponse(
            ok: true,
            atomId: 'atom-task-1',
            message: 'Task created.',
          );
        },
        searchDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      const commandText = '> task finish docs';
      controller.textController.text = commandText;
      controller.handleInputChanged(commandText);
      controller.handleDetailAction();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(taskContent, 'finish docs');
      expect(controller.state.phase, EntryPhase.success);
      expect(controller.state.statusMessage?.text, 'Task created.');
      expect(controller.visibleDetail, contains('action=create_task'));
      expect(controller.visibleDetail, contains('atom_id=atom-task-1'));
    },
  );

  test('detail action executes schedule range with epoch mapping', () async {
    int? startEpoch;
    int? endEpoch;
    String? scheduleTitle;

    final controller = SingleEntryController(
      prepareCommand: () async {},
      scheduleInvoker:
          ({required title, required startEpochMs, endEpochMs}) async {
            scheduleTitle = title;
            startEpoch = startEpochMs;
            endEpoch = endEpochMs;
            return const EntryActionResponse(
              ok: true,
              atomId: 'atom-event-1',
              message: 'Event scheduled.',
            );
          },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    const commandText = '> schedule 03/15/2026 09:30-10:45 weekly sync';
    controller.textController.text = commandText;
    controller.handleInputChanged(commandText);
    controller.handleDetailAction();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(scheduleTitle, 'weekly sync');
    expect(startEpoch, DateTime(2026, 3, 15, 9, 30).millisecondsSinceEpoch);
    expect(endEpoch, DateTime(2026, 3, 15, 10, 45).millisecondsSinceEpoch);
    expect(controller.state.phase, EntryPhase.success);
    expect(controller.state.statusMessage?.text, 'Event scheduled.');
    expect(controller.visibleDetail, contains('action=schedule'));
    expect(controller.visibleDetail, contains('atom_id=atom-event-1'));
  });

  test(
    'command execution failure keeps input and exposes error detail',
    () async {
      final controller = SingleEntryController(
        prepareCommand: () async {},
        createTaskInvoker: ({required content}) async {
          return const EntryActionResponse(
            ok: false,
            atomId: null,
            message: 'entry_create_task failed: db locked',
          );
        },
        searchDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      const commandText = '> task recover failure';
      controller.textController.text = commandText;
      controller.handleInputChanged(commandText);
      controller.handleDetailAction();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, EntryPhase.error);
      expect(
        controller.state.statusMessage?.text,
        'entry_create_task failed: db locked',
      );
      expect(controller.visibleDetail, contains('action=create_task'));
      expect(controller.visibleDetail, contains('ok=false'));
      expect(controller.state.rawInput, commandText);
    },
  );

  test(
    'command response is still delivered after input changes post-submit',
    () async {
      final commandResponse = Completer<EntryActionResponse>();
      var commandCalls = 0;
      var searchCalls = 0;

      final controller = SingleEntryController(
        prepareCommand: () async {},
        createTaskInvoker: ({required content}) {
          commandCalls += 1;
          return commandResponse.future;
        },
        searchInvoker: ({required text, required limit, String? kind}) async {
          searchCalls += 1;
          return const EntrySearchResponse(
            ok: true,
            errorCode: null,
            items: [],
            message: 'No results.',
            appliedLimit: 10,
          );
        },
        prepareSearch: () async {},
        searchDebounce: const Duration(milliseconds: 1),
      );
      addTearDown(controller.dispose);

      const commandText = '> task keep receipt';
      controller.textController.text = commandText;
      controller.handleInputChanged(commandText);
      controller.handleDetailAction();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, EntryPhase.loading);
      expect(commandCalls, 1);

      controller.handleInputChanged('typing after submit');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(searchCalls, 1);

      commandResponse.complete(
        const EntryActionResponse(
          ok: true,
          atomId: 'atom-receipt-1',
          message: 'Task created.',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, EntryPhase.success);
      expect(controller.state.statusMessage?.text, 'Task created.');
      expect(controller.visibleDetail, contains('action=create_task'));
      expect(controller.visibleDetail, contains('atom_id=atom-receipt-1'));
    },
  );

  test('duplicate submit while command is loading is ignored', () async {
    final commandResponse = Completer<EntryActionResponse>();
    var commandCalls = 0;

    final controller = SingleEntryController(
      prepareCommand: () async {},
      createTaskInvoker: ({required content}) {
        commandCalls += 1;
        return commandResponse.future;
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    const commandText = '> task prevent duplicate';
    controller.textController.text = commandText;
    controller.handleInputChanged(commandText);

    controller.handleDetailAction();
    controller.handleDetailAction();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, EntryPhase.loading);
    expect(commandCalls, 1);

    commandResponse.complete(
      const EntryActionResponse(
        ok: true,
        atomId: 'atom-dup-1',
        message: 'Task created.',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(commandCalls, 1);
    expect(controller.state.phase, EntryPhase.success);
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
      searchInvoker: ({required text, required limit, String? kind}) async {
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
      searchInvoker: ({required text, required limit, String? kind}) async {
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
