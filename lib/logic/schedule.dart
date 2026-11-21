import 'dart:math';

import '../data/models.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

/// The occurrence after [date]. Monthly steps keep [anchorDay], clamped to
/// short months, so Jan 31 goes to Feb 28 and then back to Mar 31.
DateTime advance(DateTime date, Freq f, int anchorDay) {
  if (f.days > 0) return _day(date).add(Duration(days: f.days));
  final months = date.month + f.months;
  final year = date.year + (months - 1) ~/ 12;
  final month = (months - 1) % 12 + 1;
  return DateTime(year, month, min(anchorDay, _daysIn(year, month)));
}

/// First occurrence after [last] (or [from] itself when nothing was paid yet).
DateTime nextOccurrence(DateTime from, Freq f, DateTime? last) {
  var d = _day(from);
  if (last == null || f == Freq.once) return d;
  while (!d.isAfter(_day(last))) {
    d = advance(d, f, from.day);
  }
  return d;
}

/// Next due date once the current one is paid or skipped; null when it ends.
DateTime? following(Scheduled s) {
  if (s.freq == Freq.once) return null;
  final next = advance(s.nextDue, s.freq, s.fromDate.day);
  return s.toDate != null && next.isAfter(s.toDate!) ? null : next;
}

/// Items waiting for confirmation: due today or earlier and not snoozed.
bool isPending(Scheduled s, DateTime now) =>
    s.archivedAt == null &&
    !_day(s.nextDue).isAfter(_day(now)) &&
    (s.snoozeUntil == null || !s.snoozeUntil!.isAfter(now));

/// Average yearly cost of a repeating item.
int yearlyCents(Scheduled s) => (s.amountCents * s.freq.perYear).round();

/// The saving day in a given month, clamped to short months.
DateTime savingDate(int year, int month, int savingDay) => DateTime(year, month, min(savingDay, _daysIn(year, month)));

/// How many automatic deposits are still possible before [due]: one per month
/// on [savingDay], from this month (unless this month's is done) to the due date.
int depositsLeft(DateTime now, DateTime due, int savingDay, {required bool doneThisMonth}) {
  var count = 0;
  final last = DateTime(due.year, due.month);
  for (var m = DateTime(now.year, now.month); !m.isAfter(last); m = DateTime(m.year, m.month + 1)) {
    if (doneThisMonth && m.year == now.year && m.month == now.month) continue;
    if (!savingDate(m.year, m.month, savingDay).isAfter(_day(due))) count++;
  }
  return max(count, 1);
}

/// Amount to put aside each month to reach [targetCents] by [due].
int monthlyQuota({
  required int targetCents,
  required int savedCents,
  required DateTime now,
  required DateTime due,
  required int savingDay,
  required bool doneThisMonth,
}) {
  final missing = targetCents - savedCents;
  if (missing <= 0) return 0;
  final n = depositsLeft(now, due, savingDay, doneThisMonth: doneThisMonth);
  return (missing / n).ceil();
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
