import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'widgets.dart';

/// Create or edit a quick-expense preset.
class PresetSheet extends ConsumerStatefulWidget {
  const PresetSheet({super.key, this.preset});
  final Preset? preset;

  static Future<void> open(BuildContext context, Preset? preset) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PresetSheet(preset: preset),
  );

  @override
  ConsumerState<PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends ConsumerState<PresetSheet> {
  late final _label = TextEditingController(text: widget.preset?.label);
  late final _amount = TextEditingController(
    text: widget.preset == null
        ? ''
        : NumberFormat.decimalPattern(moneyLocale).format(widget.preset!.amountCents / 100),
  );
  late TxType _type = widget.preset?.type ?? TxType.expense;
  late int? _categoryId = widget.preset?.categoryId;
  late int? _accountId = widget.preset?.accountId;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  int? get _cents {
    final n = parseAmount(_amount.text.trim());
    return n == null ? null : (n * 100).round();
  }

  Future<void> _save() async {
    final cents = _cents;
    if (_label.text.trim().isEmpty || cents == null || cents <= 0 || _accountId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('preset.fill_all'.tr())));
      return;
    }
    await ref
        .read(repoProvider)
        .savePreset(
          Preset(
            id: widget.preset?.id,
            label: _label.text.trim(),
            amountCents: cents,
            type: _type,
            categoryId: _categoryId,
            accountId: _accountId!,
            position: widget.preset?.position ?? 0,
          ),
        );
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(repoProvider).deletePreset(widget.preset!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    if (lookup == null) return const SizedBox(height: 200);
    _accountId ??= lookup.mainAccount?.id;
    final categories = lookup.categories.values.where((c) => c.deletedAt == null && c.matches(_type)).toList()
      ..sort((a, b) => _sortKey(lookup, a).compareTo(_sortKey(lookup, b)));
    final accounts = lookup.accounts.values.where((a) => a.deletedAt == null && a.active).toList();
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
              (widget.preset == null ? 'preset.new_title' : 'preset.edit_title').tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Row(
              spacing: 8,
              children: [
                for (final type in [TxType.expense, TxType.income])
                  Pill(
                    label: txTypeKey(type).tr(),
                    color: _type == type ? t.accent.withValues(alpha: 0.18) : t.card2,
                    onTap: () => setState(() {
                      _type = type;
                      _categoryId = null;
                    }),
                  ),
              ],
            ),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _label,
                    autofocus: widget.preset == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: 'preset.name'.tr()),
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
            DropdownMenu<int>(
              key: ValueKey(_type),
              expandedInsets: EdgeInsets.zero,
              hintText: 'preset.category'.tr(),
              initialSelection: _categoryId,
              menuHeight: 320,
              onSelected: (v) => _categoryId = v,
              dropdownMenuEntries: [
                for (final c in categories)
                  DropdownMenuEntry(
                    value: c.id!,
                    label: c.parentId == null ? c.name : '${lookup.categories[c.parentId]?.name} › ${c.name}',
                  ),
              ],
            ),
            DropdownMenu<int>(
              expandedInsets: EdgeInsets.zero,
              hintText: 'preset.account'.tr(),
              initialSelection: _accountId,
              onSelected: (v) => _accountId = v,
              dropdownMenuEntries: [for (final a in accounts) DropdownMenuEntry(value: a.id!, label: a.name)],
            ),
            Row(
              spacing: 8,
              children: [
                if (widget.preset != null)
                  Expanded(
                    child: OutlinedButton(onPressed: _delete, child: Text('preset.delete'.tr())),
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

  /// Keeps subcategories right after their parent.
  String _sortKey(Lookup lookup, Category c) {
    final parent = lookup.root(c.id) ?? c;
    final own = c.parentId == null ? '' : c.position.toString().padLeft(5, '0');
    return '${parent.position.toString().padLeft(5, '0')}${parent.id}|$own';
  }
}
