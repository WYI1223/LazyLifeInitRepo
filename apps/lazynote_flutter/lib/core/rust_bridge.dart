import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/bindings/frb_generated.dart';

class RustHealthSnapshot {
  const RustHealthSnapshot({required this.ping, required this.coreVersion});

  final String ping;
  final String coreVersion;
}

typedef RustBridgeLogger =
    void Function({
      required String message,
      Object? error,
      StackTrace? stackTrace,
    });

class RustBridge {
  static bool _initialized = false;
  static Future<void>? _initFuture;

  @visibleForTesting
  static String Function() operatingSystem = () => Platform.operatingSystem;

  @visibleForTesting
  static bool Function(String path) fileExists = (path) =>
      File(path).existsSync();

  @visibleForTesting
  static ExternalLibrary Function(String path) externalLibraryOpener =
      ExternalLibrary.open;

  @visibleForTesting
  static Future<void> Function(ExternalLibrary? externalLibrary) rustLibInit =
      (externalLibrary) {
        if (externalLibrary != null) {
          return RustLib.init(externalLibrary: externalLibrary);
        }
        return RustLib.init();
      };

  @visibleForTesting
  static RustBridgeLogger logger =
      ({required String message, Object? error, StackTrace? stackTrace}) {
        dev.log(
          message,
          name: 'RustBridge',
          error: error,
          stackTrace: stackTrace,
        );
      };

  @visibleForTesting
  static List<String>? candidateLibraryPathsOverride;

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _initFuture = null;
    operatingSystem = () => Platform.operatingSystem;
    fileExists = (path) => File(path).existsSync();
    externalLibraryOpener = ExternalLibrary.open;
    rustLibInit = (externalLibrary) {
      if (externalLibrary != null) {
        return RustLib.init(externalLibrary: externalLibrary);
      }
      return RustLib.init();
    };
    logger =
        ({required String message, Object? error, StackTrace? stackTrace}) {
          dev.log(
            message,
            name: 'RustBridge',
            error: error,
            stackTrace: stackTrace,
          );
        };
    candidateLibraryPathsOverride = null;
  }

  static ExternalLibrary? _resolveWorkspaceLibrary() {
    final dynamicLibraryFileName = switch (operatingSystem()) {
      'windows' => 'lazynote_ffi.dll',
      'linux' => 'liblazynote_ffi.so',
      'macos' => 'liblazynote_ffi.dylib',
      _ => null,
    };

    if (dynamicLibraryFileName == null) {
      return null;
    }

    final useOverridePaths = candidateLibraryPathsOverride != null;
    final candidates =
        candidateLibraryPathsOverride ??
        <String>[
          '../../crates/target/release/$dynamicLibraryFileName',
          '../../crates/lazynote_ffi/target/release/$dynamicLibraryFileName',
        ];

    for (final candidatePath in candidates) {
      final filePath = useOverridePaths
          ? candidatePath
          : Directory.current.uri.resolve(candidatePath).toFilePath();
      if (fileExists(filePath)) {
        try {
          return externalLibraryOpener(filePath);
        } catch (error, stackTrace) {
          logger(
            message: 'Failed to open Rust dylib candidate: $filePath',
            error: error,
            stackTrace: stackTrace,
          );
          continue;
        }
      }
    }

    return null;
  }

  static Future<void> init() {
    if (_initialized) {
      return Future.value();
    }

    final inFlight = _initFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _initInternal();
    _initFuture = future;
    return future;
  }

  static Future<void> _initInternal() async {
    try {
      final externalLibrary = _resolveWorkspaceLibrary();
      await rustLibInit(externalLibrary);

      _initialized = true;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  static Future<RustHealthSnapshot> runHealthCheck() async {
    await init();
    return RustHealthSnapshot(
      ping: rust_api.ping(),
      coreVersion: rust_api.coreVersion(),
    );
  }
}
