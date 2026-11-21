import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'date_sheet.dart';
import 'pickers.dart';
import 'plan_page.dart';
import 'solar.dart';
import 'widgets.dart';

final _movesProvider = FutureProvider.family<List<PotMove>, int>((ref, potId) {
  ref.watch(dataVersionProvider);
  return ref.watch(repoProvider).potMoves(potId);
});

class PotPage extends ConsumerWidget {
  const PotPage({super.key, required this.potId});
  final int potId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pot = ref.watch(potsProvider).value?.firstWhereOrNull((p) => p.id == potId);
    final moves = ref.watch(_movesProvider(potId)).value ?? const <PotMove>[];
    final lookup = ref.watch(lookupProvider).value;
    if (pot == null || lookup == null) return const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
    final linked = ref.watch(scheduledProvider).value?.firstWhereOrNull((s) => s.id == pot.recurringId);
    final saved = ref.watch(potBalancesProvider).value?[pot.id] ?? 0;
    final free = ref.watch(accountSplitProvider).value?[pot.accountId]?.free ?? 0;
    final quota = potQuota(pot, linked, saved, DateTime.now(), ref.watch(savingDayProvider));
    final target = linked?.amountCents ?? pot.targetCents;
    final due = linked?.nextDue ?? pot.targetDate;
    final t = context.tokens;
    final lang = context.locale.languageCode;
    final color = categoryColor(pot.color);

