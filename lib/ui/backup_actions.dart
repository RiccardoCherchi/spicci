import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../state.dart';
import '../theme/theme.dart';
import 'solar.dart';

void _say(BuildContext context, String text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(text), margin: const EdgeInsets.fromLTRB(gap, 0, gap, 96)));

/// Writes today's backup on the phone and, when one is chosen, in the backup folder.
/// Failures are silent: the folder status in Settings and the Home reminder show them.
Future<void> backupNow(WidgetRef ref) async {
  final db = ref.read(repoProvider).db;
  await ref.read(autoBackupProvider).run(db);
  if (await ref.read(backupFolderNameProvider.future) == null) return;
  try {
    await ref.read(backupFolderProvider).write(await exportJson(db));
    ref.read(folderLastWriteProvider.notifier).mark();
  } on Object {
    // Folder moved, deleted or offline; the status shows it as stale.
  }
}

/// Lets the user pick the backup folder and writes a first backup there.
Future<void> chooseBackupFolder(BuildContext context, WidgetRef ref) async {
  final String? name;
  try {
    name = await ref.read(backupFolderProvider).pick();
  } on Object catch (e) {
    if (context.mounted) _say(context, '$e');
    return;
  }
  if (name == null) return;
  ref.invalidate(backupFolderNameProvider);
  await backupNow(ref);
  if (context.mounted) _say(context, 'backup.folder_set'.tr(namedArgs: {'name': name}));
}

/// Opens the share sheet with a fresh backup file, so it can be saved to iCloud Drive.
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  final box = context.findRenderObject() as RenderBox?;
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final file = File(p.join((await getTemporaryDirectory()).path, 'spicci-backup-$day.json'));
  await file.writeAsString(await exportJson(ref.read(repoProvider).db));
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      // Needed on iPad, harmless on iPhone.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
  if (result.status == ShareResultStatus.success) {
    ref.read(lastExportProvider.notifier).mark();
    if (context.mounted) _say(context, 'backup.exported'.tr());
  }
}

Future<void> restoreFromFile(BuildContext context, WidgetRef ref) async {
  final path = (await FilePicker.pickFiles()).firstOrNull?.path;
  if (path == null || !context.mounted) return;
  await _restore(context, ref, File(path));
}

/// Lists the automatic backups and restores the chosen one.
Future<void> showAutoBackups(BuildContext context, WidgetRef ref) async {
  final files = ref.read(autoBackupProvider).list();
  final lang = context.locale.languageCode;
  final picked = await showModalBottomSheet<File>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text('backup.auto_hint'.tr(), style: TextStyle(color: sheet.tokens.muted, fontSize: 13)),
          ),
          if (files.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('backup.auto_none'.tr())),
          for (final f in files)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: SolarIcon.ui(Ui.history),
              title: Text(
                DateFormat.yMMMEd(lang).format(f.lastModifiedSync()),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(DateFormat.Hm(lang).format(f.lastModifiedSync())),
              trailing: Text('backup.restore'.tr(), style: TextStyle(color: sheet.tokens.accentInk)),
              onTap: () => Navigator.pop(sheet, f),
            ),
        ],
      ),
    ),
  );
  if (picked != null && context.mounted) await _restore(context, ref, picked);
}

Future<void> _restore(BuildContext context, WidgetRef ref, File file) async {
  final Backup backup;
  try {
    backup = parseBackup(await file.readAsString());
  } on Object catch (e) {
    if (context.mounted) _say(context, 'settings.read_failed'.tr(namedArgs: {'error': '$e'}));
    return;
  }
  if (!context.mounted) return;
  final when = backup.exportedAt == null
      ? ''
      : '${DateFormat.yMMMEd(context.locale.languageCode).add_Hm().format(backup.exportedAt!)}\n';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('settings.replace_title'.tr()),
      content: Text(
        '$when${'settings.replace_body'.tr(namedArgs: {'accounts': '${backup.count('accounts')}', 'categories': '${backup.count('categories')}', 'transactions': '${backup.count('transactions')}'})}'
        '\n\n${'backup.safety'.tr()}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('add.cancel'.tr())),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('settings.replace'.tr(), style: TextStyle(color: c.tokens.expense)),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final db = ref.read(repoProvider).db;
  try {
    // Keep today's state as an automatic backup, so a wrong restore can be undone.
    await ref.read(autoBackupProvider).run(db);
    await restoreBackup(db, backup);
    ref.read(dataVersionProvider.notifier).bump();
    if (context.mounted) _say(context, 'backup.restored'.tr());
  } on Object catch (e) {
    if (context.mounted) _say(context, 'settings.import_failed'.tr(namedArgs: {'error': '$e'}));
  }
}
