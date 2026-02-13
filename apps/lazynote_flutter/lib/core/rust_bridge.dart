import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;
import 'package:lazynote_flutter/core/bindings/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

/// Health-check values returned from Rust smoke APIs.
class RustHealthSnapshot {
  const RustHealthSnapshot({required this.ping, required this.coreVersion});

  /// Expected to be `pong` when bridge calls are healthy.
  final String ping;

  /// Rust core crate version string.
  final String coreVersion;
}

/// Result snapshot for startup logging initialization.
class RustLoggingInitSnapshot {
  const RustLoggingInitSnapshot.success({
    required this.level,
    required this.logDir,
  }) : errorMessage = null;

  const RustLoggingInitSnapshot.failure({
    required this.level,
    required this.logDir,
    required this.errorMessage,
  });

  /// Effective log level passed to Rust core.
  final String level;

  /// Effective log directory passed to Rust core.
  final String logDir;

  /// Human-readable error on failure; `null` on success.
  final String? errorMessage;

  /// Whether logging initialization succeeded.
  bool get isSuccess => errorMessage == null;
}

/// Pluggable logger sink used by bridge internals.
typedef RustBridgeLogger =
    void Function({
      required String message,
      Object? error,
      StackTrace? stackTrace,
    });

/// Pluggable FFI call used to initialize Rust-side logging.
typedef RustInitLoggingCall =
    String Function({required String level, required String logDir});

/// Pluggable FFI call used to configure entry DB path.
typedef RustConfigureEntryDbPathCall =
    String Function({required String dbPath});

/// Rust FFI bootstrap helper for app startup and diagnostics flows.
///
/// Contract:
/// - `init()` initializes FRB once and deduplicates concurrent calls.
/// - `bootstrapLogging()` never throws and never blocks app startup decisions.
/// - All failures are captured as snapshots/messages for diagnostics UI.
class RustBridge {
  static bool _initialized = false;
  static Future<void>? _initFuture;
  // Tracks entry DB path readiness independently from logging bootstrap.
  // Search/command paths can require this before logs are initialized.
  static bool _entryDbPathConfigured = false;
  static Future<void>? _entryDbPathFuture;
  static RustLoggingInitSnapshot? _latestLoggingInitSnapshot;
  static Future<RustLoggingInitSnapshot>? _loggingInitFuture;

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
  static Future<Directory> Function() applicationSupportDirectoryResolver =
      getApplicationSupportDirectory;

  @visibleForTesting
  static String Function() defaultLogLevelResolver = () =>
      kReleaseMode ? 'info' : 'debug';

  @visibleForTesting
  static RustInitLoggingCall initLoggingCall =
      ({required String level, required String logDir}) =>
          rust_api.initLogging(level: level, logDir: logDir);

  @visibleForTesting
  static RustConfigureEntryDbPathCall configureEntryDbPathCall =
      ({required String dbPath}) =>
          rust_api.configureEntryDbPath(dbPath: dbPath);

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

  /// Resets mutable static hooks to production defaults for isolated tests.
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _initFuture = null;
    _entryDbPathConfigured = false;
    _entryDbPathFuture = null;
    _latestLoggingInitSnapshot = null;
    _loggingInitFuture = null;
    operatingSystem = () => Platform.operatingSystem;
    fileExists = (path) => File(path).existsSync();
    externalLibraryOpener = ExternalLibrary.open;
    rustLibInit = (externalLibrary) {
      if (externalLibrary != null) {
        return RustLib.init(externalLibrary: externalLibrary);
      }
      return RustLib.init();
    };
    applicationSupportDirectoryResolver = getApplicationSupportDirectory;
    defaultLogLevelResolver = () => kReleaseMode ? 'info' : 'debug';
    initLoggingCall = ({required String level, required String logDir}) =>
        rust_api.initLogging(level: level, logDir: logDir);
    configureEntryDbPathCall = ({required String dbPath}) =>
        rust_api.configureEntryDbPath(dbPath: dbPath);
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
          // Why: continue trying other candidates so one bad file does not
          // permanently block bridge initialization in local dev layouts.
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

  /// Initializes FRB bridge runtime once per process.
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

  /// Latest in-process logging bootstrap result for diagnostics UI.
  static RustLoggingInitSnapshot? get latestLoggingInitSnapshot =>
      _latestLoggingInitSnapshot;

