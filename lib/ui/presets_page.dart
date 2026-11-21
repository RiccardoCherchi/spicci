import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette.dart';
import '../format.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'pickers.dart';
import 'preset_sheet.dart';
import 'solar.dart';
import 'widgets.dart';

class PresetsPage extends ConsumerWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider).value ?? const <Preset>[];
    final lookup = ref.watch(lookupProvider).value;
    final t = context.tokens;
    return SubPage(
      title: 'presets.title'.tr(),
      actions: [IconButton(onPressed: () => PresetSheet.open(context, null), icon: SolarIcon.ui(Ui.addCircle))],
      body: presets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'presets.empty'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted),
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(gap, 8, gap, 40),
              buildDefaultDragHandles: false,
              itemCount: presets.length,
              onReorder: (from, to) async {
                final ids = presets.map((p) => p.id!).toList();
                ids.insert(to > from ? to - 1 : to, ids.removeAt(from));
                await ref.read(repoProvider).reorder('presets', ids);
                ref.read(dataVersionProvider.notifier).bump();
              },
              itemBuilder: (context, i) {
                final p = presets[i];
                final category = lookup?.categories[p.categoryId];
                return Padding(
                  key: ValueKey(p.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: t.card,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => PresetSheet.open(context, p),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(
                          spacing: 12,
                          children: [
                            IconTile(
                              icon: category?.icon ?? 'tag',
                              color: categoryColor(lookup?.root(p.categoryId)?.color ?? 0),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                  ),
                                  Text(
                                    '${category?.name ?? ''} · ${lookup?.accounts[p.accountId]?.name ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: t.muted, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            MoneyText(
                              money(p.amountCents),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: t.ink),
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
