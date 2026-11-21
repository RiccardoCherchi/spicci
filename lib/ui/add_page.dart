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
import 'solar.dart';
import 'tag_sheet.dart';
import 'widgets.dart';

class AddPage extends ConsumerStatefulWidget {
  const AddPage({super.key, this.editing});
  final Txn? editing;

  static Future<void> open(BuildContext context, {Txn? editing}) =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AddPage(editing: editing)));

  @override
  ConsumerState<AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<AddPage> {
  late TxType _type;
  late String _input; // digits with '.' as the decimal point
  late DateTime _date;
  int? _categoryId;
  int? _accountId;
  int? _toAccountId;
  var _tags = <String>[];

  /// Piggy bank paying for this expense, if any.
  int? _potId;

  /// True once the user picks a category, so suggestions stop overriding it.
  var _categoryTouched = false;
  var _suggested = false;
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _type = e?.type ?? TxType.expense;
    _input = e == null ? '' : _centsToInput(e.amountCents);
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    _accountId = e?.accountId;
    _toAccountId = e?.toAccountId;
    _note.text = e?.note ?? '';
    _categoryTouched = e != null;
    _noteFocus.addListener(() => setState(() {}));
    _note.addListener(_suggest);
    if (e != null) {
      ref.read(transactionTagsProvider.future).then((all) {
        if (mounted) setState(() => _tags = [...?all[e.id]]);
      });
      ref.read(transactionPotsProvider.future).then((all) {
        if (mounted) setState(() => _potId = all[e.id]);
      });
    }
  }

  void _suggest() {
    if (_categoryTouched || _type == TxType.transfer) return;
    final suggester = ref.read(suggesterProvider).value;
    final lookup = ref.read(lookupProvider).value;
    if (suggester == null || lookup == null) return;
    final id = suggester.suggest(
      _note.text,
      allowed: (id) {
        final c = lookup.categories[id];
        return c != null && c.deletedAt == null && c.matches(_type);
      },
    );
    if (id != _categoryId) {
      setState(() {
        _categoryId = id;
        _suggested = id != null;
      });
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  static String _centsToInput(int cents) {
    final whole = cents ~/ 100, frac = cents % 100;
    return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}';
  }

  int get _cents {
    if (_input.isEmpty) return 0;
    final [whole, ...rest] = _input.split('.');
    final frac = rest.isEmpty ? '' : rest.first;
    return int.parse(whole.isEmpty ? '0' : whole) * 100 + int.parse(frac.padRight(2, '0'));
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '<') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (k == '.') {
        if (!_input.contains('.')) _input = _input.isEmpty ? '0.' : '$_input.';
      } else {
        final dot = _input.indexOf('.');
        if (dot >= 0 && _input.length - dot > 2) return;
        if (dot < 0 && _input.length >= 9) return;
        _input = _input == '0' ? k : _input + k;
      }
    });
  }

  String get _display {
    final [whole, ...rest] = (_input.isEmpty ? '0' : _input).split('.');
    final grouped = groupInt(int.parse(whole.isEmpty ? '0' : whole));
    return rest.isEmpty ? grouped : '$grouped${decimalSeparator()}${rest.first}';
  }

  Future<void> _save() async {
    if (_saving) return;
    String? error;
    if (_cents <= 0) {
      error = 'add.enter_amount';
    } else if (_accountId == null) {
      error = 'add.choose_account';
    } else if (_type == TxType.transfer && (_toAccountId == null || _toAccountId == _accountId)) {
      error = 'add.choose_other_account';
    } else if (_type != TxType.transfer && _categoryId == null) {
      error = 'add.choose_category';
    }
    if (error != null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.tr())));
      return;
    }
    _saving = true;
    final note = _note.text.trim();
    final txn = Txn(
      id: widget.editing?.id,
      date: _date,
      amountCents: _cents,
      type: _type,
      note: note.isEmpty ? null : note,
      categoryId: _type == TxType.transfer ? null : _categoryId,
      accountId: _accountId!,
      toAccountId: _type == TxType.transfer ? _toAccountId : null,
      recurringId: widget.editing?.recurringId,
    );
    final repo = ref.read(repoProvider);
    final potId = _type == TxType.expense ? _potId : null;
    txn.id == null
        ? await repo.insertTxn(txn, tags: _tags, potId: potId)
        : await repo.updateTxn(txn, tags: _tags, potId: potId);
    ref.read(dataVersionProvider.notifier).bump();
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('add.delete_title'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('add.cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('add.delete'.tr(), style: TextStyle(color: c.tokens.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repoProvider).deleteTxn(widget.editing!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await pickDay(context, initial: _date, marked: ref.read(markedDaysProvider).value ?? const {});
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickPot(List<Pot> pots) async {
    final o = await pickOption<int?>(context, [
      Option(null, 'add.no_pot'.tr()),
      for (final p in pots)
        Option(
          p.id,
          p.name,
          leading: IconTile(icon: p.icon, color: categoryColor(p.color), size: 32),
        ),
    ], selected: _potId);
    if (o != null) setState(() => _potId = o.value);
  }

  Future<void> _pickTags() async {
    final picked = await pickTags(context, selected: _tags, known: ref.read(tagsProvider).value ?? const []);
    if (picked != null) setState(() => _tags = picked);
  }

  Future<void> _pickAccount(Lookup lookup, {required bool destination}) async {
    final picked = await pickAccount(
      context,
      lookup.accounts.values.toList(),
      selectedId: destination ? _toAccountId : _accountId,
      excludeId: destination ? _accountId : null,
    );
    if (picked == null) return;
    setState(() {
      if (destination) {
        _toAccountId = picked.id;
      } else {
        _accountId = picked.id;
        // A piggy bank belongs to one account.
        _potId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    // Keep these loaded so the note, date and tag pickers can read them synchronously.
    ref
      ..watch(suggesterProvider)
      ..watch(markedDaysProvider)
      ..watch(tagsProvider);
    if (lookup == null) return const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
    _accountId ??= lookup.mainAccount?.id;
    final pots = (ref.watch(potsProvider).value ?? const <Pot>[])
        .where((p) => p.archivedAt == null && p.accountId == _accountId)
        .toList();
    final t = context.tokens;
    final keypad = !_noteFocus.hasFocus;
    final signed = switch (_type) {
      TxType.expense => '−${money(_cents)}',
      TxType.income => '+${money(_cents)}',
      TxType.transfer => money(_cents),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: gap),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  _RoundButton(icon: Ui.closeCircle, onTap: () => Navigator.pop(context)),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _TypeSwitch(
                        value: _type,
                        onChanged: (v) => setState(() {
                          _type = v;
                          final c = lookup.categories[_categoryId];
                          if (c != null && !c.matches(_type)) _categoryId = null;
                        }),
                      ),
                    ),
                  ),
                  widget.editing == null
                      ? const SizedBox(width: 44)
                      : _RoundButton(icon: Ui.trashBinMinimalistic, onTap: _delete, color: t.expense),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _noteFocus.unfocus,
                      child: _AmountDisplay(text: _display, empty: _input.isEmpty),
                    ),
                    const SizedBox(height: 10),
                    _NoteField(controller: _note, focusNode: _noteFocus),
                  ],
                ),
              ),
              if (_type == TxType.transfer)
                _TransferAccounts(
                  from: lookup.accounts[_accountId],
                  to: lookup.accounts[_toAccountId],
                  onFrom: () => _pickAccount(lookup, destination: false),
                  onTo: () => _pickAccount(lookup, destination: true),
                )
              else
                _CategoryPicker(
                  lookup: lookup,
                  type: _type,
                  selectedId: _categoryId,
                  suggested: _suggested,
                  onSelected: (id) => setState(() {
                    _categoryId = id;
                    _categoryTouched = true;
                    _suggested = false;
                  }),
                ),
              const SizedBox(height: 12),
              Row(
                spacing: 8,
                children: [
                  if (_type != TxType.transfer)
                    Expanded(
                      child: _MetaButton(
                        icon: Ui.card,
                        label: lookup.accounts[_accountId]?.name ?? 'add.account'.tr(),
                        onTap: () => _pickAccount(lookup, destination: false),
                      ),
                    ),
                  Expanded(
                    child: _MetaButton(
                      icon: Ui.calendar,
                      label: toBeginningOfSentenceCase(dayLabel(_date, context.locale.languageCode)),
                      onTap: _pickDate,
                    ),
                  ),
                  if (_type == TxType.expense && pots.isNotEmpty)
                    _potId == null
                        ? _MetaButton(icon: Ui.wallet, onTap: () => _pickPot(pots))
                        : Expanded(
                            child: _MetaButton(
                              icon: Ui.wallet,
                              label: pots.firstWhereOrNull((p) => p.id == _potId)?.name,
                              onTap: () => _pickPot(pots),
                            ),
                          ),
                  if (_tags.isEmpty)
                    _MetaButton(key: const ValueKey('tags'), icon: Ui.hashtag, onTap: _pickTags)
                  else
                    Expanded(
                      child: _MetaButton(
                        key: const ValueKey('tags'),
                        icon: Ui.hashtag,
                        label: _tags.join(', '),
                        onTap: _pickTags,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (keypad) _Keypad(onKey: _key),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('save'),
                onPressed: _save,
                child: Text(_cents == 0 ? 'add.save'.tr() : '${'add.save'.tr()} $signed'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.color});
  final Ui icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: SolarIcon.ui(icon, size: 22, color: color)),
      ),
    ),
  );
}

