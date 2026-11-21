import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db.dart';

const backupVersion = 1;

/// Insert order, so rows always come after the rows they reference.
const _insertOrder = [
  'accounts',
  'categories',
  'transactions',
  'recurring',
  'budgets',
  'tags',
  'transaction_tags',
  'presets',
  'pots',
  'pot_moves',
];

/// One file per day; sorting names newest first sorts them by date.
String backupName(DateTime day) => 'spicci-${day.toIso8601String().substring(0, 10)}.json';

final _backupName = RegExp(r'^spicci-\d{4}-\d{2}-\d{2}\.json$');
bool isBackupName(String name) => _backupName.hasMatch(name);

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A parsed backup: table name to rows, using the database column names.
class Backup {
  Backup(this.tables, this.exportedAt);
  final Map<String, List<Map<String, Object?>>> tables;
  final DateTime? exportedAt;

  int count(String table) => tables[table]?.length ?? 0;
}

Future<String> exportJson(Database db) async {
  final tables = {for (final t in _insertOrder) t: await db.query(t)};
  return const JsonEncoder.withIndent(' ').convert({
    'app': 'spicci',
    'version': backupVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'tables': tables,
  });
}

Backup parseBackup(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw BackupException('Not a Spicci backup: invalid JSON.');
  }
  if (root is! Map || root['app'] != 'spicci' || root['tables'] is! Map) {
    throw BackupException('Not a Spicci backup.');
  }
  final version = root['version'];
  if (version is! int || version > backupVersion) {
    throw BackupException('This backup comes from a newer version of Spicci.');
  }
  final raw = root['tables'] as Map;
  final tables = <String, List<Map<String, Object?>>>{};
  for (final t in _insertOrder) {
    final rows = raw[t] ?? const [];
    if (rows is! List || rows.any((r) => r is! Map)) throw BackupException('Table "$t" is malformed.');
    tables[t] = [for (final r in rows) Map<String, Object?>.from(r as Map)];
  }
  if (tables['accounts']!.isEmpty) throw BackupException('The backup has no accounts.');
  return Backup(tables, DateTime.tryParse(root['exportedAt'] as String? ?? ''));
}

/// Replaces all data with [backup] in one transaction. Columns the current
/// schema does not know are dropped, so older or newer backups still load.
Future<void> restoreBackup(Database db, Backup backup) => db.transaction((txn) async {
  for (final t in dataTables) {
    await txn.delete(t);
  }
  for (final t in _insertOrder) {
    final columns = {for (final c in await txn.rawQuery('PRAGMA table_info($t)')) c['name'] as String};
    final batch = txn.batch();
    for (final row in backup.tables[t]!) {
      batch.insert(t, {
        for (final e in row.entries)
          if (columns.contains(e.key)) e.key: e.value,
      });
    }
    await batch.commit(noResult: true);
  }
});

/// Daily copies in a folder the Files app can see, keeping the newest [keep].
class AutoBackup {
  AutoBackup(this.dir, {this.keep = 10});
  final Directory dir;
  final int keep;

  List<File> list() {
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) => isBackupName(p.basename(f.path))).toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
  }

  /// Writes today's backup (overwriting an earlier one from today) and prunes old ones.
  Future<File> run(Database db, {DateTime? now}) async {
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, backupName(now ?? DateTime.now())));
    await file.writeAsString(await exportJson(db), flush: true);
    for (final old in list().skip(keep)) {
      await old.delete();
    }
    return file;
  }
}
