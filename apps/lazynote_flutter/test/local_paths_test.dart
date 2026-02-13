import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/local_paths.dart';

void main() {
  tearDown(() {
    LocalPaths.resetForTesting();
  });

  test('resolves Windows app root under APPDATA/LazyLife', () async {
    LocalPaths.operatingSystemResolver = () => 'windows';
    LocalPaths.environmentResolver = () => <String, String>{
      'APPDATA': r'C:\Users\tester\AppData\Roaming',
    };
    LocalPaths.applicationSupportDirectoryResolver = () async =>
        Directory.systemTemp;

    final root = await LocalPaths.resolveAppRootPath();
    final logDir = await LocalPaths.resolveLogDirPath();
    final settingsPath = await LocalPaths.resolveSettingsFilePath();

    expect(root, endsWith(r'AppData\Roaming\LazyLife'));
    expect(logDir, endsWith(r'AppData\Roaming\LazyLife\logs'));
    expect(settingsPath, endsWith(r'AppData\Roaming\LazyLife\settings.json'));
  });

  test(
    'falls back to app-support/LazyLife when APPDATA is unavailable',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp('lazynote-paths-');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      LocalPaths.operatingSystemResolver = () => 'windows';
      LocalPaths.environmentResolver = () => <String, String>{};
      LocalPaths.applicationSupportDirectoryResolver = () async => tempRoot;

      final root = await LocalPaths.resolveAppRootPath();
      expect(root, '${tempRoot.path}${Platform.pathSeparator}LazyLife');
    },
  );
}
