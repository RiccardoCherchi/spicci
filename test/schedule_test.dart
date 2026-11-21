import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/logic/schedule.dart';

Scheduled _s({
  Freq freq = Freq.monthly,
  DateTime? from,
  DateTime? next,
  DateTime? to,
  DateTime? snooze,
  int amount = 1000,
}) => Scheduled(
  kind: 'SUB',
  name: 'x',
  amountCents: amount,
  freq: freq,
  fromDate: from ?? DateTime(2025, 1, 31),
  nextDue: next ?? from ?? DateTime(2025, 1, 31),
  toDate: to,
  snoozeUntil: snooze,
  accountId: 1,
);

void main() {
  test('monthly steps keep the anchor day through short months', () {
    var d = DateTime(2025, 1, 31);
    final seen = <DateTime>[];
    for (var i = 0; i < 3; i++) {
      d = advance(d, Freq.monthly, 31);
      seen.add(d);
    }
    expect(seen, [DateTime(2025, 2, 28), DateTime(2025, 3, 31), DateTime(2025, 4, 30)]);
    expect(advance(DateTime(2025, 11, 15), Freq.quarterly, 15), DateTime(2026, 2, 15));
    expect(advance(DateTime(2025, 3, 1), Freq.weekly, 1), DateTime(2025, 3, 8));
  });

  test('next occurrence after the last payment, first one included', () {
    final from = DateTime(2025, 1, 10);
    expect(nextOccurrence(from, Freq.monthly, null), from, reason: 'the first occurrence is never lost');
    expect(nextOccurrence(from, Freq.monthly, DateTime(2025, 3, 10)), DateTime(2025, 4, 10));
    expect(nextOccurrence(from, Freq.annual, DateTime(2025, 6, 1)), DateTime(2026, 1, 10));
  });

  test('following ends one-off items and respects the end date', () {
    expect(following(_s(freq: Freq.once)), isNull);
    expect(following(_s(next: DateTime(2025, 2, 28))), DateTime(2025, 3, 31));
    expect(following(_s(next: DateTime(2025, 2, 28), to: DateTime(2025, 3, 1))), isNull);
  });

  test('pending when due and not snoozed', () {
    final now = DateTime(2025, 3, 10, 12);
    expect(isPending(_s(next: DateTime(2025, 3, 10)), now), isTrue);
    expect(isPending(_s(next: DateTime(2025, 3, 11)), now), isFalse);
    expect(isPending(_s(next: DateTime(2025, 3, 1), snooze: DateTime(2025, 3, 11)), now), isFalse);
  });

  test('yearly cost', () {
    expect(yearlyCents(_s(amount: 1399)), 16788);
    expect(yearlyCents(_s(freq: Freq.semester, amount: 40000)), 80000);
    expect(yearlyCents(_s(freq: Freq.once)), 0);
  });

  test('monthly quota spreads what is missing over the deposits left', () {
    // Insurance of 800 due on 15 March; saving on the 1st; it is 20 November.
    final now = DateTime(2026, 11, 20);
    final due = DateTime(2027, 3, 15);
    expect(depositsLeft(now, due, 1, doneThisMonth: false), 5, reason: 'Nov, Dec, Jan, Feb, Mar');
    expect(depositsLeft(now, due, 1, doneThisMonth: true), 4);
    expect(depositsLeft(now, due, 20, doneThisMonth: true), 3, reason: 'saving on 20 March is after the due date');
    expect(
      monthlyQuota(targetCents: 80000, savedCents: 0, now: now, due: due, savingDay: 1, doneThisMonth: true),
      20000,
    );
    expect(
      monthlyQuota(targetCents: 80000, savedCents: 80000, now: now, due: due, savingDay: 1, doneThisMonth: true),
      0,
    );
    expect(
      monthlyQuota(
        targetCents: 1000,
        savedCents: 0,
        now: now,
        due: DateTime(2026, 11, 25),
        savingDay: 1,
        doneThisMonth: true,
      ),
      1000,
      reason: 'never fewer than one deposit',
    );
  });
}
