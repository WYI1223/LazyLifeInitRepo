import 'dart:collection';

import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/entry/command_parser.dart';

/// One command registration entry in registry.
class CommandRegistryEntry {
  const CommandRegistryEntry({
    required this.commandId,
    required this.actionLabel,
    required this.execute,
  });

  /// Stable namespaced command id.
  final String commandId;

  /// Human-readable action label for diagnostics payload.
  final String actionLabel;

  /// Executes one command payload.
  final Future<rust_api.EntryActionResponse> Function(EntryCommand command)
  execute;
}

/// Command registry conflict/validation error.
class CommandRegistryError implements Exception {
  const CommandRegistryError({required this.code, required this.message});

  final String code;
  final String message;
}

/// Runtime command registry used by single-entry command execution.
class EntryCommandRegistry {
  EntryCommandRegistry({Iterable<CommandRegistryEntry> entries = const []}) {
    for (final entry in entries) {
      register(entry);
    }
  }

  final SplayTreeMap<String, CommandRegistryEntry> _entries =
      SplayTreeMap<String, CommandRegistryEntry>();

  /// Registers one command entry.
  ///
  /// Throws [CommandRegistryError] on duplicate/invalid command id.
  void register(CommandRegistryEntry entry) {
    final commandId = entry.commandId.trim();
    if (commandId.isEmpty) {
      throw const CommandRegistryError(
        code: 'invalid_command_id',
        message: 'Command id must not be empty.',
      );
    }
    if (_entries.containsKey(commandId)) {
      throw CommandRegistryError(
        code: 'duplicate_command_id',
        message: 'Duplicate command id: $commandId',
      );
    }

    _entries[commandId] = CommandRegistryEntry(
      commandId: commandId,
      actionLabel: entry.actionLabel,
      execute: entry.execute,
    );
  }

  /// Executes one command via registered entry.
  Future<rust_api.EntryActionResponse> execute(EntryCommand command) async {
    final entry = _entries[command.commandId];
    if (entry == null) {
      return rust_api.EntryActionResponse(
        ok: false,
        atomId: null,
        message:
            '[unknown_command_id] unsupported command: ${command.commandId}',
      );
    }
    return entry.execute(command);
  }

  /// Returns action label for one command id.
  String actionLabelFor(String commandId) {
    return _entries[commandId]?.actionLabel ?? commandId;
  }

  /// Number of registered commands.
  int get length => _entries.length;

  /// Builds first-party command registry baseline.
  factory EntryCommandRegistry.firstParty({
    required Future<rust_api.EntryActionResponse> Function({
      required String content,
    })
    createNoteInvoker,
    required Future<rust_api.EntryActionResponse> Function({
      required String content,
    })
    createTaskInvoker,
    required Future<rust_api.EntryActionResponse> Function({
      required String title,
      required int startEpochMs,
      int? endEpochMs,
    })
    scheduleInvoker,
  }) {
    return EntryCommandRegistry(
      entries: <CommandRegistryEntry>[
        CommandRegistryEntry(
          commandId: NewNoteCommand.id,
          actionLabel: 'new_note',
          execute: (command) {
            final typed = command as NewNoteCommand;
            return createNoteInvoker(content: typed.content);
          },
        ),
        CommandRegistryEntry(
          commandId: CreateTaskCommand.id,
          actionLabel: 'create_task',
          execute: (command) {
            final typed = command as CreateTaskCommand;
            return createTaskInvoker(content: typed.content);
          },
        ),
        CommandRegistryEntry(
          commandId: ScheduleCommand.id,
          actionLabel: 'schedule',
          execute: (command) {
            final typed = command as ScheduleCommand;
            return scheduleInvoker(
              title: typed.title,
              startEpochMs: typed.start.millisecondsSinceEpoch,
              endEpochMs: typed.end?.millisecondsSinceEpoch,
            );
          },
        ),
      ],
    );
  }
}
