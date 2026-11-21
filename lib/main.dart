import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/backup.dart';
import 'data/db.dart';
import 'data/repo.dart';
import 'format.dart';
import 'notify.dart';
import 'state.dart';
import 'theme/theme.dart';
import 'ui/app_lock.dart';
import 'ui/backup_actions.dart';
import 'ui/plan_actions.dart';
import 'ui/shell.dart';

const supportedLocales = [Locale('en'), Locale('it')];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final device = PlatformDispatcher.instance.locale;
  deviceRegion = device.countryCode ?? '';
  moneyLocale = Intl.verifiedLocale(device.toString(), NumberFormat.localeExists, onFailure: (_) => 'en')!;
  final (db, prefs) = (await openAppDb(italian: device.languageCode == 'it'), await SharedPreferences.getInstance());
  // Documents is visible in Files > On My iPhone > Spicci.
  final autoBackup = AutoBackup(Directory(p.join((await getApplicationDocumentsDirectory()).path, 'Backups')));
  runApp(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      fallbackLocale: supportedLocales.first,
      useOnlyLangCode: true,
      child: ProviderScope(
        overrides: [
          repoProvider.overrideWithValue(Repo(db)),
          prefsProvider.overrideWithValue(prefs),
          autoBackupProvider.overrideWithValue(autoBackup),
          notificationsProvider.overrideWithValue(Notifications()),
        ],
        child: const SpicciApp(),
      ),
    ),
  );
}

class SpicciApp extends ConsumerStatefulWidget {
  const SpicciApp({super.key});

  @override
  ConsumerState<SpicciApp> createState() => _SpicciAppState();
}

class _SpicciAppState extends ConsumerState<SpicciApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back up at launch and whenever the app goes to the background, so today's copy is current.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(backupNow(ref));
      // After the first frame, so translations are loaded for the notification buttons.
      final notifications = ref.read(notificationsProvider)
        ..onAction = (action, id) => handleNotificationAction(ref, action, id);
      await notifications.init();
      await refreshPlan(ref);
    });
    _lifecycle = AppLifecycleListener(
      onHide: () => backupNow(ref),
      // The saving day may pass while the app sits in the background.
      onResume: () => refreshPlan(ref),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'Spicci',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: context.localizationDelegates,
    supportedLocales: context.supportedLocales,
    locale: context.locale,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    home: const AppLock(child: Shell()),
  );
}
