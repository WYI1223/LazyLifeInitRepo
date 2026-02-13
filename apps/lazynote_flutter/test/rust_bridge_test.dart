import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/rust_bridge.dart';

void main() {
  tearDown(() {
    RustBridge.resetForTesting();
  });

  test('init de-duplicates concurrent calls', () async {
    RustBridge.resetForTesting();
    RustBridge.candidateLibraryPathsOverride = const [];

    var initCalls = 0;
    final blocker = Completer<void>();
    RustBridge.rustLibInit = (_) async {
      initCalls += 1;
      await blocker.future;
    };

    final futures = <Future<void>>[
      RustBridge.init(),
      RustBridge.init(),
      RustBridge.init(),
    ];

    expect(initCalls, 1);
    blocker.complete();
    await Future.wait(futures);

    await RustBridge.init();
    expect(initCalls, 1);
  });

  test('init can retry after first failure', () async {
    RustBridge.resetForTesting();
    RustBridge.candidateLibraryPathsOverride = const [];

    var initAttempts = 0;
    RustBridge.rustLibInit = (_) async {
      initAttempts += 1;
      if (initAttempts == 1) {
        throw StateError('first init failed');
      }
    };

    await expectLater(RustBridge.init(), throwsA(isA<StateError>()));
    await RustBridge.init();
    expect(initAttempts, 2);
  });

  test('falls back to next candidate if opening library fails', () async {
    RustBridge.resetForTesting();
    RustBridge.operatingSystem = () => 'windows';
    RustBridge.candidateLibraryPathsOverride = const [
      'first_candidate.dll',
      'second_candidate.dll',
    ];
    RustBridge.fileExists = (_) => true;

    final openedCandidates = <String>[];
    final logMessages = <String>[];

    RustBridge.externalLibraryOpener = (path) {
      openedCandidates.add(path);
      throw StateError('cannot open $path');
    };
    RustBridge.logger = ({required message, error, stackTrace}) {
      logMessages.add('$message | $error');
    };
    RustBridge.rustLibInit = (_) async {};

    await RustBridge.init();

    expect(openedCandidates, const [
      'first_candidate.dll',
      'second_candidate.dll',
    ]);
    expect(logMessages.length, 2);
  });

  test('bootstrapLogging de-duplicates concurrent calls', () async {
    RustBridge.resetForTesting();
    RustBridge.candidateLibraryPathsOverride = const [];

    var dirCalls = 0;
    RustBridge.applicationSupportDirectoryResolver = () async {
      dirCalls += 1;
      return Directory.systemTemp;
    };

    var initLoggingCalls = 0;
    var configureCalls = 0;
    RustBridge.rustLibInit = (_) async {};
    RustBridge.configureEntryDbPathCall = ({required dbPath}) {
      configureCalls += 1;
      return '';
    };
    RustBridge.initLoggingCall = ({required level, required logDir}) {
      initLoggingCalls += 1;
      return '';
    };

    final futures = <Future<RustLoggingInitSnapshot>>[
      RustBridge.bootstrapLogging(),
      RustBridge.bootstrapLogging(),
      RustBridge.bootstrapLogging(),
    ];

    final snapshots = await Future.wait(futures);
    expect(dirCalls, 1);
    expect(configureCalls, 1);
    expect(initLoggingCalls, 1);
    expect(snapshots.every((snapshot) => snapshot.isSuccess), isTrue);
  });

  test('ensureEntryDbPathConfigured de-duplicates concurrent calls', () async {
    RustBridge.resetForTesting();
    RustBridge.candidateLibraryPathsOverride = const [];

    var dirCalls = 0;
    var configureCalls = 0;
    RustBridge.applicationSupportDirectoryResolver = () async {
      dirCalls += 1;
      return Directory.systemTemp;
    };
    RustBridge.rustLibInit = (_) async {};
    RustBridge.configureEntryDbPathCall = ({required dbPath}) {
      configureCalls += 1;
      return '';
    };

    await Future.wait([
      RustBridge.ensureEntryDbPathConfigured(),
      RustBridge.ensureEntryDbPathConfigured(),
      RustBridge.ensureEntryDbPathConfigured(),
    ]);

    expect(dirCalls, 1);
    expect(configureCalls, 1);

    await RustBridge.ensureEntryDbPathConfigured();
    expect(configureCalls, 1);
  });

  test('bootstrapLogging returns failure snapshot on init error', () async {
    RustBridge.resetForTesting();
    RustBridge.applicationSupportDirectoryResolver = () async =>
        Directory.systemTemp;
    RustBridge.configureEntryDbPathCall = ({required dbPath}) => '';
    RustBridge.rustLibInit = (_) async {
      throw StateError('ffi init failed');
    };

    final snapshot = await RustBridge.bootstrapLogging();
    expect(snapshot.isSuccess, isFalse);
    expect(snapshot.errorMessage, contains('ffi init failed'));
  });

  test(
    'bootstrapLogging returns failure when entry db path config fails',
    () async {
      RustBridge.resetForTesting();
      RustBridge.applicationSupportDirectoryResolver = () async =>
          Directory.systemTemp;
      RustBridge.rustLibInit = (_) async {};
      RustBridge.configureEntryDbPathCall = ({required dbPath}) =>
          'db path denied';
      var initLoggingCalls = 0;
      RustBridge.initLoggingCall = ({required level, required logDir}) {
        initLoggingCalls += 1;
        return '';
      };

      final snapshot = await RustBridge.bootstrapLogging();
      expect(snapshot.isSuccess, isFalse);
      expect(snapshot.errorMessage, contains('db path denied'));
      expect(initLoggingCalls, 0);
    },
  );
}
