import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/db.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/data/repo.dart';
import 'package:spicci/state.dart';
import 'package:spicci/ui/solar.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<Repo> openRepo({bool italian = false}) async {
    final db = await openAppDb(factory: databaseFactoryFfi, path: inMemoryDatabasePath, italian: italian);
    addTearDown(db.close);
    return Repo(db);
  }

  test('seed creates a main account and localized categories with known icons', () async {
    final repo = await openRepo(italian: true);
    expect((await repo.accounts()).single.isMain, isTrue);
    final cats = await repo.categories();
    expect(cats.map((c) => c.name), contains('Spesa'));
    expect(cats.where((c) => c.type == 'IN'), isNotEmpty);
    expect(cats.where((c) => c.parentId != null), isNotEmpty);
    expect(cats.map((c) => c.icon).where((i) => !categoryIcons.containsKey(i)), isEmpty);
  });

  test('groups the selected month by day and compares spending with last month', () async {
    final repo = await openRepo();
    Future<void> add(DateTime d, int cents, TxType type) =>
        repo.insertTxn(Txn(date: d, amountCents: cents, type: type, accountId: 1, categoryId: 1));
    await add(DateTime(2025, 3, 2, 9), 550, TxType.expense);
    await add(DateTime(2025, 3, 2, 18), 10000, TxType.income);
    await add(DateTime(2025, 3, 1, 12), 1250, TxType.expense);
    await add(DateTime(2025, 3, 1, 13), 3000, TxType.transfer);
    await add(DateTime(2025, 2, 1), 5000, TxType.expense);
    await add(DateTime(2025, 2, 20), 9999, TxType.expense);

    final container = ProviderContainer(overrides: [repoProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    container.read(selectedMonthProvider.notifier).set(DateTime(2025, 3));

    final groups = await container.read(dayGroupsProvider.future);
    expect(groups.map((g) => g.day.day), [2, 1]);
    expect(groups.first.totalCents, 9450);
    expect(groups.last.totalCents, -1250, reason: 'transfers are neutral');
    expect(groups.first.txns.first.amountCents, 10000, reason: 'newest first within a day');

    final stats = await container.read(monthStatsProvider.future);
    expect(stats.spentCents, 1800);
    expect(stats.incomeCents, 10000);
    expect(stats.cumulative.take(2), [1250, 1800]);
    expect(stats.previousCumulative.last, 14999);
    expect(stats.deltaCents, 1800 - 14999, reason: 'a past month is compared in full');
  });
}
