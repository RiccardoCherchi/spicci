import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'pickers.dart';
import 'solar.dart';
import 'widgets.dart';

/// Monthly limit for a top-level expense category.
class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key, this.budget});
  final Budget? budget;

  static Future<void> open(BuildContext context, Budget? budget) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => BudgetSheet(budget: budget),
  );

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  late final _amount = TextEditingController(
    text: widget.budget == null
        ? ''
        : NumberFormat.decimalPattern(moneyLocale).format(widget.budget!.amountCents / 100),
  );
  late int? _categoryId = widget.budget?.categoryId;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = parseAmount(_amount.text.trim());
    if (_categoryId == null || n == null || n <= 0) return;
    await ref
        .read(repoProvider)
        .saveBudget(Budget(id: widget.budget?.id, categoryId: _categoryId!, amountCents: (n * 100).round()));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(repoProvider).deleteBudget(widget.budget!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    if (lookup == null) return const SizedBox(height: 200);
    final t = context.tokens;
    final roots = lookup.categories.values
        .where((c) => c.parentId == null && c.deletedAt == null && c.matches(TxType.expense))
        .sortedBy<num>((c) => c.position);
    final category = lookup.categories[_categoryId];
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 0, gap, MediaQuery.viewInsetsOf(context).bottom + gap),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Text(
              (widget.budget == null ? 'plan.new_budget' : 'plan.edit_budget').tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Pill(
              label: category?.name ?? 'preset.category'.tr(),
              color: t.card2,
              leading: category == null
                  ? SolarIcon.ui(Ui.tag, size: 16, color: t.muted)
                  : SolarIcon.category(category.icon, size: 18, color: categoryColor(category.color)),
              onTap: () async {
                final o = await pickOption<int>(context, [
                  for (final c in roots)
                    Option(
                      c.id!,
                      c.name,
                      leading: IconTile(icon: c.icon, color: categoryColor(c.color), size: 32),
                    ),
                ], selected: _categoryId);
                if (o != null) setState(() => _categoryId = o.value);
              },
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '€ ', hintText: 'plan.per_month'.tr()),
            ),
            Row(
              spacing: 8,
              children: [
                if (widget.budget != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _delete,
                      child: Text('add.delete'.tr(), style: TextStyle(color: t.expense)),
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
    );
  }
}
