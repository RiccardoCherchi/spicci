import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'date_sheet.dart';
import 'plan_actions.dart';
import 'solar.dart';
import 'widgets.dart';

/// Confirms a due item: the real amount may differ from the planned one.
class PaySheet extends ConsumerStatefulWidget {
  const PaySheet({super.key, required this.item});
  final Scheduled item;

  static Future<void> open(BuildContext context, Scheduled item) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PaySheet(item: item),
  );

  @override
  ConsumerState<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<PaySheet> {
  late final _amount = TextEditingController(
    text: NumberFormat.decimalPattern(moneyLocale).format(widget.item.amountCents / 100),
  );
  late DateTime _date = DateTime.now();
  late int _accountId = widget.item.accountId;
  var _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _cents {
    final n = parseAmount(_amount.text.trim());
    return n == null || n <= 0 ? null : (n * 100).round();
  }

  Future<void> _pay() async {
    final cents = _cents;
    if (cents == null || _busy) return;
    _busy = true;
    await ref.read(repoProvider).payScheduled(widget.item, amountCents: cents, date: _date, accountId: _accountId);
    HapticFeedback.mediumImpact();
    ref.read(dataVersionProvider.notifier).bump();
    await refreshPlan(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lookup = ref.watch(lookupProvider).value;
    final pots = ref.watch(potsProvider).value ?? const <Pot>[];
    final balances = ref.watch(potBalancesProvider).value ?? const {};
    final pot = pots.where((p) => p.recurringId == widget.item.id && p.archivedAt == null).firstOrNull;
    final fromPot = pot == null ? 0 : ((balances[pot.id] ?? 0).clamp(0, _cents ?? 0));

    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 0, gap, MediaQuery.viewInsetsOf(context).bottom + gap),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Text(widget.item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '€ '),
            ),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Pill(
                    label: lookup?.accounts[_accountId]?.name ?? '',
                    color: t.card2,
                    leading: SolarIcon.ui(Ui.card, size: 16, color: t.muted),
                    onTap: lookup == null
                        ? null
                        : () async {
                            final a = await pickAccount(
                              context,
                              lookup.accounts.values.toList(),
                              selectedId: _accountId,
                            );
                            if (a != null) setState(() => _accountId = a.id!);
                          },
                  ),
                ),
                Expanded(
                  child: Pill(
                    label: toBeginningOfSentenceCase(dayLabel(_date, context.locale.languageCode)),
                    color: t.card2,
                    leading: SolarIcon.ui(Ui.calendar, size: 16, color: t.muted),
                    onTap: () async {
                      final d = await pickDay(context, initial: _date);
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                ),
              ],
            ),
            if (pot != null && fromPot > 0)
              Text(
                'plan.from_pot'.tr(namedArgs: {'amount': money(fromPot), 'pot': pot.name}),
                style: TextStyle(color: t.accentInk, fontWeight: FontWeight.w600),
              ),
            FilledButton(onPressed: _cents == null ? null : _pay, child: Text('plan.paid'.tr())),
          ],
        ),
      ),
    );
  }
}
