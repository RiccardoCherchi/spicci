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

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => a.deletedAt == null)
        .toList();
    final balances = ref.watch(balancesProvider).value ?? const {};
    final split = ref.watch(accountSplitProvider).value ?? const {};
    final t = context.tokens;
    return SubPage(
      title: 'accounts.title'.tr(),
      actions: [IconButton(onPressed: () => _AccountSheet.open(context, null), icon: SolarIcon.ui(Ui.addCircle))],
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 40),
        buildDefaultDragHandles: false,
        itemCount: accounts.length,
        onReorder: (from, to) async {
          final ids = accounts.map((a) => a.id!).toList();
          ids.insert(to > from ? to - 1 : to, ids.removeAt(from));
          await ref.read(repoProvider).reorder('accounts', ids);
          ref.read(dataVersionProvider.notifier).bump();
        },
        itemBuilder: (context, i) {
          final a = accounts[i];
          return Padding(
            key: ValueKey(a.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: t.card,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _AccountSheet.open(context, a),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(
                    spacing: 12,
                    children: [
                      IconTile(icon: a.icon, color: accountColor(a.color)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              spacing: 6,
                              children: [
                                Flexible(
                                  child: Text(
                                    a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                  ),
                                ),
                                if (a.isMain) SolarIcon.ui(Ui.star, size: 15, color: t.accentInk),
                              ],
                            ),
                            if (!a.countNetWorth || !a.active || (split[a.id]?.inPots ?? 0) != 0)
                              Text(
                                [
                                  if ((split[a.id]?.inPots ?? 0) != 0)
                                    'home.in_pots'.tr(namedArgs: {'amount': money(split[a.id]!.inPots)}),
                                  if (!a.active) 'accounts.archived'.tr(),
                                  if (!a.countNetWorth) 'accounts.not_counted'.tr(),
                                ].join(' · '),
                                style: TextStyle(color: t.muted, fontSize: 12.5),
                              ),
                          ],
                        ),
                      ),
                      MoneyText(
                        money(balances[a.id] ?? 0),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          color: (balances[a.id] ?? 0) < 0 ? t.expense : t.ink,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: SolarIcon.ui(Ui.hamburgerMenu, size: 20, color: t.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.account});
  final Account? account;

  static Future<void> open(BuildContext context, Account? account) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AccountSheet(account: account),
  );

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late final _name = TextEditingController(text: widget.account?.name);
  late final _start = TextEditingController(
    text: widget.account == null
        ? ''
        : NumberFormat.decimalPattern(moneyLocale).format(widget.account!.startingCents / 100),
  );
  late String _icon = widget.account?.icon ?? 'wallet';
  late int _color = widget.account?.color ?? 0;
  late bool _counted = widget.account?.countNetWorth ?? true;
  late bool _active = widget.account?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _start.text.trim();
    final start = text.isEmpty ? 0 : parseAmount(text);
    if (_name.text.trim().isEmpty || start == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('accounts.fill_all'.tr())));
      return;
    }
    final a = widget.account;
    final repo = ref.read(repoProvider);
    final id = await repo.saveAccount(
      Account(
        id: a?.id,
        name: _name.text.trim(),
        icon: _icon,
        color: _color,
        startingCents: (start * 100).round(),
        isMain: a?.isMain ?? false,
        active: _active,
        countNetWorth: _counted,
        position: a?.position ?? 0,
      ),
    );
    final hasMain = (await repo.accounts()).any((x) => x.isMain && x.deletedAt == null);
    if (!hasMain) await repo.setMainAccount(id);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'accounts.delete_title'.tr(), 'accounts.delete_body'.tr());
    if (!ok) return;
    await ref.read(repoProvider).deleteAccount(widget.account!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = widget.account;
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
                (a == null ? 'accounts.new' : 'accounts.edit').tr(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Row(
                spacing: 10,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final icon = await pickIcon(context, current: _icon, color: accountColor(_color));
                      if (icon != null) setState(() => _icon = icon);
                    },
                    child: IconTile(icon: _icon, color: accountColor(_color), size: 52),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: a == null,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(hintText: 'accounts.name'.tr()),
                    ),
                  ),
                ],
              ),
              ColorRow(colors: accountPalette, selected: _color, onChanged: (i) => setState(() => _color = i)),
              Field(
                label: 'accounts.starting'.tr(),
                child: TextField(
                  controller: _start,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(prefixText: '€ ', hintText: '0'),
                ),
              ),
              _Switch(label: 'accounts.count'.tr(), value: _counted, onChanged: (v) => setState(() => _counted = v)),
              _Switch(label: 'accounts.active'.tr(), value: _active, onChanged: (v) => setState(() => _active = v)),
              if (a != null && !a.isMain)
                TextButton(
                  onPressed: () async {
                    await ref.read(repoProvider).setMainAccount(a.id!);
                    ref.read(dataVersionProvider.notifier).bump();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text('accounts.make_default'.tr()),
                ),
              Row(
                spacing: 8,
                children: [
                  if (a != null)
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
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: context.tokens.accent),
    ],
  );
}
