import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/core/settings/local_settings_store.dart';

void main() {
  tearDown(() {
    LocalSettingsStore.resetForTesting();
  });

  test('creates default settings.json when missing', () async {
    final tempDir = await Directory.systemTemp.createTemp('lazynote-settings-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final settingsPath =
        '${tempDir.path}${Platform.pathSeparator}settings.json';
    LocalSettingsStore.settingsFilePathResolver = () async => settingsPath;

    await LocalSettingsStore.ensureInitialized();

    final file = File(settingsPath);
    expect(await file.exists(), isTrue);
    final content = await file.readAsString();
    expect(content, contains('"schema_version": 1'));
    expect(content, contains('"result_limit": 10'));
    expect(content, contains('"use_single_entry_as_home": false'));
  });

  test('does not overwrite existing settings file', () async {
    final tempDir = await Directory.systemTemp.createTemp('lazynote-settings-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final settingsPath =
        '${tempDir.path}${Platform.pathSeparator}settings.json';
    final existing = File(settingsPath);
    await existing.parent.create(recursive: true);
    await existing.writeAsString('{"schema_version": 1, "custom": true}');

    LocalSettingsStore.settingsFilePathResolver = () async => settingsPath;
    await LocalSettingsStore.ensureInitialized();

    final content = await existing.readAsString();
    expect(content, '{"schema_version": 1, "custom": true}');
  });
}
