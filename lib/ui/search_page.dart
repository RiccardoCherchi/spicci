import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../logic/filter.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'date_sheet.dart';
import 'home_page.dart';
import 'pickers.dart';
import 'solar.dart';
import 'widgets.dart';

enum _Period { all, thisMonth, lastMonth, last30, thisYear, custom }

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _query = TextEditingController();
  var _period = _Period.all;
  DateTime? _from;
  DateTime? _to;
  TxType? _type;
  int? _categoryId;
  int? _accountId;
  String? _tag;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    return switch (_period) {
      _Period.all => (null, null),
      _Period.thisMonth => (DateTime(now.year, now.month), now),
      _Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month, 0)),
      _Period.last30 => (now.subtract(const Duration(days: 29)), now),
      _Period.thisYear => (DateTime(now.year), now),
      _Period.custom => (_from, _to),
    };
  }

  String _periodLabel(String lang) => switch (_period) {
    _Period.custom when _from != null && _to != null =>
      '${DateFormat.MMMd(lang).format(_from!)} – ${DateFormat.MMMd(lang).format(_to!)}',
    final p => 'search.period_${p.name}'.tr(),
  };

  Future<void> _pickPeriod() async {
    final o = await pickOption(context, [
      for (final p in _Period.values) Option(p, 'search.period_${p.name}'.tr()),
    ], selected: _period);
    if (o == null || !mounted) return;
    if (o.value != _Period.custom) {
      setState(() => _period = o.value);
      return;
    }
    final from = await pickDay(context, initial: _from ?? DateTime.now().subtract(const Duration(days: 7)));
    if (from == null || !mounted) return;
    final to = await pickDay(context, initial: _to ?? DateTime.now());
    if (to == null) return;
    setState(() {
      _period = _Period.custom;
      _from = from.isAfter(to) ? to : from;
      _to = from.isAfter(to) ? from : to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider).value;
    final lookup = ref.watch(lookupProvider).value;
    final tags = ref.watch(transactionTagsProvider).value ?? const {};
    final knownTags = ref.watch(tagsProvider).value ?? const <String>[];
    final t = context.tokens;
    final lang = context.locale.languageCode;
    if (txns == null || lookup == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
    }

    final (from, to) = _range;
    final filter = TxnFilter(
      query: _query.text,
      type: _type,
      categoryId: _categoryId,
      accountId: _accountId,
      tag: _tag,
      from: from,
      to: to,
    );
    final results = filter.isEmpty
        ? const <Txn>[]
        : applyFilter(filter, txns, categories: lookup.categories, accounts: lookup.accounts, tags: tags);
    final groups = <DayGroup>[];
    for (final tx in results) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (groups.lastOrNull?.day != day) groups.add(DayGroup(day, []));
      groups.last.txns.add(tx);
    }
    final out = results.where((x) => x.type == TxType.expense).map((x) => x.amountCents).sum;
    final inc = results.where((x) => x.type == TxType.income).map((x) => x.amountCents).sum;

    Widget chip(String label, bool active, VoidCallback onTap, VoidCallback? onClear) => Pill(
      label: label,
      color: active ? t.accent.withValues(alpha: 0.18) : t.card,
      trailing: active && onClear != null
          ? GestureDetector(
              onTap: onClear,
              child: SolarIcon.ui(Ui.closeCircle, size: 16, color: t.accentInk),
            )
          : SolarIcon.ui(Ui.altArrowDown, size: 14, color: t.muted),
      onTap: onTap,
    );

    final categoryOptions = lookup.categories.values
        .where((c) => c.deletedAt == null && c.parentId == null)
        .sortedBy<num>((c) => c.position);
    final accountOptions = lookup.accounts.values.where((a) => a.deletedAt == null);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, gap, 0),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: SolarIcon.ui(Ui.altArrowLeft)),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'search.hint'.tr(),
                        fillColor: t.card,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(11),
                          child: SolarIcon.ui(Ui.magnifier, size: 20, color: t.muted),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(99),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: gap, vertical: 8),
                children: [
                  chip(
                    _periodLabel(lang),
                    _period != _Period.all,
                    _pickPeriod,
                    () => setState(() => _period = _Period.all),
                  ),
                  const SizedBox(width: 6),
                  chip(_type == null ? 'search.type'.tr() : txTypeKey(_type!).tr(), _type != null, () async {
                    final o = await pickOption<TxType>(context, [
                      for (final ty in TxType.values) Option(ty, txTypeKey(ty).tr()),
                    ], selected: _type);
                    if (o != null) setState(() => _type = o.value);
                  }, () => setState(() => _type = null)),
                  const SizedBox(width: 6),
                  chip(
                    lookup.categories[_categoryId]?.name ?? 'preset.category'.tr(),
                    _categoryId != null,
                    () async {
                      final o = await pickOption<int>(context, [
                        for (final c in categoryOptions)
                          Option(
                            c.id!,
                            c.name,
                            leading: IconTile(icon: c.icon, color: categoryColor(c.color), size: 32),
                          ),
                      ], selected: _categoryId);
                      if (o != null) setState(() => _categoryId = o.value);
                    },
                    () => setState(() => _categoryId = null),
                  ),
                  const SizedBox(width: 6),
                  chip(
                    lookup.accounts[_accountId]?.name ?? 'preset.account'.tr(),
                    _accountId != null,
                    () async {
                      final o = await pickOption<int>(context, [
                        for (final a in accountOptions)
                          Option(
                            a.id!,
                            a.name,
                            leading: IconTile(icon: a.icon, color: accountColor(a.color), size: 32),
                          ),
                      ], selected: _accountId);
                      if (o != null) setState(() => _accountId = o.value);
                    },
                    () => setState(() => _accountId = null),
                  ),
                  if (knownTags.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    chip(_tag == null ? 'search.tag'.tr() : '#$_tag', _tag != null, () async {
                      final o = await pickOption<String>(context, [
                        for (final name in knownTags) Option(name, '#$name'),
                      ], selected: _tag);
                      if (o != null) setState(() => _tag = o.value);
                    }, () => setState(() => _tag = null)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: filter.isEmpty
                  ? Center(
                      child: Text('search.start'.tr(), style: TextStyle(color: t.muted)),
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text('search.none'.tr(), style: TextStyle(color: t.muted)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(gap, 4, gap, 40),
                      itemCount: groups.length + 1,
                      itemBuilder: (context, i) => i == 0
                          ? _Summary(count: results.length, outCents: out, inCents: inc)
                          : DayCard(group: groups[i - 1], lookup: lookup, tags: tags, lang: lang),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.outCents, required this.inCents});
  final int count;
  final int outCents;
  final int inCents;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
              style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('search.results'.tr(), style: TextStyle(color: t.muted, fontSize: 12.5)),
                Text('$count', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          stat('add.expense'.tr(), '−${money(outCents)}', t.ink),
          stat('add.income'.tr(), '+${money(inCents)}', t.income),
        ],
      ),
    );
  }
}
