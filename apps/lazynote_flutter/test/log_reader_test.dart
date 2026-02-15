import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/debug/log_reader.dart';

void main() {
  tearDown(() {
    LogReader.resetForTesting();
  });

  test('openLogFolder surfaces explicit stderr failure', () async {
    final tempDir = await Directory.systemTemp.createTemp('lazynote-log-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    LogReader.processRunner = (String executable, List<String> args) async =>
        ProcessResult(1, 1, '', 'simulated failure');

    expect(
      () => LogReader.openLogFolder(tempDir.path),
      throwsA(isA<ProcessException>()),
    );
  });

  test('openLogFolder tolerates explorer non-zero without stderr', () async {
    final tempDir = await Directory.systemTemp.createTemp('lazynote-log-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    LogReader.processRunner = (String executable, List<String> args) async =>
        ProcessResult(1, 1, '', '');

    if (Platform.isWindows) {
      await LogReader.openLogFolder(tempDir.path);
      return;
    }

    expect(
      () => LogReader.openLogFolder(tempDir.path),
      throwsA(isA<ProcessException>()),
    );
  });

  test('openLogFolder fails when directory is missing', () async {
    final missingPath = Directory.systemTemp
        .createTempSync('lazynote-log-test-')
        .path;
    await Directory(missingPath).delete(recursive: true);

    LogReader.processRunner = (String executable, List<String> args) async =>
        ProcessResult(1, 1, '', '');

    expect(
      () => LogReader.openLogFolder(missingPath),
      throwsA(isA<ProcessException>()),
    );
  });

  test('readLatestTail uses tail reader for large log files', () async {
    final tempDir = await Directory.systemTemp.createTemp('lazynote-log-tail-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final largeFile = File(
      '${tempDir.path}${Platform.pathSeparator}lazynote-big.log',
    );
    final largeContent = List.filled(300 * 1024, 'a').join();
    await largeFile.writeAsString(largeContent);

    LogReader.logDirPathResolver = () async => tempDir.path;

    var fullReaderCalls = 0;
    var tailReaderCalls = 0;
    LogReader.fileReader = (File file) async {
      fullReaderCalls += 1;
      return 'full';
    };
    LogReader.fileTailReader = (File file, int maxBytes) async {
      tailReaderCalls += 1;
      // Newline-terminated: simulates a properly flushed log file.
      return 'tail-only-line\n';
    };

    final snapshot = await LogReader.readLatestTail(maxLines: 50);
    expect(snapshot.tailText, contains('tail-only-line'));
    expect(fullReaderCalls, 0);
    expect(tailReaderCalls, 1);
  });

  test('readLatestTail discards incomplete trailing line', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'lazynote-log-guard-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final logFile = File(
      '${tempDir.path}${Platform.pathSeparator}lazynote-guard.log',
    );
    await logFile.writeAsString('placeholder');

    LogReader.logDirPathResolver = () async => tempDir.path;
    // Simulate a mid-write read: last line has no trailing newline.
    LogReader.fileReader = (File file) async =>
        'line1\nline2\nincomplete_partial';

    final snapshot = await LogReader.readLatestTail(maxLines: 200);
    expect(snapshot.tailText, equals('line1\nline2'));
    expect(snapshot.tailText, isNot(contains('incomplete_partial')));
  });

  test(
    'readLatestTail keeps last line when content ends with newline',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('lazynote-log-nl-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final logFile = File(
        '${tempDir.path}${Platform.pathSeparator}lazynote-nl.log',
      );
      await logFile.writeAsString('placeholder');

      LogReader.logDirPathResolver = () async => tempDir.path;
      // Properly terminated content — last line must be kept.
      LogReader.fileReader = (File file) async => 'line1\nline2\n';

      final snapshot = await LogReader.readLatestTail(maxLines: 200);
      expect(snapshot.tailText, equals('line1\nline2'));
    },
  );
}
