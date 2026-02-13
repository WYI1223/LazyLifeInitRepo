import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:lazynote_flutter/core/local_paths.dart';

/// Ensures local settings file exists at a stable path.
class LocalSettingsStore {
  static bool _initialized = false;
  static Future<void>? _initFuture;

  @visibleForTesting
  static Future<String> Function() settingsFilePathResolver =
      LocalPaths.resolveSettingsFilePath;

  @visibleForTesting
  static void Function({
    required String message,
    Object? error,
    StackTrace? stackTrace,
  })
  logger = ({required String message, Object? error, StackTrace? stackTrace}) {
    dev.log(
      message,
      name: 'LocalSettingsStore',
      error: error,
      stackTrace: stackTrace,
    );
  };

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _initFuture = null;
    settingsFilePathResolver = LocalPaths.resolveSettingsFilePath;
    logger =
        ({required String message, Object? error, StackTrace? stackTrace}) {
          dev.log(
            message,
            name: 'LocalSettingsStore',
            error: error,
            stackTrace: stackTrace,
          );
        };
  }

  /// Creates `settings.json` with defaults when missing.
  ///
  /// Contract:
  /// - Never throws.
  /// - Safe and idempotent for repeated calls.
  static Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }

    final inFlight = _initFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _ensureInitializedInternal();
    _initFuture = future;
    return future;
  }

  static Future<void> _ensureInitializedInternal() async {
    try {
      final settingsPath = await settingsFilePathResolver();
      final file = File(settingsPath);
      if (await file.exists()) {
        _initialized = true;
        return;
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(_defaultSettingsJson, flush: true);
      _initialized = true;
    } catch (error, stackTrace) {
      logger(
        message:
            'Failed to initialize settings.json. Using in-memory defaults.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _initFuture = null;
    }
  }
}

const String _defaultSettingsJson =
    '{\n'
    '  "schema_version": 1,\n'
    '  "entry": {\n'
    '    "result_limit": 10,\n'
    '    "use_single_entry_as_home": false,\n'
    '    "expand_on_focus": true\n'
    '  },\n'
    '  "logging": {\n'
    '    "level_override": null\n'
    '  }\n'
    '}\n';
