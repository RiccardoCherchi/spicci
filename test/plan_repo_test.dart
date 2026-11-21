import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/db.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/data/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<Repo> open() async {
    final dir = await Directory.systemTemp.createTemp('spicci_plan');
    addTearDown(() => dir.delete(recursive: true));
    final db = await openAppDb(factory: databaseFactoryFfi, path: '${dir.path}/db.sqlite');
    addTearDown(db.close);
    return Repo(db);
  }

  final insurance = Scheduled(
    kind: 'PLAN',
    name: 'Car insurance',
    amountCents: 80000,
    freq: Freq.annual,
    fromDate: DateTime(2027, 3, 15),
    nextDue: DateTime(2027, 3, 15),
    categoryId: 5,
    accountId: 1,
  );

  test('a linked piggy bank fills monthly, pays the expense and the balance still matches the bank', () async {
    final repo = await open();
    final sid = await repo.saveScheduled(insurance);
    final potId = await repo.savePot(Pot(accountId: 1, name: 'Insurance', recurringId: sid));

    // 20 Nov, saving day 1: deposits left are Nov, Dec, Jan, Feb, Mar.
    final made = await repo.runAutoSaving(DateTime(2026, 11, 20), 1);
    expect(made.single.$2, 16000);
    expect(await repo.runAutoSaving(DateTime(2026, 11, 25), 1), isEmpty, reason: 'once a month');
    final balanceBefore = (await repo.balances())[1];
    expect(balanceBefore, 0, reason: 'setting money aside never changes the account balance');

    await repo.addPotMove(PotMove(potId: potId, date: DateTime(2027, 1, 1), amountCents: 64000));
    final s = (await repo.scheduled()).single;
    await repo.payScheduled(s, amountCents: 76000, date: DateTime(2027, 3, 15), accountId: 1);

    expect((await repo.balances())[1], -76000, reason: 'the real payment leaves the account');
    expect((await repo.potBalances())[potId], 80000 - 76000, reason: 'the pot paid it and keeps the change');
    final next = (await repo.scheduled()).single;
    expect(next.nextDue, DateTime(2028, 3, 15));
    expect(next.lastDate, DateTime(2027, 3, 15));
    expect((await repo.transactions()).single.recurringId, sid);
  });

  test('a one-off item is archived once paid; skipping records nothing', () async {
    final repo = await open();
    await repo.saveScheduled(
      Scheduled(
        kind: 'PLAN',
        name: 'Tuition',
        amountCents: 150000,
        freq: Freq.once,
        fromDate: DateTime(2026, 9, 1),
        nextDue: DateTime(2026, 9, 1),
        accountId: 1,
      ),
    );
    await repo.saveScheduled(insurance);
    final [tuition, ins] = await repo.scheduled();
    await repo.payScheduled(tuition, amountCents: 150000, date: DateTime(2026, 9, 1), accountId: 1);
    await repo.skipScheduled(ins);
    final [t2, i2] = await repo.scheduled();
    expect(t2.archivedAt, isNotNull);
    expect(i2.nextDue, DateTime(2028, 3, 15));
    expect(await repo.transactions(), hasLength(1));
  });

  test('spending from a piggy bank, editing and deleting the expense', () async {
    final repo = await open();
    final potId = await repo.savePot(const Pot(accountId: 1, name: 'Japan'));
    await repo.addPotMove(PotMove(potId: potId, date: DateTime(2026, 1, 1), amountCents: 50000));
    final t = Txn(date: DateTime(2026, 7, 1), amountCents: 12000, type: TxType.expense, accountId: 1, categoryId: 24);
    final id = await repo.insertTxn(t, potId: potId);
    expect((await repo.potBalances())[potId], 38000);
    expect(await repo.transactionPots(), {id: potId});

    await repo.updateTxn(t.copyWithId(id), potId: null);
    expect((await repo.potBalances())[potId], 50000, reason: 'unlinking gives the money back');
    await repo.updateTxn(t.copyWithId(id), potId: potId);
    await repo.deleteTxn(id);
    expect((await repo.potBalances())[potId], 50000);

    await repo.closePot(potId);
    expect((await repo.potBalances())[potId], 0, reason: 'closing returns the rest to free money');
  });
}
