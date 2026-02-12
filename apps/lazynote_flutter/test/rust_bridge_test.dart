import 'dart:async';

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
}
