import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/logic/analysis.dart';

Txn _t(DateTime d, int cents, TxType type, {int? cat, String? note}) =>
    Txn(date: d, amountCents: cents, type: type, accountId: 1, categoryId: cat, note: note);

void main() {
  final categories = {
    1: const Category(id: 1, name: 'Food', type: 'OUT'),
    2: const Category(id: 2, name: 'Groceries', type: 'OUT', parentId: 1),
    3: const Category(id: 3, name: 'Home', type: 'OUT'),
  };
  final txns = [
    _t(DateTime(2026, 11, 3), 200000, TxType.income),
    _t(DateTime(2026, 11, 4), 3000, TxType.expense, cat: 2),
    _t(DateTime(2026, 11, 5), 1000, TxType.expense, cat: 1),
    _t(DateTime(2026, 11, 6), 50000, TxType.expense, cat: 3),
    _t(DateTime(2026, 11, 7), 999, TxType.expense),
    _t(DateTime(2026, 11, 8), 7000, TxType.transfer),
    _t(DateTime(2026, 10, 10), 2500, TxType.expense, cat: 2),
  ];
  final nov = Period.month(DateTime(2026, 11));

  test('totals ignore transfers and give the savings rate', () {
    final t = totals(txns, nov);
    expect(t.incomeCents, 200000);
    expect(t.expenseCents, 54999);
    expect(t.savingsRate, closeTo(0.725, 0.001));
    expect(totals(txns, Period.month(DateTime(2026, 9))).savingsRate, isNull);
  });

  test('breakdown groups subcategories under the parent, largest first', () {
    final b = categoryBreakdown(txns, nov, categories);
    expect(b.map((s) => s.categoryId), [3, 1, null]);
    final food = b[1];
    expect(food.cents, 4000);
    expect(food.previousCents, 2500);
    expect(food.children, {2: 3000, 1: 1000});

    // On 5 November, October counts only up to 5 October, so the 10 October expense is left out.
    final early = categoryBreakdown(txns, nov, categories, now: DateTime(2026, 11, 5, 12));
    expect(early.firstWhere((s) => s.categoryId == 1).previousCents, 0);
  });

  test('monthly series and net worth going back from today', () {
    final series = monthlySeries(txns, DateTime(2026, 11), count: 3);
    expect(series.map((e) => e.$1.month), [9, 10, 11]);
    expect(series.last.$2.expenseCents, 54999);

    // 1000.00 today; November added +1450.01, October -25.
    final worth = netWorthSeries(txns, 100000, DateTime(2026, 11), count: 3);
    expect(worth.map((e) => e.$2), [100000 - 145001 + 2500, 100000 - 145001, 100000]);
  });

  test('projection only for the current month', () {
    expect(monthProjection(txns, DateTime(2026, 11), DateTime(2026, 11, 15)), (54999 / 15 * 30).round());
    expect(monthProjection(txns, DateTime(2026, 10), DateTime(2026, 11, 15)), isNull);
  });

  test('periods move by month or year', () {
    expect(nov.previous, Period.month(DateTime(2026, 10)));
    expect(Period.year(DateTime(2026)).next.start, DateTime(2027));
    expect(Period.month(DateTime(2026, 1)).previous.start, DateTime(2025, 12));
  });

  test('largest expenses', () {
    expect(largestExpenses(txns, nov, count: 2).map((t) => t.amountCents), [50000, 3000]);
  });
}
