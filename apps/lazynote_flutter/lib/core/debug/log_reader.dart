import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:lazynote_flutter/core/local_paths.dart';

/// Metadata for a discovered local log file.
class DebugLogFile {
  const DebugLogFile({
    required this.name,
    required this.path,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  /// File name shown in diagnostics UI.
  final String name;

  /// Absolute file path on local machine.
  final String path;

  /// Last modification time.
  final DateTime modifiedAt;

  /// File size in bytes.
  final int sizeBytes;
}

/// Snapshot of readable local log state for diagnostics UI.
class DebugLogSnapshot {
  const DebugLogSnapshot({
    required this.logDir,
    required this.files,
    required this.activeFile,
    required this.tailText,
    this.warningMessage,
  });

  /// Absolute log directory used by Rust logging.
  final String logDir;

  /// Discovered rolling log files ordered by modified time (newest first).
  final List<DebugLogFile> files;

  /// Currently displayed file.
  final DebugLogFile? activeFile;

  /// Tail text extracted from [activeFile].
  final String tailText;

  /// Non-fatal warning message shown to developers.
  final String? warningMessage;
}

/// Reads local rolling logs for developer diagnostics.
class LogReader {
  @visibleForTesting
  static Future<String> Function() logDirPathResolver =
      LocalPaths.resolveLogDirPath;

  @visibleForTesting
  static Future<ProcessResult> Function(String executable, List<String> args)
  processRunner = Process.run;

  @visibleForTesting
  static Future<void> Function(String path) ensureDirectoryExists =
      (String path) async {
        final directory = Directory(path);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      };

  @visibleForTesting
  static Future<List<File>> Function(Directory directory) fileEnumerator =
      _defaultFileEnumerator;

  @visibleForTesting
  static Future<String> Function(File file) fileReader = (File file) =>
      file.readAsString();

  @visibleForTesting
  static void resetForTesting() {
    logDirPathResolver = LocalPaths.resolveLogDirPath;
    processRunner = Process.run;
    ensureDirectoryExists = (String path) async {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    };
    fileEnumerator = _defaultFileEnumerator;
    fileReader = (File file) => file.readAsString();
  }

  /// Resolves absolute log directory path used by Rust logging.
  static Future<String> resolveLogDirPath() => logDirPathResolver();

  /// Reads newest rolling log file and returns tail lines.
  static Future<DebugLogSnapshot> readLatestTail({int maxLines = 200}) async {
    final logDir = await resolveLogDirPath();
    await ensureDirectoryExists(logDir);
    final directory = Directory(logDir);

    final files = await fileEnumerator(directory);
    if (files.isEmpty) {
      return DebugLogSnapshot(
        logDir: logDir,
        files: const [],
        activeFile: null,
        tailText: '',
        warningMessage: 'No log files found yet.',
      );
    }

    final discovered = <DebugLogFile>[];
    for (final file in files) {
      final stat = await file.stat();
      discovered.add(
        DebugLogFile(
          name: _fileName(file),
          path: file.path,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }

    discovered.sort((left, right) {
      final time = right.modifiedAt.compareTo(left.modifiedAt);
      if (time != 0) {
        return time;
      }
      return left.name.compareTo(right.name);
    });

    final activeFile = discovered.first;
    final activeText = await fileReader(File(activeFile.path));
    final tailText = _tailLines(activeText, maxLines);
    return DebugLogSnapshot(
      logDir: logDir,
      files: discovered,
      activeFile: activeFile,
      tailText: tailText,
    );
  }

  /// Opens log folder in platform file explorer.
  static Future<void> openLogFolder(String logDir) async {
    if (logDir.trim().isEmpty) {
      throw ArgumentError('logDir cannot be empty');
    }

    final command = switch (Platform.operatingSystem) {
      'windows' => 'explorer.exe',
      'macos' => 'open',
      _ => 'xdg-open',
    };
    final result = await processRunner(command, [logDir]);
    if (Platform.isWindows) {
      // Why: `explorer.exe` can return non-zero even on success, so exit code
      // alone is not a reliable signal. Treat explicit stderr output or a
      // missing target directory as failure to avoid false success messages.
      if (result.exitCode == 0) {
        return;
      }

      final stderrText = result.stderr.toString().trim();
      if (stderrText.isNotEmpty) {
        throw ProcessException(
          command,
          [logDir],
          'failed to open log folder: $stderrText',
          result.exitCode,
        );
      }

      final directoryExists = await Directory(logDir).exists();
      if (!directoryExists) {
        throw ProcessException(
          command,
          [logDir],
          'failed to open log folder: directory does not exist',
          result.exitCode,
        );
      }
      return;
    }

    if (result.exitCode != 0) {
      throw ProcessException(
        command,
        [logDir],
        'failed to open log folder: ${result.stderr}',
        result.exitCode,
      );
    }
  }
}

Future<List<File>> _defaultFileEnumerator(Directory directory) async {
  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final name = _fileName(entity).toLowerCase();
    if (name.startsWith('lazynote')) {
      files.add(entity);
    }
  }
  return files;
}

String _tailLines(String content, int maxLines) {
  if (content.isEmpty || maxLines <= 0) {
    return '';
  }

  final lines = const LineSplitter().convert(content);
  if (lines.length <= maxLines) {
    return lines.join('\n');
  }
  return lines.sublist(lines.length - maxLines).join('\n');
}

String _fileName(File file) {
  final segments = file.uri.pathSegments;
  if (segments.isEmpty) {
    return file.path;
  }
  return segments.last;
}
