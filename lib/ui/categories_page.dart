import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'pickers.dart';
import 'solar.dart';
import 'widgets.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  var _type = TxType.expense;

  @override
  Widget build(BuildContext context) {
    final all = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.deletedAt == null && c.matches(_type))
        .toList();
    final children = groupBy(all.where((c) => c.parentId != null), (c) => c.parentId!);
    final parents = all.where((c) => c.parentId == null).toList();
    final t = context.tokens;

    return SubPage(
      title: 'categories.title'.tr(),
      actions: [
        IconButton(
          onPressed: () => CategorySheet.open(context, type: _type),
          icon: SolarIcon.ui(Ui.addCircle),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(gap, 4, gap, 8),
            child: Row(
              spacing: 8,
              children: [
                for (final type in [TxType.expense, TxType.income])
                  Expanded(
                    child: Material(
                      color: _type == type ? t.card2 : t.card,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _type = type),
                        child: SizedBox(
                          height: 42,
                          child: Center(
                            child: Text(
                              (type == TxType.expense ? 'categories.expenses' : 'categories.income').tr(),
                              style: TextStyle(fontWeight: FontWeight.w600, color: _type == type ? t.ink : t.muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            // The list is the scrollable itself, so dragging near an edge auto-scrolls.
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(gap, 0, gap, 40),
              buildDefaultDragHandles: false,
              itemCount: parents.length,
              onReorder: (from, to) async {
                final ids = parents.map((c) => c.id!).toList();
                ids.insert(to > from ? to - 1 : to, ids.removeAt(from));
                await ref.read(repoProvider).reorder('categories', ids);
                ref.read(dataVersionProvider.notifier).bump();
              },
              itemBuilder: (context, i) {
                final p = parents[i];
                final subs = children[p.id] ?? const <Category>[];
                final color = categoryColor(p.color);
                return Padding(
                  key: ValueKey(p.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: t.card,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => CategorySheet.open(context, type: _type, category: p),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                            child: Row(
                              spacing: 12,
                              children: [
                                IconTile(icon: p.icon, color: color),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'categories.add_sub'.tr(),
                                  onPressed: () => CategorySheet.open(context, type: _type, parentId: p.id),
                                  icon: SolarIcon.ui(Ui.addCircle, size: 20, color: t.muted),
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
                        for (final s in subs)
                          InkWell(
                            onTap: () => CategorySheet.open(context, type: _type, category: s),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(30, 8, 14, 8),
                              child: Row(
                                spacing: 12,
                                children: [
                                  IconTile(icon: s.icon, color: color, size: 30),
                                  Expanded(
                                    child: Text(
                                      s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (subs.isNotEmpty) const SizedBox(height: 6),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Create or edit a category. A subcategory takes its colour from its parent.
class CategorySheet extends ConsumerStatefulWidget {
  const CategorySheet({super.key, required this.type, this.category, this.parentId});
  final TxType type;
  final Category? category;
  final int? parentId;

  static Future<void> open(BuildContext context, {required TxType type, Category? category, int? parentId}) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => CategorySheet(type: type, category: category, parentId: parentId),
      );

  @override
  ConsumerState<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<CategorySheet> {
  late final _name = TextEditingController(text: widget.category?.name);
  late String _icon = widget.category?.icon ?? 'tag';
  late int _color = widget.category?.color ?? 0;
  late int? _parentId = widget.category?.parentId ?? widget.parentId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(Lookup lookup) async {
    if (_name.text.trim().isEmpty) return;
    final c = widget.category;
    final parent = lookup.categories[_parentId];
    await ref
        .read(repoProvider)
        .saveCategory(
          Category(
            id: c?.id,
            name: _name.text.trim(),
            type: parent?.type ?? c?.type ?? widget.type.code,
            icon: _icon,
            color: parent?.color ?? _color,
            note: c?.note,
            parentId: _parentId,
            position: c?.position ?? 0,
          ),
        );
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'categories.delete_title'.tr(), 'categories.delete_body'.tr());
    if (!ok) return;
    await ref.read(repoProvider).deleteCategory(widget.category!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(lookupProvider).value;
    if (lookup == null) return const SizedBox(height: 200);
    final t = context.tokens;
    final c = widget.category;
    final parent = lookup.categories[_parentId];
    final color = categoryColor(parent?.color ?? _color);
    final hasChildren = c != null && lookup.categories.values.any((x) => x.parentId == c.id && x.deletedAt == null);
    final parentOptions = lookup.categories.values
        .where((x) => x.parentId == null && x.deletedAt == null && x.matches(widget.type) && x.id != c?.id)
        .sortedBy<num>((x) => x.position);

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
                (c == null ? 'categories.new' : 'categories.edit').tr(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
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
                      autofocus: c == null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: 'categories.name'.tr()),
                    ),
                  ),
                ],
              ),
              // A category with subcategories cannot become a subcategory itself.
              if (!hasChildren)
                Field(
                  label: 'categories.parent'.tr(),
                  child: Pill(
                    label: parent?.name ?? 'categories.no_parent'.tr(),
                    color: t.card2,
                    trailing: SolarIcon.ui(Ui.altArrowDown, size: 16, color: t.muted),
                    onTap: () async {
                      final o = await pickOption<int?>(context, [
                        Option(null, 'categories.no_parent'.tr()),
                        for (final p in parentOptions)
                          Option(
                            p.id,
                            p.name,
                            leading: IconTile(icon: p.icon, color: categoryColor(p.color), size: 32),
                          ),
                      ], selected: _parentId);
                      if (o != null) setState(() => _parentId = o.value);
                    },
                  ),
                ),
              if (parent == null)
                ColorRow(colors: categoryPalette, selected: _color, onChanged: (i) => setState(() => _color = i)),
              Row(
                spacing: 8,
                children: [
                  if (c != null)
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
