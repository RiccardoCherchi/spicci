import 'package:collection/collection.dart';

import '../data/models.dart';

/// A month or a whole year.
class Period {
  const Period.month(this.start) : isYear = false;
  const Period.year(this.start) : isYear = true;

  final DateTime start;
  final bool isYear;

  DateTime get end => isYear ? DateTime(start.year + 1) : DateTime(start.year, start.month + 1);
  Period get previous =>
      isYear ? Period.year(DateTime(start.year - 1)) : Period.month(DateTime(start.year, start.month - 1));
  Period get next =>
      isYear ? Period.year(DateTime(start.year + 1)) : Period.month(DateTime(start.year, start.month + 1));
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  @override
  bool operator ==(Object other) => other is Period && other.start == start && other.isYear == isYear;
  @override
  int get hashCode => Object.hash(start, isYear);
}

class Totals {
  const Totals(this.incomeCents, this.expenseCents);
  final int incomeCents;
  final int expenseCents;
  int get netCents => incomeCents - expenseCents;

  /// Share of income not spent, or null without income.
  double? get savingsRate => incomeCents == 0 ? null : netCents / incomeCents;
}

Totals totals(Iterable<Txn> txns, Period p) {
  var (income, expense) = (0, 0);
  for (final t in txns) {
    if (!p.contains(t.date)) continue;
    if (t.type == TxType.income) income += t.amountCents;
    if (t.type == TxType.expense) expense += t.amountCents;
  }
  return Totals(income, expense);
}

class CategoryShare {
  CategoryShare(this.categoryId, this.cents, this.previousCents, this.children);

  /// Null collects uncategorised expenses.
  final int? categoryId;
  final int cents;
  final int previousCents;

  /// Per subcategory (or the parent itself when spent directly on it).
  final Map<int?, int> children;
}

/// Expenses per top-level category, largest first, with the previous period for comparison.
/// While [p] is still running (it contains [now]), the previous period is cut at
/// the same point, so half a month is never compared with a whole one.
List<CategoryShare> categoryBreakdown(Iterable<Txn> txns, Period p, Map<int, Category> categories, {DateTime? now}) {
  int? root(int? id) {
    final c = categories[id];
    return c == null ? null : (c.parentId ?? c.id);
  }

  final current = <int?, int>{}, before = <int?, int>{}, children = <int?, Map<int?, int>>{};
  final prev = p.previous;
  final prevEnd = now != null && p.contains(now) ? prev.start.add(now.difference(p.start)) : prev.end;
  for (final t in txns.where((t) => t.type == TxType.expense)) {
    final r = root(t.categoryId);
    if (p.contains(t.date)) {
      current.update(r, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
      children.putIfAbsent(r, () => {}).update(t.categoryId, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
    } else if (prev.contains(t.date) && t.date.isBefore(prevEnd)) {
      before.update(r, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
    }
  }
  return [
    for (final e in current.entries) CategoryShare(e.key, e.value, before[e.key] ?? 0, children[e.key]!),
  ].sortedBy<num>((s) => -s.cents);
}

/// Income and expenses for each of the [count] months ending with [last].
List<(DateTime, Totals)> monthlySeries(Iterable<Txn> txns, DateTime last, {int count = 12}) => [
  for (var i = count - 1; i >= 0; i--)
    () {
      final m = DateTime(last.year, last.month - i);
      return (m, totals(txns, Period.month(m)));
    }(),
];

/// Net worth at the end of each of the [count] months ending with [last]:
/// [current] minus everything that happened after each month end.
List<(DateTime, int)> netWorthSeries(Iterable<Txn> txns, int current, DateTime last, {int count = 12}) {
  final sorted = txns.sortedBy((t) => t.date).reversed.toList();
  final out = <(DateTime, int)>[];
  var value = current, i = 0;
  for (var k = 0; k < count; k++) {
    final m = DateTime(last.year, last.month - k);
    final end = DateTime(m.year, m.month + 1);
    while (i < sorted.length && !sorted[i].date.isBefore(end)) {
      value -= sorted[i].signedCents;
      i++;
    }
    out.add((m, value));
  }
  return out.reversed.toList();
}

/// Expected expenses for the whole month at the current daily pace, or null
/// when [now] is not inside [month].
int? monthProjection(Iterable<Txn> txns, DateTime month, DateTime now) {
  final p = Period.month(month);
  if (!p.contains(now)) return null;
  final spent = totals(txns, p).expenseCents;
  final days = DateTime(month.year, month.month + 1, 0).day;
  return (spent / now.day * days).round();
}

List<Txn> largestExpenses(Iterable<Txn> txns, Period p, {int count = 5}) => txns
    .where((t) => t.type == TxType.expense && p.contains(t.date))
    .sortedBy<num>((t) => -t.amountCents)
    .take(count)
    .toList();
