import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'date_sheet.dart';
import 'pickers.dart';
import 'plan_actions.dart';
import 'solar.dart';
import 'widgets.dart';

/// Create or edit a subscription (SUB) or a planned big expense (PLAN).
class ScheduledSheet extends ConsumerStatefulWidget {
  const ScheduledSheet({super.key, required this.kind, this.item});
  final String kind;
  final Scheduled? item;

  static Future<void> open(BuildContext context, {required String kind, Scheduled? item}) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ScheduledSheet(kind: kind, item: item),
  );

  @override
  ConsumerState<ScheduledSheet> createState() => _ScheduledSheetState();
}

class _ScheduledSheetState extends ConsumerState<ScheduledSheet> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _amount = TextEditingController(
    text: widget.item == null ? '' : NumberFormat.decimalPattern(moneyLocale).format(widget.item!.amountCents / 100),
  );
  late DateTime _due = widget.item?.nextDue ?? DateTime.now();
  late Freq _freq = widget.item?.freq ?? (widget.kind == 'PLAN' ? Freq.annual : Freq.monthly);
  late int? _categoryId = widget.item?.categoryId;
  late int? _accountId = widget.item?.accountId;
  late int _remind = widget.item?.remindDays ?? (widget.kind == 'PLAN' ? 7 : 1);
  var _withPot = true;

  /// Editable, so imported Sossoldi items can move between subscriptions and planned expenses.
  late String _kind = widget.item?.kind ?? widget.kind;

  bool get _planned => _kind == 'PLAN';

  /// Whether a piggy bank already saves for this item.
  bool get _hasPot =>
      widget.item != null &&
      (ref.read(potsProvider).value ?? const <Pot>[]).any(
        (p) => p.recurringId == widget.item!.id && p.archivedAt == null,
      );

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(Lookup lookup) async {
    final n = parseAmount(_amount.text.trim());
    if (_name.text.trim().isEmpty || n == null || n <= 0 || _accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('plan.fill_all'.tr())));
      return;
    }
    final old = widget.item;
    final repo = ref.read(repoProvider);
    final dateChanged = old == null || old.nextDue != _due;
    final id = await repo.saveScheduled(
      Scheduled(
        id: old?.id,
        kind: _kind,
        name: _name.text.trim(),
        amountCents: (n * 100).round(),
        type: old?.type ?? TxType.expense,
        freq: _freq,
        // A new date also becomes the anchor for the following ones.
        fromDate: dateChanged ? _due : old.fromDate,
        toDate: old?.toDate,
        categoryId: _categoryId,
        accountId: _accountId!,
        nextDue: _due,
        remindDays: _remind,
        lastDate: old?.lastDate,
      ),
    );
    if (_planned && _withPot && !_hasPot) {
      final category = lookup.categories[_categoryId];
      await repo.savePot(
        Pot(
          accountId: _accountId!,
          name: _name.text.trim(),
          icon: category?.icon ?? 'piggy-bank',
          color: lookup.root(_categoryId)?.color ?? 0,
          recurringId: id,
        ),
      );
    }
    await afterScheduleChange(ref);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'plan.delete_title'.tr(), 'plan.delete_body'.tr())) return;
    await ref.read(repoProvider).archiveScheduled(widget.item!.id!);
    await afterScheduleChange(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    ref.watch(potsProvider); // keeps _hasPot current
    if (lookup == null) return const SizedBox(height: 200);
    _accountId ??= lookup.mainAccount?.id;
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final category = lookup.categories[_categoryId];
    // Parents in their order, each followed by its subcategories.
    String key(Category c) {
      final root = lookup.root(c.id)!;
      final own = c.parentId == null ? '' : c.position.toString().padLeft(5, '0');
      return '${root.position.toString().padLeft(5, '0')}${root.id}|$own';
    }

    final categories = lookup.categories.values
        .where((c) => c.deletedAt == null && c.matches(TxType.expense))
        .sortedBy(key);

    Widget choice(Ui icon, String label, VoidCallback onTap) => Pill(
      label: label,
      color: t.card2,
      leading: SolarIcon.ui(icon, size: 16, color: t.muted),
      onTap: onTap,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 0, gap, MediaQuery.viewInsetsOf(context).bottom + gap),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Text(
                (widget.item != null ? 'plan.edit' : (_planned ? 'plan.new_planned' : 'plan.new_sub')).tr(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (widget.item != null)
                Row(
                  spacing: 8,
                  children: [
                    for (final k in ['SUB', 'PLAN'])
                      Pill(
                        label: (k == 'SUB' ? 'plan.kind_sub' : 'plan.kind_plan').tr(),
                        color: _kind == k ? t.accent.withValues(alpha: 0.18) : t.card2,
                        onTap: () => setState(() => _kind = k),
                      ),
                  ],
                ),
              if (_planned && widget.item == null)
                Text('plan.planned_hint'.tr(), style: TextStyle(color: t.muted, fontSize: 13)),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _name,
                      autofocus: widget.item == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: (_planned ? 'plan.name_planned' : 'plan.name_sub').tr()),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(hintText: 'preset.amount'.tr(), prefixText: '€ '),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  choice(Ui.calendar, DateFormat.yMMMd(lang).format(_due), () async {
                    final d = await pickDay(context, initial: _due);
                    if (d != null) setState(() => _due = d);
                  }),
                  choice(Ui.history, 'freq.${_freq.code}'.tr(), () async {
                    final o = await pickOption<Freq>(context, [
                      for (final f in Freq.values) Option(f, 'freq.${f.code}'.tr()),
                    ], selected: _freq);
                    if (o != null) setState(() => _freq = o.value);
                  }),
                  choice(Ui.tag, category?.name ?? 'preset.category'.tr(), () async {
                    final o = await pickOption<int?>(context, [
                      Option(null, 'home.uncategorised'.tr()),
                      for (final c in categories)
                        Option(
                          c.id,
                          c.parentId == null ? c.name : '   ${c.name}',
                          leading: IconTile(
                            icon: c.icon,
                            color: categoryColor(lookup.root(c.id)?.color ?? 0),
                            size: 30,
                          ),
                        ),
                    ], selected: _categoryId);
                    if (o != null) setState(() => _categoryId = o.value);
                  }),
                  choice(Ui.card, lookup.accounts[_accountId]?.name ?? 'preset.account'.tr(), () async {
                    final a = await pickAccount(context, lookup.accounts.values.toList(), selectedId: _accountId);
                    if (a != null) setState(() => _accountId = a.id);
                  }),
                  choice(Ui.notes, _remind == 0 ? 'plan.remind_none'.tr() : 'plan.remind'.plural(_remind), () async {
                    final o = await pickOption<int>(context, [
                      for (final d in [0, 1, 3, 7, 14, 30])
                        Option(d, d == 0 ? 'plan.remind_none'.tr() : 'plan.remind'.plural(d)),
                    ], selected: _remind);
                    if (o != null) setState(() => _remind = o.value);
                  }),
                ],
              ),
              if (_planned && !_hasPot)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _withPot,
                  activeTrackColor: t.accent,
                  onChanged: (v) => setState(() => _withPot = v),
                  title: Text('plan.with_pot'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('plan.with_pot_sub'.tr(), style: TextStyle(color: t.muted, fontSize: 12.5)),
                ),
              Row(
                spacing: 8,
                children: [
                  if (widget.item != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _delete,
                        child: Text('add.delete'.tr(), style: TextStyle(color: t.expense)),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: FilledButton(onPressed: () => _save(lookup), child: Text('preset.save'.tr())),
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
