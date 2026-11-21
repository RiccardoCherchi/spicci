import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'accounts_page.dart';
import 'add_page.dart';
import 'backup_actions.dart';
import 'preset_sheet.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'solar.dart';
import 'widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(dayGroupsProvider).value;
    final lookup = ref.watch(lookupProvider).value;
    final tags = ref.watch(transactionTagsProvider).value ?? const {};
    if (groups == null || lookup == null) return const Center(child: CircularProgressIndicator.adaptive());
    final lang = context.locale.languageCode;

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: gap),
            sliver: SliverList.list(
              children: const [_MonthPicker(), _BackupReminder(), _Hero(), _Stats(), _Accounts(), _Presets()],
            ),
          ),
        ),
        if (groups.isEmpty) const SliverToBoxAdapter(child: _Empty()),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: gap),
          sliver: SliverList.builder(
            itemCount: groups.length,
            itemBuilder: (context, i) => DayCard(group: groups[i], lookup: lookup, tags: tags, lang: lang),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _MonthPicker extends ConsumerWidget {
  const _MonthPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final lang = context.locale.languageCode;
    final now = DateTime.now();
    final label = month.year == now.year
        ? toBeginningOfSentenceCase(monthName(month, lang))
        : '${toBeginningOfSentenceCase(monthName(month, lang))} ${month.year}';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(
        children: [
          Pill(
            label: label,
            trailing: SolarIcon.ui(Ui.altArrowDown, size: 16, color: context.tokens.muted),
            onTap: () => _pick(context, ref, month),
          ),
          const Spacer(),
          Material(
            color: context.tokens.card,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'search.title'.tr(),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
              icon: SolarIcon.ui(Ui.magnifier, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, DateTime current) async {
    final months = await ref.read(monthsProvider.future);
    if (!context.mounted) return;
    final lang = context.locale.languageCode;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final m in months)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(
                    toBeginningOfSentenceCase(DateFormat.yMMMM(lang).format(m)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: m == current ? SolarIcon.ui(Ui.checkCircle, color: sheet.tokens.accentInk) : null,
                  onTap: () => Navigator.pop(sheet, m),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) ref.read(selectedMonthProvider.notifier).set(picked);
  }
}

/// Nudges the user to copy a backup out of the phone: a sideloaded app loses
/// its data if it is deleted or re-signed with another Apple ID.
class _BackupReminder extends ConsumerStatefulWidget {
  const _BackupReminder();

  @override
  ConsumerState<_BackupReminder> createState() => _BackupReminderState();
}

class _BackupReminderState extends ConsumerState<_BackupReminder> {
  static const _snoozeKey = 'backup_snooze_until';

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final folder = ref.watch(backupFolderNameProvider);
    final lastWrite = ref.watch(folderLastWriteProvider);
    final hasData = (ref.watch(transactionsProvider).value ?? const []).isNotEmpty;
    final snoozed = DateTime.tryParse(prefs.getString(_snoozeKey) ?? '')?.isAfter(DateTime.now()) ?? false;
    final name = folder.value;
    // Backups run at every launch, so a copy older than two days means the folder stopped working.
    final healthy = name != null && lastWrite != null && DateTime.now().difference(lastWrite).inDays < 2;
    if (!hasData || folder.isLoading || healthy || snoozed) return const SizedBox.shrink();

    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        spacing: 12,
        children: [
          SolarIcon.ui(Ui.shieldCheck, color: t.accentInk),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('backup.reminder_title'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  name == null
                      ? 'backup.reminder_no_folder'.tr()
                      : 'backup.reminder_stale'.tr(namedArgs: {'name': name}),
                  style: TextStyle(color: t.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => chooseBackupFolder(context, ref), child: Text('backup.reminder_action'.tr())),
          IconButton(
            tooltip: 'backup.later'.tr(),
            onPressed: () => setState(
              () => prefs.setString(_snoozeKey, DateTime.now().add(const Duration(days: 3)).toIso8601String()),
            ),
            icon: SolarIcon.ui(Ui.closeCircle, size: 20, color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(monthStatsProvider).value;
    final month = ref.watch(selectedMonthProvider);
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final prevName = monthName(DateTime(month.year, month.month - 1), lang);
    final hasPrevious = (stats?.previousCumulative.lastOrNull ?? 0) > 0;
    final delta = stats?.deltaCents ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'home.spent_in'.tr(namedArgs: {'month': monthName(month, lang)}),
          style: TextStyle(color: t.muted, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            money(stats?.spentCents ?? 0),
            style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, letterSpacing: -1.5, color: t.ink, height: 1.1),
            centsColor: t.muted,
          ),
        ),
        if (hasPrevious && delta != 0) ...[
          const SizedBox(height: 8),
          _DeltaChip(
            text: (delta < 0 ? 'home.less_than' : 'home.more_than').tr(
              namedArgs: {'amount': money(delta.abs()), 'month': prevName},
            ),
            good: delta < 0,
          ),
        ],
        const SizedBox(height: 12),
        if (stats != null && (stats.spentCents > 0 || hasPrevious))
          SizedBox(
            height: 100,
            child: _SpendChart(stats: stats, month: month),
          ),
      ],
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.text, required this.good});
  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? context.tokens.income : context.tokens.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          SolarIcon.ui(good ? Ui.graphDown : Ui.graphUp, color: color, size: 15),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cumulative spending this month against last month. Straight segments only,
/// so the line never overshoots between points.
class _SpendChart extends StatelessWidget {
  const _SpendChart({required this.stats, required this.month});
  final MonthStats stats;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final maxY = max(1, max(stats.cumulative.lastOrNull ?? 0, stats.previousCumulative.lastOrNull ?? 0)).toDouble();
    List<FlSpot> spots(List<int> values) => [for (final (i, v) in values.indexed) FlSpot((i + 1).toDouble(), v / 100)];
    final current = spots(stats.cumulative);

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: days.toDouble(),
        minY: 0,
        maxY: maxY / 100 * 1.08,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: lineTouch(context, (s, first) {
          // Bar 0 is the dashed previous month.
          final row =
              '${s.barIndex == 0 ? 'search.period_lastMonth'.tr() : 'add.expense'.tr()} ${money((s.y * 100).round())}';
          if (!first) return row;
          final day = DateFormat.MMMd(
            context.locale.languageCode,
          ).format(DateTime(month.year, month.month, s.x.toInt()));
          return '$day\n$row';
        }),
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots: spots(stats.previousCumulative),
            color: t.muted.withValues(alpha: 0.45),
            barWidth: 2,
            dashArray: const [4, 5],
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: current,
            color: t.accentInk,
            barWidth: 2.5,
            isStrokeJoinRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.accent.withValues(alpha: 0.28), t.accent.withValues(alpha: 0)],
              ),
            ),
            dotData: FlDotData(
              checkToShowDot: (spot, _) => spot == current.last,
              getDotPainter: (_, _, _, _) =>
                  FlDotCirclePainter(radius: 4.5, color: t.accentInk, strokeWidth: 2.5, strokeColor: t.bg),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final income = ref.watch(monthStatsProvider).value?.incomeCents ?? 0;
    final worth = ref.watch(netWorthProvider).value ?? 0;
    final (_, saved) = ref.watch(freeAndSavedProvider).value ?? (0, 0);
    final t = context.tokens;
    Widget card(String label, String value, Color color, {String? caption, VoidCallback? onTap}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyText(
                value,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (caption != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  caption,
                  style: TextStyle(color: t.accentInk, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        spacing: 8,
        children: [
          card('home.income'.tr(), signedMoney(income), t.income),
          // Always the full amount, matching the bank; piggy banks are only pointed out.
          card(
            'home.net_worth'.tr(),
            money(worth),
            t.ink,
            caption: saved == 0 ? null : 'home.in_pots'.tr(namedArgs: {'amount': money(saved)}),
          ),
        ],
      ),
    );
  }
}

/// One card per account with its full balance, like the bank shows it, and the
/// part of it set aside in piggy banks underneath.
class _Accounts extends ConsumerWidget {
  const _Accounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => a.deletedAt == null && a.active)
        .toList();
    final split = ref.watch(accountSplitProvider).value ?? const {};
    final t = context.tokens;
    if (accounts.length < 2 && split.values.every((s) => s.inPots == 0)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('accounts.title'.tr()),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = accounts[i];
              final balance = split[a.id]?.balance ?? a.startingCents;
              final inPots = split[a.id]?.inPots ?? 0;
              return Material(
                color: t.card,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsPage())),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            IconTile(icon: a.icon, color: accountColor(a.color), size: 28),
                            Flexible(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: t.muted, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MoneyText(
                              money(balance),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: balance < 0 ? t.expense : t.ink,
                              ),
                            ),
                            Text(
                              inPots == 0 ? ' ' : 'home.in_pots'.tr(namedArgs: {'amount': money(inPots)}),
                              style: TextStyle(color: t.accentInk, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Presets extends ConsumerWidget {
  const _Presets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider).value ?? const <Preset>[];
    final lookup = ref.watch(lookupProvider).value;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('home.quick'.tr(), trailing: presets.isEmpty ? null : 'home.quick_hint'.tr()),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final p in presets) ...[
                _PresetCard(preset: p, lookup: lookup, onTap: () => _quickAdd(context, ref, p)),
                const SizedBox(width: 8),
              ],
              _DashedAdd(
                onTap: () => PresetSheet.open(context, null),
                color: t.line,
                label: presets.isEmpty ? 'preset.new_title'.tr() : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _quickAdd(BuildContext context, WidgetRef ref, Preset p) async {
    HapticFeedback.mediumImpact();
    final repo = ref.read(repoProvider);
    final id = await repo.insertTxn(p.toTxn(DateTime.now()));
    ref.read(dataVersionProvider.notifier).bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('home.saved'.tr(namedArgs: {'label': '${p.label} · ${money(p.amountCents)}'})),
          margin: const EdgeInsets.fromLTRB(gap, 0, gap, 96),
          action: SnackBarAction(
            label: 'home.undo'.tr(),
            onPressed: () async {
              await repo.deleteTxn(id);
              ref.read(dataVersionProvider.notifier).bump();
            },
          ),
        ),
      );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.lookup, required this.onTap});
  final Preset preset;
  final Lookup? lookup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final category = lookup?.categories[preset.categoryId];
    final color = categoryColor(lookup?.root(preset.categoryId)?.color ?? 0);
    final account = lookup?.accounts[preset.accountId]?.name ?? '';
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: () => PresetSheet.open(context, preset),
        child: Container(
          width: 128,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconTile(icon: category?.icon ?? 'tag', color: color, size: 30),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${preset.label} · $account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  MoneyText(
                    money(preset.amountCents),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedAdd extends StatelessWidget {
  const _DashedAdd({required this.onTap, required this.color, this.label});
  final VoidCallback onTap;
  final Color color;

  /// Shown only while there are no presets, to explain the empty row.
  final String? label;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: CustomPaint(
      painter: _DashedBorder(color),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          spacing: 8,
          children: [
            SolarIcon.ui(Ui.addCircle, color: context.tokens.muted),
            if (label != null)
              Text(
                label!,
                style: TextStyle(color: context.tokens.muted, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _Empty extends ConsumerWidget {
  const _Empty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          SolarIcon.category('wallet', color: t.muted, size: 44),
          const SizedBox(height: 12),
          Text('home.empty'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'home.empty_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 20),
          Text(
            'home.restore_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, fontSize: 13),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: () => restoreFromFile(context, ref), child: Text('backup.restore_file'.tr())),
              TextButton(
                onPressed: () => SettingsPage.importSossoldi(context, ref),
                child: Text('settings.import_sossoldi'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.group, required this.lookup, required this.tags, required this.lang});
  final DayGroup group;
  final Lookup lookup;
  final Map<int, List<String>> tags;
  final String lang;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        toBeginningOfSentenceCase(dayLabel(group.day, lang)),
        trailing: group.totalCents == 0 ? null : signedMoney(group.totalCents),
      ),
      Material(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [for (final t in group.txns) TxnRow(txn: t, lookup: lookup, tags: tags[t.id] ?? const [])],
          ),
        ),
      ),
    ],
  );
}

class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, required this.lookup, this.tags = const []});
  final List<String> tags;
  final Txn txn;
  final Lookup lookup;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final category = lookup.categories[txn.categoryId];
    final account = lookup.accounts[txn.accountId]?.name ?? '?';
    final isTransfer = txn.type == TxType.transfer;
    final note = txn.note?.trim() ?? '';
    final title = note.isNotEmpty
        ? note
        : isTransfer
        ? 'home.transfer'.tr()
        : category?.name ?? 'home.uncategorised'.tr();
    final subtitle = isTransfer
        ? '$account → ${lookup.accounts[txn.toAccountId]?.name ?? '?'}'
        : [category?.name ?? 'home.uncategorised'.tr(), account, ...tags.map((t) => '#$t')].join(' · ');
    final (amount, color) = switch (txn.type) {
      TxType.income => ('+${money(txn.amountCents)}', t.income),
      TxType.expense => ('−${money(txn.amountCents)}', t.ink),
      TxType.transfer => (money(txn.amountCents), t.muted),
    };

    return InkWell(
      onTap: () => AddPage.open(context, editing: txn),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            isTransfer
                ? Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: t.card2, borderRadius: BorderRadius.circular(13)),
                    alignment: Alignment.center,
                    child: SolarIcon.ui(Ui.transferHorizontal, color: t.muted, size: 22),
                  )
                : IconTile(
                    icon: category?.icon ?? 'tag',
                    color: categoryColor(lookup.root(txn.categoryId)?.color ?? 0),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The amount keeps its natural width; only the text column shrinks.
            MoneyText(
              amount,
              style: TextStyle(color: color, fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
