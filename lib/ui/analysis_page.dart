import 'dart:convert';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../logic/ai.dart';
import '../logic/analysis.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'ai_settings_page.dart';
import 'home_page.dart';
import 'solar.dart';
import 'widgets.dart';

class _PeriodNotifier extends Notifier<Period> {
  @override
  Period build() {
    final now = DateTime.now();
    return Period.month(DateTime(now.year, now.month));
  }

  void set(Period p) => state = p;
}

final _periodProvider = NotifierProvider<_PeriodNotifier, Period>(_PeriodNotifier.new);

class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider).value;
    final lookup = ref.watch(lookupProvider).value;
    if (txns == null || lookup == null) return const Center(child: CircularProgressIndicator.adaptive());
    final period = ref.watch(_periodProvider);
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final label = period.isYear
        ? '${period.start.year}'
        : toBeginningOfSentenceCase(DateFormat.yMMMM(lang).format(period.start));
    final now = DateTime.now();
    final canGoNext = period.next.start.isBefore(DateTime(now.year, now.month + 1));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 130),
        children: [
          Text(
            'analysis.title'.tr(),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Toggle(
                isYear: period.isYear,
                onChanged: (year) => ref
                    .read(_periodProvider.notifier)
                    .set(year ? Period.year(DateTime(period.start.year)) : Period.month(DateTime(now.year, now.month))),
              ),
              const Spacer(),
              _Arrow(icon: Ui.altArrowLeft, onTap: () => ref.read(_periodProvider.notifier).set(period.previous)),
              SizedBox(
                width: 132,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _Arrow(
                icon: Ui.altArrowRight,
                onTap: canGoNext ? () => ref.read(_periodProvider.notifier).set(period.next) : null,
              ),
            ],
          ),
          _Overview(txns: txns, period: period),
          _Categories(txns: txns, period: period, lookup: lookup),
          SectionHeader('analysis.months'.tr()),
          _Card(
            child: Column(
              spacing: 10,
              children: [
                SizedBox(
                  height: 190,
                  child: _MonthBars(
                    series: monthlySeries(txns, period.isYear ? DateTime(period.start.year, 12) : period.start),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 16,
                  children: [
                    _Legend(color: t.muted.withValues(alpha: 0.45), label: 'add.income'.tr()),
                    _Legend(color: t.accentInk, label: 'add.expense'.tr()),
                  ],
                ),
              ],
            ),
          ),
          const _NetWorth(),
          SectionHeader('analysis.largest'.tr()),
          _Card(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final tx in largestExpenses(txns, period)) TxnRow(txn: tx, lookup: lookup),
                if (largestExpenses(txns, period).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('analysis.nothing'.tr(), style: TextStyle(color: t.muted)),
                  ),
              ],
            ),
          ),
          _AiCard(txns: txns, period: period, lookup: lookup),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: context.tokens.card, borderRadius: BorderRadius.circular(22)),
    child: child,
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final Ui icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: SolarIcon.ui(icon, size: 18, color: onTap == null ? context.tokens.line : null),
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.isYear, required this.onChanged});
  final bool isYear;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget option(bool year, String label) => GestureDetector(
      onTap: () => onChanged(year),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isYear == year ? t.card2 : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w600, color: isYear == year ? t.ink : t.muted),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option(false, 'analysis.month'.tr()), option(true, 'analysis.year'.tr())],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.txns, required this.period});
  final List<Txn> txns;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tot = totals(txns, period);
    final rate = tot.savingsRate;
    final projection = period.isYear ? null : monthProjection(txns, period.start, DateTime.now());
    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.muted, fontSize: 12.5)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              value,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Row(
              spacing: 10,
              children: [
                stat('add.income'.tr(), '+${money(tot.incomeCents)}', t.income),
                stat('add.expense'.tr(), '−${money(tot.expenseCents)}', t.ink),
                stat('analysis.net'.tr(), signedMoney(tot.netCents), tot.netCents < 0 ? t.expense : t.accentInk),
              ],
            ),
            if (rate != null || projection != null)
              Text(
                [
                  if (rate != null) 'analysis.saved_rate'.tr(namedArgs: {'pct': '${(rate * 100).round()}'}),
                  if (projection != null) 'analysis.projection'.tr(namedArgs: {'amount': money(projection)}),
                ].join(' · '),
                style: TextStyle(color: t.muted, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _Categories extends StatefulWidget {
  const _Categories({required this.txns, required this.period, required this.lookup});
  final List<Txn> txns;
  final Period period;
  final Lookup lookup;

  @override
  State<_Categories> createState() => _CategoriesState();
}

class _CategoriesState extends State<_Categories> {
  int? _open = -1;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shares = categoryBreakdown(widget.txns, widget.period, widget.lookup.categories, now: DateTime.now());
    final total = shares.fold(0, (s, x) => s + x.cents);
    Color colorOf(int? id) => id == null ? t.muted : categoryColor(widget.lookup.categories[id]?.color ?? 0);
    String nameOf(int? id) => widget.lookup.categories[id]?.name ?? 'home.uncategorised'.tr();
    final picked = shares.where((s) => s.categoryId == _open).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('analysis.categories'.tr()),
        _Card(
          child: total == 0
              ? Text('analysis.nothing'.tr(), style: TextStyle(color: t.muted))
              : Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Sections come from the same list as the legend, so they always match.
                          PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 58,
                              startDegreeOffset: -90,
                              pieTouchData: PieTouchData(
                                touchCallback: (event, response) {
                                  final i = response?.touchedSection?.touchedSectionIndex ?? -1;
                                  if (event is! FlTapUpEvent || i < 0) return;
                                  final id = shares[i].categoryId;
                                  setState(() => _open = _open == id ? -1 : id);
                                },
                              ),
                              sections: [
                                for (final s in shares)
                                  PieChartSectionData(
                                    value: s.cents.toDouble(),
                                    color: colorOf(s.categoryId),
                                    radius: _open == s.categoryId ? 26 : 20,
                                    showTitle: false,
                                  ),
                              ],
                            ),
                            duration: Duration.zero,
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                picked == null ? 'add.expense'.tr() : nameOf(picked.categoryId),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.muted, fontSize: 12),
                              ),
                              MoneyText(
                                money(picked?.cents ?? total),
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in shares) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _open = _open == s.categoryId ? -1 : s.categoryId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            spacing: 10,
                            children: [
                              IconTile(
                                icon: widget.lookup.categories[s.categoryId]?.icon ?? 'tag',
                                color: colorOf(s.categoryId),
                                size: 34,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nameOf(s.categoryId),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      '${(s.cents * 100 / total).round()}%',
                                      style: TextStyle(color: t.muted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  MoneyText(
                                    money(s.cents),
                                    style: TextStyle(fontWeight: FontWeight.w700, color: t.ink),
                                  ),
                                  if (s.previousCents > 0) _Delta(now: s.cents, before: s.previousCents),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Only worth expanding when it has subcategories, not just direct spending.
                      if (_open == s.categoryId && !(s.children.length == 1 && s.children.containsKey(s.categoryId)))
                        for (final c in s.children.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(44, 2, 0, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.key == s.categoryId ? 'analysis.direct'.tr() : nameOf(c.key),
                                    style: TextStyle(color: t.muted),
                                  ),
                                ),
                                Text(
                                  money(c.value),
                                  style: TextStyle(color: t.muted, fontFeatures: tabular),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Change against the previous period. Spending less is good, so it is green.
class _Delta extends StatelessWidget {
  const _Delta({required this.now, required this.before});
  final int now;
  final int before;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pct = ((now - before) * 100 / before).round();
    if (pct == 0) return const SizedBox.shrink();
    return Text(
      '${pct > 0 ? '▲' : '▼'} ${pct.abs()}%',
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pct > 0 ? t.expense : t.income),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      Text(label, style: TextStyle(color: context.tokens.muted, fontSize: 12)),
    ],
  );
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.series});
  final List<(DateTime, Totals)> series;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final top = series.fold(0, (m, e) => max(m, max(e.$2.incomeCents, e.$2.expenseCents)));
    return BarChart(
      BarChartData(
        maxY: max(1, top) / 100 * 1.1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => t.card2,
            tooltipBorderRadius: BorderRadius.circular(10),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 180,
            // One tooltip per month, whichever bar was touched.
            getTooltipItem: (group, i, rod, rodIndex) {
              final (m, tot) = series[i];
              return BarTooltipItem(
                '${DateFormat.yMMM(lang).format(m)}\n'
                '${'add.income'.tr()} ${money(tot.incomeCents)}\n'
                '${'add.expense'.tr()} ${money(tot.expenseCents)}',
                TextStyle(color: t.ink, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  DateFormat.MMM(lang).format(series[v.toInt()].$1).characters.first.toUpperCase(),
                  style: TextStyle(color: t.muted, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (final (i, (_, tot)) in series.indexed)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                  toY: tot.incomeCents / 100,
                  color: t.muted.withValues(alpha: 0.45),
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                ),
                BarChartRodData(
                  toY: tot.expenseCents / 100,
                  color: t.accentInk,
                  width: 7,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _NetWorth extends ConsumerWidget {
  const _NetWorth();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider).value ?? const <Txn>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final current = ref.watch(netWorthProvider).value;
    if (current == null) return const SizedBox.shrink();
    final counted = {for (final a in accounts.where((a) => a.deletedAt == null && a.countNetWorth)) a.id};
    final now = DateTime.now();
    final series = netWorthSeries(
      txns.where((tx) => counted.contains(tx.accountId)),
      current,
      DateTime(now.year, now.month),
    );
    final values = series.map((e) => e.$2 / 100).toList();
    final lo = values.reduce(min), hi = values.reduce(max);
    final pad = max(1.0, (hi - lo) * 0.15);
    final t = context.tokens;
    final lang = context.locale.languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('home.net_worth'.tr(), trailing: money(current)),
        _Card(
          child: SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (values.length - 1).toDouble(),
                // Bounds follow the data, negatives included, so the line never leaves the chart.
                minY: lo - pad,
                maxY: hi + pad,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: lineTouch(
                  context,
                  (s, _) => '${DateFormat.yMMM(lang).format(series[s.x.toInt()].$1)}\n${money((s.y * 100).round())}',
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          DateFormat.MMM(lang).format(series[v.toInt()].$1).characters.first.toUpperCase(),
                          style: TextStyle(color: t.muted, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v)],
                    color: t.accentInk,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      applyCutOffY: true,
                      cutOffY: lo - pad,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [t.accent.withValues(alpha: 0.22), t.accent.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ),
      ],
    );
  }
}

/// Optional commentary from the user's AI provider, written on top of the numbers above.
class _AiCard extends ConsumerStatefulWidget {
  const _AiCard({required this.txns, required this.period, required this.lookup});
  final List<Txn> txns;
  final Period period;
  final Lookup lookup;

  @override
  ConsumerState<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends ConsumerState<_AiCard> {
  final _cache = <Period, String>{};
  Period? _loading;
  String? _error;

  Future<void> _run(AiSettings settings, String key) async {
    setState(() {
      _loading = widget.period;
      _error = null;
    });
    final period = widget.period;
    try {
      final payload = aiPayload(widget.txns, period, widget.lookup.categories);
      final language = context.locale.languageCode == 'it' ? 'Italian' : 'English';
      final text = await AiClient(
        baseUrl: settings.baseUrl,
        apiKey: key,
        model: settings.model,
      ).chat(aiSystemPrompt(language), jsonEncode(payload));
      _cache[period] = text;
    } on Object catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final key = ref.watch(aiKeyProvider).value;
    final t = context.tokens;
    final ready = settings.isComplete && (key?.isNotEmpty ?? false);
    final text = _cache[widget.period];
    final loading = _loading == widget.period;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('analysis.ai'.tr()),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (!ready)
                Text('analysis.ai_setup_hint'.tr(), style: TextStyle(color: t.muted))
              else if (text != null)
                Text(text, style: const TextStyle(height: 1.4))
              else
                Text('analysis.ai_hint'.tr(), style: TextStyle(color: t.muted)),
              if (_error != null) Text(_error!, style: TextStyle(color: t.expense, fontSize: 12.5)),
              if (!ready)
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsPage())),
                  child: Text('analysis.ai_setup'.tr()),
                )
              else
                FilledButton(
                  onPressed: loading ? null : () => _run(settings, key!),
                  child: loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: t.onAccent),
                        )
                      : Text((text == null ? 'analysis.ai_write' : 'analysis.ai_again').tr()),
                ),
              if (ready)
                Row(
                  spacing: 6,
                  children: [
                    SolarIcon.ui(Ui.shieldCheck, size: 14, color: t.muted),
                    Expanded(
                      child: Text('analysis.ai_privacy'.tr(), style: TextStyle(color: t.muted, fontSize: 11.5)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
