import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spicci/data/db.dart';
import 'package:spicci/data/repo.dart';
import 'package:spicci/state.dart';
import 'package:spicci/theme/theme.dart';
import 'package:spicci/ui/add_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the add page over an in-memory database and returns its repo.
Future<Repo> openAddPage(WidgetTester tester, {Future<void> Function(Repo repo)? before}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();

  final db = await openAppDb(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
  addTearDown(db.close);
  final repo = Repo(db);
  await before?.call(repo);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('it')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      child: ProviderScope(
        overrides: [repoProvider.overrideWithValue(repo)],
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: buildTheme(Brightness.dark),
            home: Builder(
              builder: (c) => TextButton(onPressed: () => AddPage.open(c), child: const Text('open')),
            ),
          ),
        ),
      ),
    ),
  );
  // Translations load from assets with real I/O, outside the fake clock.
  for (var i = 0; i < 50 && find.text('open').evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.tap(find.text('open'));
  await settle(tester);
  return repo;
}

Future<void> typeAmount(WidgetTester tester, List<String> keys) async {
  for (final k in keys) {
    await tester.tap(find.byKey(ValueKey('key$k')));
  }
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('save')));
  await settle(tester);
}

// The amount caret blinks forever, so pumpAndSettle would never return.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
