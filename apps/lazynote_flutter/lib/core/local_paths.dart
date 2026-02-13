import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// Centralized local runtime path resolver.
///
/// Path policy:
/// - Windows: `%APPDATA%/LazyLife/...`
/// - Non-Windows: `<app_support>/LazyLife/...`
class LocalPaths {
  static const String appRootFolderName = 'LazyLife';
  static const String logsFolderName = 'logs';
  static const String dataFolderName = 'data';
  static const String entryDbFileName = 'lazynote_entry.sqlite3';
  static const String settingsFileName = 'settings.json';

  @visibleForTesting
  static Future<Directory> Function() applicationSupportDirectoryResolver =
      getApplicationSupportDirectory;

  @visibleForTesting
  static Map<String, String> Function() environmentResolver = () =>
      Platform.environment;

  @visibleForTesting
  static String Function() operatingSystemResolver = () =>
      Platform.operatingSystem;

  @visibleForTesting
  static void resetForTesting() {
    applicationSupportDirectoryResolver = getApplicationSupportDirectory;
    environmentResolver = () => Platform.environment;
    operatingSystemResolver = () => Platform.operatingSystem;
  }

  /// Resolves the root path where LazyLife stores local runtime artifacts.
  static Future<String> resolveAppRootPath() async {
    final os = operatingSystemResolver();
    if (os == 'windows') {
      final appData = environmentResolver()['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return _joinPath(appData, appRootFolderName);
      }
    }

    final supportDir = await applicationSupportDirectoryResolver();
    return _joinPath(supportDir.path, appRootFolderName);
  }

  /// Resolves absolute path to rolling logs directory.
  static Future<String> resolveLogDirPath() async {
    final root = await resolveAppRootPath();
    return _joinPath(root, logsFolderName);
  }

  /// Resolves absolute path to entry database file.
  static Future<String> resolveEntryDbPath() async {
    final root = await resolveAppRootPath();
    final dataDir = _joinPath(root, dataFolderName);
    return _joinPath(dataDir, entryDbFileName);
  }

  /// Resolves absolute path to local settings JSON file.
  static Future<String> resolveSettingsFilePath() async {
    final root = await resolveAppRootPath();
    return _joinPath(root, settingsFileName);
  }
}

String _joinPath(String base, String leaf) {
  final trimmedBase = base.trim();
  final separator = Platform.pathSeparator;
  if (trimmedBase.endsWith(separator)) {
    return '$trimmedBase$leaf';
  }
  return '$trimmedBase$separator$leaf';
}
