import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../logic/schedule.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'budget_sheet.dart';
import 'pay_sheet.dart';
import 'pickers.dart';
import 'plan_actions.dart';
import 'pot_page.dart';
import 'scheduled_sheet.dart';
import 'solar.dart';
import 'widgets.dart';

/// Amount still to put aside per month for a piggy bank, or null without a goal.
int? potQuota(Pot p, Scheduled? linked, int saved, DateTime now, int savingDay) {
  final target = linked?.amountCents ?? p.targetCents;
  final due = linked?.nextDue ?? p.targetDate;
  if (target == null || due == null) return null;
  return monthlyQuota(
    targetCents: target,
    savedCents: saved,
    now: now,
    due: due,
    savingDay: savingDay,
    doneThisMonth: linked != null && p.autoMonth == monthKey(now),
  );
}

class PlanPage extends ConsumerWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(scheduledProvider).value;
    final pots = ref.watch(potsProvider).value;
    final lookup = ref.watch(lookupProvider).value;
    if (items == null || pots == null || lookup == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final now = DateTime.now();
    final active = items.where((s) => s.archivedAt == null).toList();
    final pending = active.where((s) => isPending(s, now)).sortedBy((s) => s.nextDue);
    final planned = active.where((s) => s.isPlanned).toList();
    final subs = active.where((s) => !s.isPlanned).toList();
    final livePots = pots.where((p) => p.archivedAt == null).toList();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 130),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'plan.title'.tr(),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
              ),
              Material(
                color: context.tokens.card,
                shape: const CircleBorder(),
                child: IconButton(onPressed: () => _add(context), icon: SolarIcon.ui(Ui.addCircle)),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            SectionHeader('plan.to_confirm'.tr()),
            for (final s in pending) _PendingCard(item: s, lookup: lookup),
          ],
          const _Summary(),
          SectionHeader('plan.pots'.tr()),
          if (livePots.isEmpty)
            _EmptyHint(text: 'plan.pots_empty'.tr(), onTap: () => PotSheet.open(context, null))
          else
            for (final p in livePots) _PotCard(pot: p, linked: items.firstWhereOrNull((s) => s.id == p.recurringId)),
          SectionHeader('plan.planned'.tr()),
          if (planned.isEmpty)
            _EmptyHint(
              text: 'plan.planned_empty'.tr(),
              onTap: () => ScheduledSheet.open(context, kind: 'PLAN'),
            )
          else
            _Timeline(items: planned, lookup: lookup),
          SectionHeader(
            'plan.subscriptions'.tr(),
            trailing: subs.isEmpty ? null : 'plan.per_year'.tr(namedArgs: {'amount': money(subs.map(yearlyCents).sum)}),
          ),
          if (subs.isEmpty)
            _EmptyHint(
              text: 'plan.subs_empty'.tr(),
              onTap: () => ScheduledSheet.open(context, kind: 'SUB'),
            )
          else
            _Card(
              children: [for (final s in subs.sortedBy((s) => s.nextDue)) _ItemRow(item: s, lookup: lookup)],
            ),
          const _Budgets(),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final o = await pickOption<String>(context, [
      Option('PLAN', 'plan.new_planned'.tr(), leading: SolarIcon.ui(Ui.calendar)),
      Option('SUB', 'plan.new_sub'.tr(), leading: SolarIcon.ui(Ui.history)),
      Option('pot', 'plan.new_pot'.tr(), leading: SolarIcon.category('piggy-bank', size: 24)),
      Option('budget', 'plan.new_budget'.tr(), leading: SolarIcon.ui(Ui.graphUp)),
    ]);
    if (o == null || !context.mounted) return;
    switch (o.value) {
      case 'pot':
        await PotSheet.open(context, null);
      case 'budget':
        await BudgetSheet.open(context, null);
      default:
        await ScheduledSheet.open(context, kind: o.value);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          spacing: 12,
          children: [
            SolarIcon.ui(Ui.addCircle, color: context.tokens.muted),
            Expanded(
              child: Text(text, style: TextStyle(color: context.tokens.muted)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.item, required this.lookup});
  final Scheduled item;
  final Lookup lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final category = lookup.categories[item.categoryId];
    final lang = context.locale.languageCode;
    Future<void> after() async {
      ref.read(dataVersionProvider.notifier).bump();
      await refreshPlan(ref);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              IconTile(
                icon: category?.icon ?? 'calendar',
                color: categoryColor(lookup.root(item.categoryId)?.color ?? 0),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                    Text(
                      'plan.due_on'.tr(namedArgs: {'date': DateFormat.MMMd(lang).format(item.nextDue)}),
                      style: TextStyle(color: t.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              MoneyText(
                money(item.amountCents),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: t.ink),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                  onPressed: () => PaySheet.open(context, item),
                  child: Text('plan.paid'.tr()),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () async {
                    final d = DateTime.now().add(const Duration(days: 1));
                    await ref.read(repoProvider).snoozeScheduled(item.id!, DateTime(d.year, d.month, d.day, 9));
                    await after();
                  },
                  child: Text('plan.tomorrow'.tr()),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await ref.read(repoProvider).skipScheduled(item);
                    await after();
                  },
                  child: Text('plan.skip'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Free money against money already set aside, plus what to put aside monthly.
class _Summary extends ConsumerWidget {
  const _Summary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (free, saved) = ref.watch(freeAndSavedProvider).value ?? (0, 0);
    final pots = ref.watch(potsProvider).value ?? const <Pot>[];
    final items = ref.watch(scheduledProvider).value ?? const <Scheduled>[];
    final balances = ref.watch(potBalancesProvider).value ?? const {};
    final savingDay = ref.watch(savingDayProvider);
    final now = DateTime.now();
    final monthly = pots
        .where((p) => p.archivedAt == null)
        .map(
          (p) =>
              potQuota(p, items.firstWhereOrNull((s) => s.id == p.recurringId), balances[p.id] ?? 0, now, savingDay) ??
              0,
        )
        .sum;
    final t = context.tokens;
    Widget stat(String label, int cents, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.muted, fontSize: 12.5)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              money(cents),
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(22)),
      child: Row(
        spacing: 10,
        children: [
          stat('home.net_worth'.tr(), free + saved, free + saved < 0 ? t.expense : t.ink),
          stat('plan.saved'.tr(), saved, t.accentInk),
          stat('plan.monthly'.tr(), monthly, t.muted),
        ],
      ),
    );
  }
}

class _PotCard extends ConsumerWidget {
  const _PotCard({required this.pot, required this.linked});
  final Pot pot;
  final Scheduled? linked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final saved = ref.watch(potBalancesProvider).value?[pot.id] ?? 0;
    final quota = potQuota(pot, linked, saved, DateTime.now(), ref.watch(savingDayProvider));
    final target = linked?.amountCents ?? pot.targetCents;
    final due = linked?.nextDue ?? pot.targetDate;
    final color = categoryColor(pot.color);
    final lang = context.locale.languageCode;
    final progress = target == null || target == 0 ? null : (saved / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PotPage(potId: pot.id!))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    IconTile(icon: pot.icon, color: color),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                          ),
                          Text(
                            [
                              if (due != null) DateFormat.yMMM(lang).format(due),
                              if (quota != null && quota > 0) 'plan.quota'.tr(namedArgs: {'amount': money(quota)}),
                              if (linked != null) 'plan.auto'.tr(),
                            ].join(' · '),
                            style: TextStyle(color: t.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        MoneyText(
                          money(saved),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: t.ink),
                        ),
                        if (target != null)
                          Text(
                            'plan.of'.tr(namedArgs: {'amount': money(target)}),
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
                if (progress != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: t.card2,
                      color: progress >= 1 ? t.income : color,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Planned expenses over the next 12 months, grouped by month with totals.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.items, required this.lookup});
  final List<Scheduled> items;
  final Lookup lookup;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final end = DateTime(now.year + 1, now.month + 1);
    final occurrences = <(Scheduled, DateTime)>[];
    for (final s in items) {
      for (DateTime? d = s.nextDue; d != null && d.isBefore(end);) {
        occurrences.add((s, d));
        if (s.freq == Freq.once) break;
        d = advance(d, s.freq, s.fromDate.day);
        if (s.toDate != null && d.isAfter(s.toDate!)) break;
      }
    }
    occurrences.sortBy((o) => o.$2);
    final byMonth = groupBy(occurrences, (o) => DateTime(o.$2.year, o.$2.month));
    final lang = context.locale.languageCode;
    final t = context.tokens;

    return Column(
      children: [
        for (final MapEntry(key: month, value: list) in byMonth.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    toBeginningOfSentenceCase(DateFormat.yMMMM(lang).format(month)),
                    style: TextStyle(color: t.muted, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text(
                  money(list.map((o) => o.$1.amountCents).sum),
                  style: TextStyle(color: t.muted, fontWeight: FontWeight.w600, fontSize: 13, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          _Card(
            children: [for (final (s, d) in list) _ItemRow(item: s, lookup: lookup, date: d)],
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.lookup, this.date});
  final Scheduled item;
  final Lookup lookup;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final category = lookup.categories[item.categoryId];
    final when = DateFormat.MMMd(lang).format(date ?? item.nextDue);
    final freq = 'freq.${item.freq.code}'.tr();
    return InkWell(
      onTap: () => ScheduledSheet.open(context, kind: item.kind, item: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          spacing: 12,
          children: [
            IconTile(
              icon: category?.icon ?? 'calendar',
              color: categoryColor(lookup.root(item.categoryId)?.color ?? 0),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  Text(
                    item.isPlanned ? '$when · $freq' : '$freq · ${'plan.next'.tr(namedArgs: {'date': when})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  money(item.amountCents),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.ink),
                ),
                if (!item.isPlanned && item.freq != Freq.once)
                  Text(
                    'plan.per_year'.tr(namedArgs: {'amount': money(yearlyCents(item))}),
                    style: TextStyle(color: t.muted, fontSize: 11.5),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Budgets extends ConsumerWidget {
  const _Budgets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final spent = ref.watch(budgetSpentProvider).value ?? const {};
    final lookup = ref.watch(lookupProvider).value;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('plan.budgets'.tr()),
        if (budgets.isEmpty || lookup == null)
          _EmptyHint(text: 'plan.budgets_empty'.tr(), onTap: () => BudgetSheet.open(context, null))
        else
          _Card(
            children: [
              for (final b in budgets)
                InkWell(
                  onTap: () => BudgetSheet.open(context, b),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Builder(
                      builder: (context) {
                        final c = lookup.categories[b.categoryId];
                        final used = spent[b.id] ?? 0;
                        final ratio = b.amountCents == 0 ? 0.0 : used / b.amountCents;
                        final over = used > b.amountCents;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            Row(
                              spacing: 12,
                              children: [
                                IconTile(icon: c?.icon ?? 'tag', color: categoryColor(c?.color ?? 0), size: 32),
                                Expanded(
                                  child: Text(
                                    c?.name ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '${money(used)} / ${money(b.amountCents)}',
                                  style: TextStyle(
                                    color: over ? t.expense : t.muted,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: tabular,
                                  ),
                                ),
                              ],
                            ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: ratio.clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: t.card2,
                                color: over ? t.expense : (ratio > 0.85 ? Colors.orange : t.income),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
