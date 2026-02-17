import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:lazynote_flutter/core/local_paths.dart';

/// Ensures local settings file exists at a stable path.
class LocalSettingsStore {
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static EntryUiTuning _entryUiTuning = const EntryUiTuning.defaults();
  static String? _loggingLevelOverride;

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

  /// Resets all static state for test isolation.
  /// IMPORTANT: any new static field added to this class MUST be reset here.
  /// Current fields:
  /// _initialized, _initFuture, _entryUiTuning, _loggingLevelOverride,
  /// settingsFilePathResolver, logger.
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _initFuture = null;
    _entryUiTuning = const EntryUiTuning.defaults();
    _loggingLevelOverride = null;
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

  /// Effective Single Entry UI tuning values loaded from local settings.
  static EntryUiTuning get entryUiTuning => _entryUiTuning;

  /// Raw logging level override parsed from settings file.
  ///
  /// v0.1 contract:
  /// - This value is persisted and validated.
  /// - Runtime logging behavior is not changed by this field yet.
  static String? get loggingLevelOverride => _loggingLevelOverride;

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
        await _backfillMissingDefaults(file);
        await _loadRuntimeSettings(file);
        _initialized = true;
        return;
      }

      await _writeFileWithTempReplace(file, _defaultSettingsJson);
      await _loadRuntimeSettings(file);
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

/// Runtime-tunable UI values for unified Single Entry panel.
class EntryUiTuning {
  const EntryUiTuning({
    required this.collapsedHeight,
    required this.expandedMaxHeight,
    required this.animationMs,
  });

  const EntryUiTuning.defaults()
    : collapsedHeight = 72.0,
      expandedMaxHeight = 420.0,
      animationMs = 180;

  final double collapsedHeight;
  final double expandedMaxHeight;
  final int animationMs;
}

Future<void> _loadRuntimeSettings(File file) async {
  try {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final entry = decoded['entry'];
    if (entry is! Map<String, dynamic>) {
      return;
    }

    final ui = entry['ui'];
    if (ui is! Map<String, dynamic>) {
      return;
    }

    final collapsed = _readDouble(
      ui['collapsed_height'],
      fallback: 72.0,
      min: 48.0,
      max: 160.0,
    );
    final expanded = _readDouble(
      ui['expanded_max_height'],
      fallback: 420.0,
      min: 220.0,
      max: 720.0,
    );
    final animationMs = _readInt(
      ui['animation_ms'],
      fallback: 180,
      min: 80,
      max: 500,
    );

    LocalSettingsStore._entryUiTuning = EntryUiTuning(
      collapsedHeight: collapsed,
      expandedMaxHeight: expanded >= collapsed + 80 ? expanded : collapsed + 80,
      animationMs: animationMs,
    );

    final logging = decoded['logging'];
    if (logging is Map<String, dynamic>) {
      final levelOverride = _readLoggingLevelOverride(
        logging['level_override'],
      );
      LocalSettingsStore._loggingLevelOverride = levelOverride;
    } else {
      LocalSettingsStore._loggingLevelOverride = null;
    }
  } catch (error, stackTrace) {
    LocalSettingsStore.logger(
      message:
          'Failed to parse runtime settings (entry.ui/logging); falling back to defaults.',
      error: error,
      stackTrace: stackTrace,
    );
    LocalSettingsStore._entryUiTuning = const EntryUiTuning.defaults();
    LocalSettingsStore._loggingLevelOverride = null;
  }
}

Future<void> _backfillMissingDefaults(File file) async {
  try {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    var changed = false;

    if (!decoded.containsKey('schema_version')) {
      decoded['schema_version'] = 1;
      changed = true;
    }

    if (decoded['entry'] is! Map<String, dynamic>) {
      decoded['entry'] = <String, dynamic>{};
      changed = true;
    }
    final entry = decoded['entry'] as Map<String, dynamic>;

    if (!entry.containsKey('result_limit')) {
      entry['result_limit'] = 10;
      changed = true;
    }
    if (!entry.containsKey('use_single_entry_as_home')) {
      entry['use_single_entry_as_home'] = false;
      changed = true;
    }
    if (!entry.containsKey('expand_on_focus')) {
      entry['expand_on_focus'] = true;
      changed = true;
    }

    if (entry['ui'] is! Map<String, dynamic>) {
      entry['ui'] = <String, dynamic>{};
      changed = true;
    }
    final ui = entry['ui'] as Map<String, dynamic>;
    if (!ui.containsKey('collapsed_height')) {
      ui['collapsed_height'] = 72;
      changed = true;
    }
    if (!ui.containsKey('expanded_max_height')) {
      ui['expanded_max_height'] = 420;
      changed = true;
    }
    if (!ui.containsKey('animation_ms')) {
      ui['animation_ms'] = 180;
      changed = true;
    }

    if (decoded['logging'] is! Map<String, dynamic>) {
      decoded['logging'] = <String, dynamic>{};
      changed = true;
    }
    final logging = decoded['logging'] as Map<String, dynamic>;
    if (!logging.containsKey('level_override')) {
      logging['level_override'] = null;
      changed = true;
    }

    if (!changed) {
      return;
    }

    const encoder = JsonEncoder.withIndent('  ');
    await _writeFileWithTempReplace(file, '${encoder.convert(decoded)}\n');
  } catch (error, stackTrace) {
    LocalSettingsStore.logger(
      message:
          'Failed to backfill missing settings keys; keeping existing file.',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

String? _readLoggingLevelOverride(Object? value) {
  if (value == null) {
    return null;
  }
  final normalized = switch (value) {
    String v => v.trim().toLowerCase(),
    _ => '',
  };
  return switch (normalized) {
    'trace' || 'debug' || 'info' || 'warn' || 'error' => normalized,
    _ => null,
  };
}

Future<void> _writeFileWithTempReplace(File target, String content) async {
  await target.parent.create(recursive: true);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final temp = File('${target.path}.tmp.$timestamp');
  await temp.writeAsString(content, flush: true);

  try {
    // Why: on POSIX, rename-over-existing is typically atomic; keep this fast
    // path first and fall back to replace semantics for platforms that reject
    // rename when destination already exists.
    await temp.rename(target.path);
    return;
  } catch (_) {
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }
}

double _readDouble(
  Object? value, {
  required double fallback,
  required double min,
  required double max,
}) {
  final parsed = switch (value) {
    int v => v.toDouble(),
    double v => v,
    String v => double.tryParse(v),
    _ => null,
  };
  if (parsed == null) {
    return fallback;
  }
  return parsed.clamp(min, max).toDouble();
}

int _readInt(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = switch (value) {
    int v => v,
    String v => int.tryParse(v),
    _ => null,
  };
  if (parsed == null) {
    return fallback;
  }
  return parsed.clamp(min, max).toInt();
}

const String _defaultSettingsJson =
    '{\n'
    '  "schema_version": 1,\n'
    '  "entry": {\n'
    '    "result_limit": 10,\n'
    '    "use_single_entry_as_home": false,\n'
    '    "expand_on_focus": true,\n'
    '    "ui": {\n'
    '      "collapsed_height": 72,\n'
    '      "expanded_max_height": 420,\n'
    '      "animation_ms": 180\n'
    '    }\n'
    '  },\n'
    '  "logging": {\n'
    '    "level_override": null\n'
    '  }\n'
    '}\n';
