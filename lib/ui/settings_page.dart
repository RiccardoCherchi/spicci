import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import/sossoldi_csv.dart';
import '../logic/ai.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'accounts_page.dart';
import 'app_lock.dart';
import 'ai_settings_page.dart';
import 'backup_actions.dart';
import 'categories_page.dart';
import 'pickers.dart';
import 'presets_page.dart';
import 'solar.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(lookupProvider).value;
    final main = lookup?.mainAccount;
    final theme = ref.watch(themeModeProvider);
    final t = context.tokens;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(gap, 8, gap, 130),
        children: [
          Text(
            'settings.title'.tr(),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          SectionHeader('settings.appearance'.tr()),
          _Segmented<ThemeMode>(
            value: theme,
            options: {
              ThemeMode.system: ('settings.theme_system'.tr(), Ui.monitor),
              ThemeMode.light: ('settings.theme_light'.tr(), Ui.sun),
              ThemeMode.dark: ('settings.theme_dark'.tr(), Ui.moon),
            },
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
          ),
          SectionHeader('lock.section'.tr()),
          Material(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            child: SwitchListTile.adaptive(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              value: ref.watch(lockEnabledProvider),
              activeTrackColor: t.accent,
              title: Text('lock.title'.tr(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text('lock.sub'.tr(), style: TextStyle(color: t.muted, fontSize: 12.5)),
              onChanged: (on) async {
                // Turning it on proves Face ID works first, so nobody locks themselves out.
                if (on && !await authenticate('lock.reason'.tr())) return;
                ref.read(lockEnabledProvider.notifier).set(on);
              },
            ),
          ),
          SectionHeader('settings.language'.tr()),
          _Segmented<String>(
            value: ref.watch(languageProvider),
            options: {
              'system': ('settings.lang_system'.tr(), Ui.global),
              'en': ('English', null),
              'it': ('Italiano', null),
            },
            onChanged: (code) {
              ref.read(languageProvider.notifier).set(code);
              code == 'system' ? context.resetLocale() : context.setLocale(Locale(code));
            },
          ),
          SectionHeader('settings.manage'.tr()),
          _Group(
            children: [
              _Row(icon: Ui.wallet, title: 'accounts.title'.tr(), onTap: () => _push(context, const AccountsPage())),
              _Row(
                icon: Ui.widget4,
                title: 'categories.title'.tr(),
                onTap: () => _push(context, const CategoriesPage()),
              ),
              _Row(icon: Ui.bolt, title: 'presets.title'.tr(), onTap: () => _push(context, const PresetsPage())),
              _Row(
                icon: Ui.calendar,
                title: 'settings.saving_day'.tr(),
                subtitle: 'settings.saving_day_sub'.tr(),
                value: 'settings.day_n'.tr(namedArgs: {'n': '${ref.watch(savingDayProvider)}'}),
                onTap: () async {
                  final o = await pickOption<int>(context, [
                    for (var d = 1; d <= 28; d++) Option(d, '$d'),
                  ], selected: ref.read(savingDayProvider));
                  if (o != null) ref.read(savingDayProvider.notifier).set(o.value);
                },
              ),
              _Row(
                icon: Ui.star,
                title: 'settings.default_account'.tr(),
                value: main?.name ?? 'settings.none'.tr(),
                onTap: lookup == null
                    ? null
                    : () async {
                        final a = await pickAccount(context, lookup.accounts.values.toList(), selectedId: main?.id);
                        if (a == null) return;
                        await ref.read(repoProvider).setMainAccount(a.id!);
                        ref.read(dataVersionProvider.notifier).bump();
                      },
              ),
            ],
          ),
          SectionHeader('analysis.title'.tr()),
          _Group(
            children: [
              _Row(
                icon: Ui.starsMinimalistic,
                title: 'ai.title'.tr(),
                subtitle: ref.watch(aiSettingsProvider).isComplete
                    ? '${aiPresets.firstWhere((p) => p.id == ref.watch(aiSettingsProvider).presetId).name} · ${ref.watch(aiSettingsProvider).model}'
                    : 'ai.off'.tr(),
                onTap: () => _push(context, const AiSettingsPage()),
              ),
            ],
          ),
          SectionHeader('backup.title'.tr()),
          _Group(
            children: [
              _Row(
                icon: Ui.folder,
                title: 'backup.folder'.tr(),
                value: ref.watch(backupFolderNameProvider).value,
                subtitle: ref.watch(backupFolderNameProvider).value == null
                    ? 'backup.folder_none'.tr()
                    : _ago(ref.watch(folderLastWriteProvider), 'backup.folder_last'),
                onTap: () => _folderActions(context, ref),
              ),
              _Row(
                icon: Ui.export,
                title: 'backup.export'.tr(),
                subtitle: _ago(ref.watch(lastExportProvider), 'backup.export_last'),
                onTap: () => exportBackup(context, ref),
              ),
              _Row(
                icon: Ui.history,
                title: 'backup.auto'.tr(),
                subtitle: 'backup.auto_sub'.tr(),
                onTap: () => showAutoBackups(context, ref),
              ),
              _Row(icon: Ui.import, title: 'backup.restore_file'.tr(), onTap: () => restoreFromFile(context, ref)),
            ],
          ),
          SectionHeader('settings.data'.tr()),
          _Group(
            children: [
              _Row(
                icon: Ui.import,
                title: 'settings.import_sossoldi'.tr(),
                subtitle: 'settings.import_sossoldi_sub'.tr(),
                onTap: () => importSossoldi(context, ref),
              ),
            ],
          ),
          SectionHeader('settings.about'.tr()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('settings.credits'.tr(), style: TextStyle(color: t.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// "Never", or the label at [prefix] followed by "today" or "N days ago".
  String _ago(DateTime? last, String prefix) {
    if (last == null) return 'backup.never'.tr();
    final days = DateTime.now().difference(last).inDays;
    return '${prefix.tr()}: ${days == 0 ? 'backup.today'.tr() : 'backup.days_ago'.plural(days)}';
  }

  Future<void> _folderActions(BuildContext context, WidgetRef ref) async {
    if (ref.read(backupFolderNameProvider).value == null) return chooseBackupFolder(context, ref);
    final o = await pickOption<String>(context, [
      Option('now', 'backup.folder_now'.tr(), leading: SolarIcon.ui(Ui.export)),
      Option('change', 'backup.folder_change'.tr(), leading: SolarIcon.ui(Ui.folder)),
      Option('remove', 'backup.folder_remove'.tr(), leading: SolarIcon.ui(Ui.closeCircle)),
    ]);
    if (o == null || !context.mounted) return;
    switch (o.value) {
      case 'now':
        await backupNow(ref);
      case 'change':
        await chooseBackupFolder(context, ref);
      case 'remove':
        await ref.read(backupFolderProvider).clear();
        ref.invalidate(backupFolderNameProvider);
    }
  }

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  static Future<void> importSossoldi(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text), margin: const EdgeInsets.fromLTRB(gap, 0, gap, 96)));
    final path = (await FilePicker.pickFiles()).firstOrNull?.path;
    if (path == null || !context.mounted) return;

    final SossoldiData data;
    try {
      data = parseSossoldiCsv(await File(path).readAsString());
    } on Object catch (e) {
      say('settings.read_failed'.tr(namedArgs: {'error': '$e'}));
      return;
    }
    if (!context.mounted) return;

    final body = [
      'settings.replace_body'.tr(
        namedArgs: {
          'accounts': '${data.accounts.length}',
          'categories': '${data.categories.length}',
          'transactions': '${data.transactions.length}',
        },
      ),
      if (data.skipped > 0) 'settings.skipped'.tr(namedArgs: {'n': '${data.skipped}'}),
      '',
      'settings.replace_warning'.tr(),
    ].join('\n');
    if (!await confirm(context, 'settings.replace_title'.tr(), body, action: 'settings.replace'.tr())) return;

    try {
      final db = ref.read(repoProvider).db;
      // Keep today's state as an automatic backup, so the import can be undone.
      await ref.read(autoBackupProvider).run(db);
      await replaceWithSossoldi(db, data);
      ref.read(dataVersionProvider.notifier).bump();
      say('settings.imported'.tr(namedArgs: {'n': '${data.transactions.length}'}));
    } on Object catch (e) {
      say('settings.import_failed'.tr(namedArgs: {'error': '$e'}));
    }
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, (String, Ui?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          for (final MapEntry(key: k, value: (label, icon)) in options.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: k == value ? t.card2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      if (icon != null) SolarIcon.ui(icon, size: 17, color: k == value ? t.ink : t.muted),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: k == value ? t.ink : t.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.value, this.onTap});
  final Ui icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: t.card2, borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: SolarIcon.ui(icon, size: 20),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: t.muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (value != null)
              // Capped instead of flexible, so the title keeps the room it needs.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 14),
                ),
              ),
            SolarIcon.ui(Ui.altArrowRight, size: 16, color: t.muted),
          ],
        ),
      ),
    );
  }
}
