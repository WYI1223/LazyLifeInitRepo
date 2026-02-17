import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/features/reminders/reminder_scheduler.dart';

import 'helpers/mock_reminder_service.dart';

void main() {
  late MockReminderService mockService;

  setUp(() async {
    mockService = MockReminderService();
    ReminderScheduler.setServiceForTesting(mockService);
    await ReminderScheduler.ensureInitialized();
  });

  tearDown(() {
    ReminderScheduler.resetForTesting();
  });

  rust_api.AtomListItem atomItem({
    required String atomId,
    required String content,
    int? startAt,
    int? endAt,
  }) {
    return rust_api.AtomListItem(
      atomId: atomId,
      kind: 'note',
      content: content,
      previewText: null,
      previewImage: null,
      tags: const [],
      startAt: startAt,
      endAt: endAt,
      taskStatus: null,
      updatedAt: 1000,
    );
  }

  group('ReminderScheduler time-matrix scheduling', () {
    test(
      'DDL task: [NULL, Value] schedules reminder 15 min before end_at',
      () async {
        final deadlineMs = DateTime(2026, 2, 20, 10, 0).millisecondsSinceEpoch;
        final atom = atomItem(
          atomId: 'ddl-1',
          content: 'Submit report',
          endAt: deadlineMs,
        );

        await ReminderScheduler.scheduleRemindersForAtoms([atom]);

        expect(mockService.scheduled.length, 1);
        final notification = mockService.scheduled.first;

        final expectedTime = DateTime.fromMillisecondsSinceEpoch(
          deadlineMs,
        ).subtract(const Duration(minutes: 15));
        expect(notification.scheduledTime.hour, expectedTime.hour);
        expect(notification.scheduledTime.minute, expectedTime.minute);
        expect(notification.body, contains('Deadline'));
      },
    );

    test(
      'Ongoing task: [Value, NULL] schedules reminder at start_at',
      () async {
        final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
        final atom = atomItem(
          atomId: 'ongoing-1',
          content: 'Work on project',
          startAt: startMs,
        );

        await ReminderScheduler.scheduleRemindersForAtoms([atom]);

        expect(mockService.scheduled.length, 1);
        final notification = mockService.scheduled.first;

        final expectedTime = DateTime.fromMillisecondsSinceEpoch(startMs);
        expect(notification.scheduledTime.hour, expectedTime.hour);
        expect(notification.scheduledTime.minute, expectedTime.minute);
        expect(notification.body, contains('Task starting'));
      },
    );

    test(
      'Event: [Value, Value] schedules reminder 15 min before start_at',
      () async {
        final startMs = DateTime(2026, 2, 20, 14, 0).millisecondsSinceEpoch;
        final endMs = DateTime(2026, 2, 20, 15, 0).millisecondsSinceEpoch;
        final atom = atomItem(
          atomId: 'event-1',
          content: 'Team meeting',
          startAt: startMs,
          endAt: endMs,
        );

        await ReminderScheduler.scheduleRemindersForAtoms([atom]);

        expect(mockService.scheduled.length, 1);
        final notification = mockService.scheduled.first;

        final expectedTime = DateTime.fromMillisecondsSinceEpoch(
          startMs,
        ).subtract(const Duration(minutes: 15));
        expect(notification.scheduledTime.hour, expectedTime.hour);
        expect(notification.scheduledTime.minute, expectedTime.minute);
        expect(notification.body, contains('Event starting'));
      },
    );

    test('Timeless: [NULL, NULL] does not schedule reminder', () async {
      final atom = atomItem(atomId: 'note-1', content: 'Just a thought');

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      expect(mockService.scheduled.length, 0);
    });

    test('multiple atoms with different time-matrix types', () async {
      final now = DateTime.now();
      final ddlDeadline = now
          .add(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      final ongoingStart = now
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      final eventStart = now
          .add(const Duration(hours: 3))
          .millisecondsSinceEpoch;
      final eventEnd = now.add(const Duration(hours: 4)).millisecondsSinceEpoch;

      await ReminderScheduler.scheduleRemindersForAtoms([
        atomItem(atomId: 'ddl', content: 'Deadline task', endAt: ddlDeadline),
        atomItem(
          atomId: 'ongoing',
          content: 'Ongoing task',
          startAt: ongoingStart,
        ),
        atomItem(
          atomId: 'event',
          content: 'Meeting',
          startAt: eventStart,
          endAt: eventEnd,
        ),
        atomItem(atomId: 'note', content: 'Just a note'),
      ]);

      // Should schedule 3 reminders (timeless note excluded)
      expect(mockService.scheduled.length, 3);
    });
  });

  group('ReminderScheduler idempotency', () {
    test('re-scheduling same atom replaces previous reminder', () async {
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
      final atom = atomItem(
        atomId: 'idempotent-1',
        content: 'Test task',
        startAt: startMs,
      );

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);
      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      // Should still have only 1 notification (previous cancelled, new scheduled)
      expect(mockService.scheduled.length, 1);
    });

    test('different atoms get different notification IDs', () async {
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;

      await ReminderScheduler.scheduleRemindersForAtoms([
        atomItem(atomId: 'atom-a', content: 'Task A', startAt: startMs),
        atomItem(atomId: 'atom-b', content: 'Task B', startAt: startMs),
      ]);

      expect(mockService.scheduled.length, 2);
      expect(
        mockService.scheduled[0].id,
        isNot(equals(mockService.scheduled[1].id)),
      );
    });
  });

  group('ReminderScheduler title', () {
    test('truncates long title and adds ellipsis', () async {
      final longContent =
          'This is a very long task title that exceeds fifty characters limit';
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
      final atom = atomItem(
        atomId: 'long-title',
        content: longContent,
        startAt: startMs,
      );

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      final notification = mockService.scheduled.first;
      expect(notification.title.length, lessThan(71));
      expect(notification.title, endsWith('...'));
    });

    test('uses first line only for title', () async {
      final multiline = 'First line\nSecond line\nThird line';
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
      final atom = atomItem(
        atomId: 'multiline',
        content: multiline,
        startAt: startMs,
      );

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      final notification = mockService.scheduled.first;
      expect(notification.title, equals('First line'));
    });
  });

  group('ReminderScheduler cancel', () {
    test('cancelReminderForAtom cancels specific atom', () async {
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
      await ReminderScheduler.scheduleRemindersForAtoms([
        atomItem(atomId: 'cancel-1', content: 'Task 1', startAt: startMs),
        atomItem(atomId: 'cancel-2', content: 'Task 2', startAt: startMs),
      ]);

      expect(mockService.scheduled.length, 2);

      await ReminderScheduler.cancelReminderForAtom('cancel-1');

      expect(mockService.scheduled.length, 1);
    });

    test('cancelAllReminders clears all notifications', () async {
      final startMs = DateTime(2026, 2, 20, 9, 0).millisecondsSinceEpoch;
      await ReminderScheduler.scheduleRemindersForAtoms([
        atomItem(atomId: 'cancel-1', content: 'Task 1', startAt: startMs),
        atomItem(atomId: 'cancel-2', content: 'Task 2', startAt: startMs),
      ]);

      expect(mockService.scheduled.length, 2);

      await ReminderScheduler.cancelAllReminders();

      expect(mockService.scheduled.length, 0);
    });
  });

  group('ReminderScheduler body shows actual time', () {
    test('DDL body shows deadline time, not reminder time', () async {
      final deadlineMs = DateTime(2026, 2, 20, 10, 0).millisecondsSinceEpoch;
      final atom = atomItem(
        atomId: 'ddl-body',
        content: 'Report due',
        endAt: deadlineMs,
      );

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      final notification = mockService.scheduled.first;
      // Body should show 10:00 (the deadline), not 09:45 (the reminder time)
      expect(notification.body, equals('Deadline: 10:00'));
    });

    test('Event body shows event start time, not reminder time', () async {
      final startMs = DateTime(2026, 2, 20, 14, 0).millisecondsSinceEpoch;
      final endMs = DateTime(2026, 2, 20, 15, 0).millisecondsSinceEpoch;
      final atom = atomItem(
        atomId: 'event-body',
        content: 'Meeting',
        startAt: startMs,
        endAt: endMs,
      );

      await ReminderScheduler.scheduleRemindersForAtoms([atom]);

      final notification = mockService.scheduled.first;
      // Body should show 14:00 (event start), not 13:45 (reminder time)
      expect(notification.body, equals('Event starting: 14:00'));
    });
  });

  group('ReminderScheduler initialize', () {
    test('initializes the underlying service', () async {
      // Reset to un-initialized state
      final freshMock = MockReminderService();
      ReminderScheduler.setServiceForTesting(freshMock);

      expect(freshMock.isInitialized, false);

      await ReminderScheduler.ensureInitialized();

      expect(freshMock.isInitialized, true);
    });
  });
}
