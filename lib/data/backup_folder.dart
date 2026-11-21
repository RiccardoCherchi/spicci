import 'package:flutter/services.dart';

import 'backup.dart';

/// A folder the user picks outside the app (for example iCloud Drive). Backups
/// written there survive deleting the app. Implemented in ios/Runner/AppDelegate.swift.
class BackupFolder {
  static const _channel = MethodChannel('spicci/backup_folder');

  /// How many daily copies to keep in the folder.
  static const keep = 30;

  /// Shows the folder picker; returns the folder name, or null when cancelled.
  Future<String?> pick() => _channel.invokeMethod<String>('pick');

  /// Name of the chosen folder, or null when none is set or it is no longer reachable.
  Future<String?> name() => _channel.invokeMethod<String>('name');

  Future<void> clear() => _channel.invokeMethod<void>('clear');

  Future<List<String>> list() async =>
      (await _channel.invokeListMethod<String>('list') ?? const []).where(isBackupName).toList()
        ..sort((a, b) => b.compareTo(a));

  Future<String?> read(String name) => _channel.invokeMethod<String>('read', {'name': name});

  /// Writes today's backup and prunes old ones.
  Future<void> write(String json, {DateTime? now}) async {
    await _channel.invokeMethod<void>('write', {'name': backupName(now ?? DateTime.now()), 'content': json});
    for (final old in (await list()).skip(keep)) {
      await _channel.invokeMethod<void>('delete', {'name': old});
    }
  }
}