    return SubPage(
      title: pot.name,
      actions: [IconButton(onPressed: () => PotSheet.open(context, pot), icon: SolarIcon.ui(Ui.pen))],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 40),
        children: [
          Center(
            child: IconTile(icon: pot.icon, color: color, size: 64),
          ),
          const SizedBox(height: 12),
          Center(
            child: MoneyText(
              money(saved),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1, color: t.ink),
              centsColor: t.muted,
            ),
          ),
          Center(
            child: Text(
              [
                if (target != null) 'plan.of'.tr(namedArgs: {'amount': money(target)}),
                if (due != null) DateFormat.yMMMd(lang).format(due),
                lookup.accounts[pot.accountId]?.name ?? '',
              ].join(' · '),
              style: TextStyle(color: t.muted),
            ),
          ),
          if (target != null && target > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (saved / target).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: t.card,
                color: saved >= target ? t.income : color,
              ),
            ),
          ],
          if (quota != null && quota > 0) ...[
            const SizedBox(height: 10),
            Text(
              (linked != null ? 'plan.quota_auto' : 'plan.quota_manual').tr(namedArgs: {'amount': money(quota)}),
              textAlign: TextAlign.center,
              style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _MoveSheet.open(context, pot, deposit: true, free: free),
                  child: Text('plan.put_in'.tr()),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _MoveSheet.open(context, pot, deposit: false, free: saved),
                  child: Text('plan.take_out'.tr()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'plan.free_in_account'.tr(namedArgs: {'amount': money(free)}),
            textAlign: TextAlign.center,
            style: TextStyle(color: free < 0 ? t.expense : t.muted, fontSize: 12.5),
          ),
          SectionHeader('plan.history'.tr()),
          if (moves.isEmpty)
            Text('plan.history_empty'.tr(), style: TextStyle(color: t.muted))
          else
            Material(
              color: t.card,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final m in moves)
                    ListTile(
                      title: Text(
                        m.note ??
                            (m.auto
                                ? 'plan.auto_deposit'.tr()
                                : (m.amountCents > 0 ? 'plan.put_in'.tr() : 'plan.take_out'.tr())),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(DateFormat.yMMMd(lang).format(m.date)),
                      trailing: MoneyText(
                        signedMoney(m.amountCents),
                        style: TextStyle(fontWeight: FontWeight.w700, color: m.amountCents > 0 ? t.income : t.ink),
                      ),
                      // Moves tied to an expense are undone by editing that expense.
                      onLongPress: m.transactionId != null
                          ? null
                          : () async {
                              if (!await confirm(context, 'plan.delete_move'.tr(), '')) return;
                              await ref.read(repoProvider).deletePotMove(m.id!);
                              ref.read(dataVersionProvider.notifier).bump();
                            },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Puts money into a pot or takes it out. Neither changes the account balance.
class _MoveSheet extends ConsumerStatefulWidget {
  const _MoveSheet({required this.pot, required this.deposit, required this.limit});
  final Pot pot;
  final bool deposit;
  final int limit;

  static Future<void> open(BuildContext context, Pot pot, {required bool deposit, required int free}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _MoveSheet(pot: pot, deposit: deposit, limit: free),
      );

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = parseAmount(_amount.text.trim());
    if (n == null || n <= 0) return;
    final cents = (n * 100).round();
    final note = _note.text.trim();
    await ref
        .read(repoProvider)
        .addPotMove(
          PotMove(
            potId: widget.pot.id!,
            date: DateTime.now(),
            amountCents: widget.deposit ? cents : -cents,
            note: note.isEmpty ? null : note,
          ),
        );
    HapticFeedback.mediumImpact();
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 0, gap, MediaQuery.viewInsetsOf(context).bottom + gap),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              (widget.deposit ? 'plan.put_in' : 'plan.take_out').tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '€ '),
            ),
            Text(
              (widget.deposit ? 'plan.free_in_account' : 'plan.in_pot').tr(namedArgs: {'amount': money(widget.limit)}),
              style: TextStyle(color: t.muted, fontSize: 12.5),
            ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: 'add.note_hint'.tr()),
            ),
            FilledButton(onPressed: _save, child: Text('preset.save'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Create or edit a piggy bank. One linked to a planned expense takes its
/// goal and date from it.
class PotSheet extends ConsumerStatefulWidget {
  const PotSheet({super.key, this.pot});
  final Pot? pot;

  static Future<void> open(BuildContext context, Pot? pot) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PotSheet(pot: pot),
  );

  @override
  ConsumerState<PotSheet> createState() => _PotSheetState();
}

class _PotSheetState extends ConsumerState<PotSheet> {
  late final _name = TextEditingController(text: widget.pot?.name);
  late final _target = TextEditingController(
    text: widget.pot?.targetCents == null
        ? ''
        : NumberFormat.decimalPattern(moneyLocale).format(widget.pot!.targetCents! / 100),
  );
  late String _icon = widget.pot?.icon ?? 'piggy-bank';
  late int _color = widget.pot?.color ?? 6;
  late int? _accountId = widget.pot?.accountId;
  late DateTime? _date = widget.pot?.targetDate;

  bool get _linked => widget.pot?.recurringId != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _target.text.trim();
    final target = text.isEmpty ? null : parseAmount(text);
    if (_name.text.trim().isEmpty || _accountId == null || (text.isNotEmpty && target == null)) return;
    final p = widget.pot;
    await ref
        .read(repoProvider)
        .savePot(
          Pot(
            id: p?.id,
            accountId: _accountId!,
            name: _name.text.trim(),
            icon: _icon,
            color: _color,
            targetCents: target == null ? null : (target * 100).round(),
            targetDate: _date,
            recurringId: p?.recurringId,
            autoMonth: p?.autoMonth,
            position: p?.position ?? 0,
          ),
        );
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _close() async {
    if (!await confirm(context, 'plan.close_pot'.tr(), 'plan.close_pot_body'.tr())) return;
    await ref.read(repoProvider).closePot(widget.pot!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    // Close the sheet and the pot page under it, which is the only place editing opens from.
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    if (lookup == null) return const SizedBox(height: 200);
    _accountId ??= lookup.mainAccount?.id;
    final t = context.tokens;
    final color = categoryColor(_color);
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
                (widget.pot == null ? 'plan.new_pot' : 'plan.edit_pot').tr(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (widget.pot == null) Text('plan.pot_hint'.tr(), style: TextStyle(color: t.muted, fontSize: 13)),
              Row(
                spacing: 10,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final icon = await pickIcon(context, current: _icon, color: color);
                      if (icon != null) setState(() => _icon = icon);
                    },
                    child: IconTile(icon: _icon, color: color, size: 52),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: widget.pot == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: 'plan.pot_name'.tr()),
                    ),
                  ),
                ],
              ),
              ColorRow(
                colors: categoryPalette.take(14).toList(),
                selected: _color,
                onChanged: (i) => setState(() => _color = i),
              ),
              Field(
                label: 'add.account'.tr(),
                child: Pill(
                  label: lookup.accounts[_accountId]?.name ?? '',
                  color: t.card2,
                  leading: SolarIcon.ui(Ui.card, size: 16, color: t.muted),
                  onTap: () async {
                    final a = await pickAccount(context, lookup.accounts.values.toList(), selectedId: _accountId);
                    if (a != null) setState(() => _accountId = a.id);
                  },
                ),
              ),
              if (_linked)
                Text('plan.pot_linked'.tr(), style: TextStyle(color: t.muted, fontSize: 13))
              else
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Field(
                        label: 'plan.goal'.tr(),
                        child: TextField(
                          controller: _target,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(prefixText: '€ ', hintText: 'plan.optional'.tr()),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Field(
                        label: 'plan.by'.tr(),
                        child: Pill(
                          label: _date == null
                              ? 'plan.optional'.tr()
                              : DateFormat.yMMMd(context.locale.languageCode).format(_date!),
                          color: t.card2,
                          leading: SolarIcon.ui(Ui.calendar, size: 16, color: t.muted),
                          onTap: () async {
                            final d = await pickDay(context, initial: _date ?? DateTime.now());
                            if (d != null) setState(() => _date = d);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              Row(
                spacing: 8,
                children: [
                  if (widget.pot != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _close,
                        child: Text('plan.close'.tr(), style: TextStyle(color: t.expense)),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: FilledButton(onPressed: _save, child: Text('preset.save'.tr())),
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
