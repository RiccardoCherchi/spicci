import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/backup.dart';
import 'package:spicci/data/db.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/data/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  // Separate files: in-memory paths would hand back the same shared instance.
  var n = 0;
  Future<Repo> open() async {
    final dir = await Directory.systemTemp.createTemp('spicci_db');
    addTearDown(() => dir.delete(recursive: true));
    final db = await openAppDb(factory: databaseFactoryFfi, path: '${dir.path}/db${n++}.sqlite');
    addTearDown(db.close);
    return Repo(db);
  }

  test('export then restore gives back the same data', () async {
    final source = await open();
    await source.insertTxn(
      Txn(
        date: DateTime(2025, 3, 1, 9),
        amountCents: 1250,
        type: TxType.expense,
        accountId: 1,
        categoryId: 2,
        note: '007',
      ),
      tags: ['casa'],
    );
    await source.savePreset(const Preset(label: 'Terea', amountCents: 550, accountId: 1, categoryId: 2));
    final json = await exportJson(source.db);

    final target = await open();
    await target.insertTxn(Txn(date: DateTime(2020), amountCents: 1, type: TxType.income, accountId: 1));
    await restoreBackup(target.db, parseBackup(json));

    expect(identical(source.db, target.db), isFalse);
    final txn = (await target.transactions()).single;
    expect(txn.amountCents, 1250);
    expect(txn.note, '007');
    expect((await target.transactionTags())[txn.id], ['casa']);
    expect((await target.presets()).single.label, 'Terea');
    expect((await target.categories()).length, (await source.categories()).length);
  });

  test('unknown columns are ignored and newer versions rejected', () async {
    final repo = await open();
    final data = jsonDecode(await exportJson(repo.db)) as Map<String, dynamic>;
    (data['tables']['accounts'] as List).first['future_column'] = 'x';
    await restoreBackup(repo.db, parseBackup(jsonEncode(data)));
    expect((await repo.accounts()).single.name, 'Main account');

    data['version'] = backupVersion + 1;
    expect(() => parseBackup(jsonEncode(data)), throwsA(isA<BackupException>()));
  });

  test('rejects files that are not Spicci backups', () {
    expect(() => parseBackup('nope'), throwsA(isA<BackupException>()));
    expect(() => parseBackup('{"app":"other","tables":{}}'), throwsA(isA<BackupException>()));
    expect(() => parseBackup('{"app":"spicci","version":1,"tables":{"accounts":[]}}'), throwsA(isA<BackupException>()));
  });

  test('auto backup writes one file per day and keeps the newest', () async {
    final repo = await open();
    final dir = await Directory.systemTemp.createTemp('spicci');
    addTearDown(() => dir.delete(recursive: true));
    final auto = AutoBackup(dir, keep: 3);
    for (var d = 1; d <= 5; d++) {
      await auto.run(repo.db, now: DateTime(2025, 3, d));
    }
    await auto.run(repo.db, now: DateTime(2025, 3, 5, 18));
    expect(auto.list().map((f) => f.uri.pathSegments.last), [
      'spicci-2025-03-05.json',
      'spicci-2025-03-04.json',
      'spicci-2025-03-03.json',
    ]);
  });
}