  /// Ensures entry DB path is configured before entry search/command calls.
  ///
  /// Contract:
  /// - De-duplicates concurrent calls in-process.
  /// - Safe to call repeatedly; subsequent calls are no-op after success.
  /// - Throws on configuration failure so callers can surface deterministic
  ///   startup/command errors instead of silently falling back to temp DB.
  static Future<void> ensureEntryDbPathConfigured({String? dbPathOverride}) {
    if (_entryDbPathConfigured) {
      return Future.value();
    }

    final inFlight = _entryDbPathFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _ensureEntryDbPathConfiguredInternal(
      dbPathOverride: dbPathOverride,
    );
    _entryDbPathFuture = future;
    return future;
  }

  static String _resolveEntryDbPathFromSupportDir(Directory supportDir) {
    return '${supportDir.path}${Platform.pathSeparator}data${Platform.pathSeparator}lazynote_entry.sqlite3';
  }

  static Future<void> _ensureEntryDbPathConfiguredInternal({
    String? dbPathOverride,
  }) async {
    try {
      final resolvedDbPath =
          dbPathOverride ??
          _resolveEntryDbPathFromSupportDir(
            await applicationSupportDirectoryResolver(),
          );

      await init();
      final dbConfigError = configureEntryDbPathCall(dbPath: resolvedDbPath);
      if (dbConfigError.isNotEmpty) {
        throw StateError(
          'entry db path configure failed for "$resolvedDbPath": $dbConfigError',
        );
      }

      _entryDbPathConfigured = true;
      // Clear in-flight marker so subsequent calls fast-path on configured flag.
      _entryDbPathFuture = null;
    } catch (_) {
      _entryDbPathFuture = null;
      rethrow;
    }
  }

  /// Initializes Rust logging for the current process.
  ///
  /// Non-fatal behavior:
  /// - Always returns a snapshot.
  /// - Never throws to callers.
  /// - On failure, app startup should continue.
  static Future<RustLoggingInitSnapshot> bootstrapLogging() {
    final cached = _latestLoggingInitSnapshot;
    if (cached != null && cached.isSuccess) {
      return Future.value(cached);
    }

    final inFlight = _loggingInitFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _bootstrapLoggingInternal();
    _loggingInitFuture = future;
    return future;
  }

  static Future<RustLoggingInitSnapshot> _bootstrapLoggingInternal() async {
    final level = defaultLogLevelResolver();
    var resolvedLogDir = 'unresolved';
    var resolvedDbPath = 'unresolved';

    RustLoggingInitSnapshot result;
    try {
      final supportDir = await applicationSupportDirectoryResolver();
      // Why: keep platform path resolution in Flutter and pass resolved path
      // into Rust to avoid platform-specific path guessing in core.
      resolvedLogDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}logs',
      ).path;
      resolvedDbPath = _resolveEntryDbPathFromSupportDir(supportDir);

      await ensureEntryDbPathConfigured(dbPathOverride: resolvedDbPath);
      final initError = initLoggingCall(level: level, logDir: resolvedLogDir);
      if (initError.isEmpty) {
        result = RustLoggingInitSnapshot.success(
          level: level,
          logDir: resolvedLogDir,
        );
      } else {
        logger(message: 'Rust logging init returned error.', error: initError);
        result = RustLoggingInitSnapshot.failure(
          level: level,
          logDir: resolvedLogDir,
          errorMessage: initError,
        );
      }
    } catch (error, stackTrace) {
      logger(
        message:
            'Rust logging/entry-db init failed. log_dir=$resolvedLogDir db_path=$resolvedDbPath',
        error: error,
        stackTrace: stackTrace,
      );
      result = RustLoggingInitSnapshot.failure(
        level: level,
        logDir: resolvedLogDir,
        errorMessage: error.toString(),
      );
    }

    _latestLoggingInitSnapshot = result;
    _loggingInitFuture = null;
    return result;
  }

  /// Runs Rust smoke APIs used by diagnostics UI.
  static Future<RustHealthSnapshot> runHealthCheck() async {
    await init();
    return RustHealthSnapshot(
      ping: rust_api.ping(),
      coreVersion: rust_api.coreVersion(),
    );
  }
}
