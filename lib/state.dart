import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/backup.dart';
import 'data/backup_folder.dart';
import 'data/models.dart';
import 'data/repo.dart';
import 'logic/ai.dart';
import 'logic/suggest.dart';
import 'notify.dart';

final repoProvider = Provider<Repo>((ref) => throw UnimplementedError('overridden in main'));
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('overridden in main'));
final autoBackupProvider = Provider<AutoBackup>((ref) => throw UnimplementedError('overridden in main'));

/// When the user last exported a backup out of the app (for example to iCloud Drive).
class LastExport extends Notifier<DateTime?> {
  static const _key = 'last_export';

  @override
  DateTime? build() => DateTime.tryParse(ref.read(prefsProvider).getString(_key) ?? '');

  void mark() {
    state = DateTime.now();
    ref.read(prefsProvider).setString(_key, state!.toIso8601String());
  }
}

final lastExportProvider = NotifierProvider<LastExport, DateTime?>(LastExport.new);

final backupFolderProvider = Provider<BackupFolder>((ref) => BackupFolder());

/// Name of the chosen backup folder, or null. Never throws: a missing or
/// unreachable folder simply reads as null.
final backupFolderNameProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref.watch(backupFolderProvider).name();
  } on Object {
    return null;
  }
});

/// When a backup last reached the backup folder.
class FolderLastWrite extends Notifier<DateTime?> {
  static const _key = 'folder_last_write';

  @override
  DateTime? build() => DateTime.tryParse(ref.read(prefsProvider).getString(_key) ?? '');

  void mark() {
    state = DateTime.now();
    ref.read(prefsProvider).setString(_key, state!.toIso8601String());
  }
}