class _TypeSwitch extends StatelessWidget {
  const _TypeSwitch({required this.value, required this.onChanged});
  final TxType value;
  final ValueChanged<TxType> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in TxType.values)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(type);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: value == type ? t.card2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  txTypeKey(type).tr(),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: value == type ? t.ink : t.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.text, required this.empty});
  final String text;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '€',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: t.muted),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w700,
              letterSpacing: -2,
              color: empty ? t.muted : t.ink,
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(width: 3),
          _Caret(color: t.accentInk),
        ],
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.color});
  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _blink.drive(
      TweenSequence([
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 1),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 1),
      ]),
    ),
    child: Container(
      width: 3,
      height: 50,
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'add.note_hint'.tr(),
          fillColor: t.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

/// Horizontal strip of top-level categories, most used first, with the
/// subcategories of the selected one shown as chips underneath.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.lookup,
    required this.type,
    required this.selectedId,
    required this.suggested,
    required this.onSelected,
  });
  final bool suggested;
  final Lookup lookup;
  final TxType type;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(categoryUsageProvider).value ?? const {};
    final all = lookup.categories.values.where((c) => c.deletedAt == null && c.matches(type)).toList();
    final children = groupBy(all.where((c) => c.parentId != null), (c) => c.parentId!);
    int uses(Category c) => (usage[c.id] ?? 0) + (children[c.id]?.map((s) => usage[s.id] ?? 0).sum ?? 0);
    final parents = all.where((c) => c.parentId == null).toList()
      ..sort((a, b) {
        final byUse = uses(b).compareTo(uses(a));
        return byUse != 0 ? byUse : a.position.compareTo(b.position);
      });
    final selectedRoot = lookup.root(selectedId);
    final subs = (children[selectedRoot?.id] ?? const <Category>[]).sortedBy<num>((c) => c.position);
    final t = context.tokens;

    return Column(
      children: [
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: parents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final c = parents[i];
              final on = selectedRoot?.id == c.id;
              final color = categoryColor(c.color);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(c.id!);
                },
                child: SizedBox(
                  width: 66,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(color: on ? t.accentInk : Colors.transparent, width: 2),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconTile(icon: c.icon, color: color, size: 48),
                            if (on && suggested)
                              Positioned(
                                right: -6,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                                  child: SolarIcon.ui(Ui.starsMinimalistic, size: 12, color: t.onAccent),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? t.ink : t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: subs.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: subs.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final s = subs[i];
                        final on = s.id == selectedId;
                        return Pill(
                          label: s.name,
                          color: on ? t.accent.withValues(alpha: 0.18) : t.card,
                          leading: SolarIcon.category(s.icon, size: 16, color: on ? t.accentInk : t.muted),
                          // Tapping the selected subcategory goes back to its parent.
                          onTap: () => onSelected(on ? selectedRoot!.id! : s.id!),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TransferAccounts extends StatelessWidget {
  const _TransferAccounts({required this.from, required this.to, required this.onFrom, required this.onTo});
  final Account? from;
  final Account? to;
  final VoidCallback onFrom;
  final VoidCallback onTo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget side(String label, Account? a, VoidCallback onTap) => Expanded(
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 10,
              children: [
                IconTile(icon: a?.icon ?? 'wallet', color: accountColor(a?.color ?? 0), size: 36),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(color: t.muted, fontSize: 12)),
                      Text(
                        a?.name ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        side('add.from'.tr(), from, onFrom),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SolarIcon.ui(Ui.altArrowRight, color: t.muted, size: 18),
        ),
        side('add.to'.tr(), to, onTo),
      ],
    );
  }
}

class _MetaButton extends StatelessWidget {
  const _MetaButton({super.key, required this.icon, required this.onTap, this.label});
  final Ui icon;

  /// Without a label the button is a small square with the icon only.
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            SolarIcon.ui(icon, size: 18, color: context.tokens.muted),
            if (label != null)
              Flexible(
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '<'];
    final t = context.tokens;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.3,
      children: [
        for (final k in keys)
          Material(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey('key$k'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => onKey(k),
              child: Center(
                child: k == '<'
                    ? SolarIcon.ui(Ui.backspace, size: 24)
                    : Text(
                        k == '.' ? decimalSeparator() : k,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