final folderLastWriteProvider = NotifierProvider<FolderLastWrite, DateTime?>(FolderLastWrite.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() => ThemeMode.values.byName(ref.read(prefsProvider).getString(_key) ?? ThemeMode.system.name);

  void set(ThemeMode mode) {
    state = mode;
    ref.read(prefsProvider).setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// The language picked in Settings: 'system', 'en' or 'it'. easy_localization
/// applies it; this only remembers the choice, which its own state does not expose.
class LanguageNotifier extends Notifier<String> {
  static const _key = 'language';

  @override
  String build() => ref.read(prefsProvider).getString(_key) ?? 'system';

  void set(String code) {
    state = code;
    ref.read(prefsProvider).setString(_key, code);
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(LanguageNotifier.new);

/// Bumped after every write so all data providers reload.
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

FutureProvider<T> _data<T>(Future<T> Function(Repo repo) load) => FutureProvider<T>((ref) {
  ref.watch(dataVersionProvider);
  return load(ref.watch(repoProvider));
});

final accountsProvider = _data((r) => r.accounts());
final categoriesProvider = _data((r) => r.categories());
final transactionsProvider = _data((r) => r.transactions());
final presetsProvider = _data((r) => r.presets());
final balancesProvider = _data((r) => r.balances());
final tagsProvider = _data((r) => r.tags());
final transactionTagsProvider = _data((r) => r.transactionTags());

/// Sum of live accounts that count towards net worth.
final netWorthProvider = FutureProvider<int>((ref) async {
  final balances = await ref.watch(balancesProvider.future);
  final accounts = await ref.watch(accountsProvider.future);
  return accounts.where((a) => a.deletedAt == null && a.countNetWorth).map((a) => balances[a.id] ?? 0).sum;
});

class Lookup {
  Lookup(List<Account> accounts, List<Category> categories)
    : accounts = {for (final a in accounts) a.id!: a},
      categories = {for (final c in categories) c.id!: c};
  final Map<int, Account> accounts;
  final Map<int, Category> categories;

  Account? get mainAccount => accounts.values.firstWhereOrNull((a) => a.isMain && a.deletedAt == null);

  /// The top-level category, used for colour and grouping.
  Category? root(int? id) {
    final c = categories[id];
    return c?.parentId == null ? c : categories[c!.parentId] ?? c;
  }
}

final lookupProvider = FutureProvider<Lookup>(
  (ref) async => Lookup(await ref.watch(accountsProvider.future), await ref.watch(categoriesProvider.future)),
);

/// First day of the month shown on Home.
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void set(DateTime month) => state = DateTime(month.year, month.month);
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

bool _inMonth(DateTime d, DateTime month) => d.year == month.year && d.month == month.month;
int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

class MonthStats {
  MonthStats({
    required this.spentCents,
    required this.incomeCents,
    required this.cumulative,
    required this.previousCumulative,
    required this.deltaCents,
  });
  final int spentCents;
  final int incomeCents;

  /// Running expense total per day, up to today for the current month.
  final List<int> cumulative;
  final List<int> previousCumulative;

  /// Spent minus last month's spending up to the same day.
  final int deltaCents;
}

List<int> _cumulative(Iterable<Txn> expenses, DateTime month, int days) {
  final perDay = List.filled(days, 0);
  for (final t in expenses) {
    if (_inMonth(t.date, month)) perDay[t.date.day - 1] += t.amountCents;
  }
  var run = 0;
  return [for (final v in perDay) run += v];
}

final monthStatsProvider = FutureProvider<MonthStats>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  final txns = await ref.watch(transactionsProvider.future);
  final prev = DateTime(month.year, month.month - 1);
  final expenses = txns.where((t) => t.type == TxType.expense);
  final now = DateTime.now();
  final shownDays = _inMonth(now, month) ? now.day : _daysIn(month);

  final cumulative = _cumulative(expenses, month, _daysIn(month)).sublist(0, shownDays);
  final previous = _cumulative(expenses, prev, _daysIn(prev));
  final spent = cumulative.lastOrNull ?? 0;
  final prevSameDay = previous[(shownDays.clamp(1, previous.length)) - 1];
  return MonthStats(
    spentCents: spent,
    incomeCents: txns.where((t) => t.type == TxType.income && _inMonth(t.date, month)).map((t) => t.amountCents).sum,
    cumulative: cumulative,
    previousCumulative: previous,
    deltaCents: spent - prevSameDay,
  );
});

/// Months that have transactions, newest first, always including the current one.
final monthsProvider = FutureProvider<List<DateTime>>((ref) async {
  final now = DateTime.now();
  final months = {DateTime(now.year, now.month)};
  for (final t in await ref.watch(transactionsProvider.future)) {
    months.add(DateTime(t.date.year, t.date.month));
  }
  return months.toList()..sort((a, b) => b.compareTo(a));
});

class DayGroup {
  DayGroup(this.day, this.txns);
  final DateTime day;
  final List<Txn> txns;
  int get totalCents => txns.map((t) => t.signedCents).sum;
}

/// The selected month's transactions (already sorted newest first) grouped by day.
final dayGroupsProvider = FutureProvider<List<DayGroup>>((ref) async {
  final month = ref.watch(selectedMonthProvider);
  final groups = <DayGroup>[];
  for (final t in await ref.watch(transactionsProvider.future)) {
    if (!_inMonth(t.date, month)) continue;
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    if (groups.lastOrNull?.day != day) groups.add(DayGroup(day, []));
    groups.last.txns.add(t);
  }
  return groups;
});

/// How often each category was used; the add page shows frequent ones first.
final categoryUsageProvider = FutureProvider<Map<int, int>>((ref) async {
  final usage = <int, int>{};
  for (final t in await ref.watch(transactionsProvider.future)) {
    if (t.categoryId != null) usage.update(t.categoryId!, (n) => n + 1, ifAbsent: () => 1);
  }
  return usage;
});

/// Days that have at least one transaction, for the date picker dots.
final markedDaysProvider = FutureProvider<Set<DateTime>>(
  (ref) async => {
    for (final t in await ref.watch(transactionsProvider.future)) DateTime(t.date.year, t.date.month, t.date.day),
  },
);

final suggesterProvider = FutureProvider<CategorySuggester>(
  (ref) async => CategorySuggester(await ref.watch(transactionsProvider.future)),
);

final scheduledProvider = _data((r) => r.scheduled());
final potsProvider = _data((r) => r.pots());
final potBalancesProvider = _data((r) => r.potBalances());
final budgetsProvider = _data((r) => r.budgets());
final transactionPotsProvider = _data((r) => r.transactionPots());

final notificationsProvider = Provider<Notifications>((ref) => throw UnimplementedError('overridden in main'));

/// Day of the month when piggy banks linked to planned expenses get their share.
class SavingDay extends Notifier<int> {
  static const _key = 'saving_day';

  @override
  int build() => ref.read(prefsProvider).getInt(_key) ?? 1;

  void set(int day) {
    state = day;
    ref.read(prefsProvider).setInt(_key, day);
  }
}

final savingDayProvider = NotifierProvider<SavingDay, int>(SavingDay.new);

/// Money per account split into what sits in piggy banks and what is free.
class AccountSplit {
  AccountSplit(this.balance, this.inPots);
  final int balance;
  final int inPots;
  int get free => balance - inPots;
}

final accountSplitProvider = FutureProvider<Map<int, AccountSplit>>((ref) async {
  final balances = await ref.watch(balancesProvider.future);
  final pots = await ref.watch(potsProvider.future);
  final potBalances = await ref.watch(potBalancesProvider.future);
  final inPots = <int, int>{};
  for (final p in pots.where((p) => p.archivedAt == null)) {
    inPots.update(p.accountId, (v) => v + (potBalances[p.id] ?? 0), ifAbsent: () => potBalances[p.id] ?? 0);
  }
  return {for (final e in balances.entries) e.key: AccountSplit(e.value, inPots[e.key] ?? 0)};
});

/// Net worth split: (free, in piggy banks), over accounts that count towards net worth.
final freeAndSavedProvider = FutureProvider<(int, int)>((ref) async {
  final split = await ref.watch(accountSplitProvider.future);
  final accounts = await ref.watch(accountsProvider.future);
  var (free, saved) = (0, 0);
  for (final a in accounts.where((a) => a.deletedAt == null && a.countNetWorth)) {
    free += split[a.id]?.free ?? 0;
    saved += split[a.id]?.inPots ?? 0;
  }
  return (free, saved);
});

/// Spent this month per budget, subcategories included.
final budgetSpentProvider = FutureProvider<Map<int, int>>((ref) async {
  final budgets = await ref.watch(budgetsProvider.future);
  final lookup = await ref.watch(lookupProvider.future);
  final txns = await ref.watch(transactionsProvider.future);
  final now = DateTime.now();
  final spent = <int, int>{};
  for (final t in txns) {
    if (t.type != TxType.expense || t.date.year != now.year || t.date.month != now.month) continue;
    final root = lookup.root(t.categoryId)?.id;
    if (root != null) spent.update(root, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
  }
  return {for (final b in budgets) b.id!: spent[b.categoryId] ?? 0};
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// AI provider choice. The API key lives in the Keychain, not here.
class AiSettings {
  const AiSettings({required this.presetId, required this.baseUrl, required this.model});
  final String presetId;
  final String baseUrl;
  final String model;
  bool get isComplete => baseUrl.isNotEmpty && model.isNotEmpty;
}

class AiSettingsNotifier extends Notifier<AiSettings> {
  @override
  AiSettings build() {
    final p = ref.read(prefsProvider);
    return AiSettings(
      presetId: p.getString('ai_preset') ?? 'groq',
      baseUrl: p.getString('ai_base_url') ?? aiPresets.first.baseUrl,
      model: p.getString('ai_model') ?? '',
    );
  }

  void set(AiSettings s) {
    state = s;
    ref.read(prefsProvider)
      ..setString('ai_preset', s.presetId)
      ..setString('ai_base_url', s.baseUrl)
      ..setString('ai_model', s.model);
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);

const aiKeyName = 'ai_api_key';

final aiKeyProvider = FutureProvider<String?>((ref) => ref.watch(secureStorageProvider).read(key: aiKeyName));
