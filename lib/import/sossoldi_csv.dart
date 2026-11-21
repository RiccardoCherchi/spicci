import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import 'material_to_solar.dart';

/// Rows from a Sossoldi CSV export, already mapped to Spicci columns.
class SossoldiData {
  final accounts = <Map<String, Object?>>[];
  final categories = <Map<String, Object?>>[];
  final transactions = <Map<String, Object?>>[];
  final recurring = <Map<String, Object?>>[];
  final budgets = <Map<String, Object?>>[];
  int skipped = 0;

  Map<String, List<Map<String, Object?>>> get tables => {
    'accounts': accounts,
    'categories': categories,
    'transactions': transactions,
    'recurring': recurring,
    'budgets': budgets,
  };
}

class SossoldiFormatException implements Exception {
  SossoldiFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

SossoldiData parseSossoldiCsv(String input) {
  // dynamicTyping stays off so notes like "007" are not turned into numbers.
  final rows = Csv(dynamicTyping: false).decode(input);
  if (rows.isEmpty) throw SossoldiFormatException('The file is empty.');
  final header = rows.first.map((e) => e.toString().trim()).toList();
  if (!header.contains('table_name')) {
    throw SossoldiFormatException('Not a Sossoldi export: missing table_name column.');
  }

  final data = SossoldiData();
  for (final raw in rows.skip(1)) {
    if (raw.every((c) => c.toString().isEmpty)) continue;
    final r = _Row(header, raw);
    try {
      switch (r.str('table_name')) {
        case 'bankAccount':
          data.accounts.add({
            'id': r.integer('id'),
            'name': r.str('name') ?? 'Account',
            'icon': materialToSolar[r.str('symbol')] ?? 'banknote',
            'color': r.integer('color') ?? 0,
            'starting_cents': r.cents('startingValue') ?? 0,
            'is_main': r.boolean('mainAccount', false) ? 1 : 0,
            'active': r.boolean('active', true) ? 1 : 0,
            'count_net_worth': r.boolean('countNetWorth', true) ? 1 : 0,
            'position': r.integer('position') ?? 0,
            'deleted_at': r.date('deletedAt'),
          });
        case 'categoryTransaction':
          data.categories.add({
            'id': r.integer('id'),
            'name': r.str('name') ?? 'Category',
            'type': r.str('type') ?? 'OUT',
            'icon': materialToSolar[r.str('symbol')] ?? 'tag',
            'color': r.integer('color') ?? 0,
            'note': r.str('note'),
            'parent_id': r.integer('parent'),
            'position': r.integer('position') ?? 0,
            'deleted_at': r.date('deletedAt'),
          });
        case 'transaction':
          final type = r.str('type') ?? 'OUT';
          data.transactions.add({
            'id': r.integer('id'),
            'date': r.date('date')!,
            'amount_cents': r.cents('amount')!.abs(),
            'type': type,
            'note': r.str('note'),
            'category_id': type == 'TRSF' ? null : r.integer('idCategory'),
            'account_id': r.integer('idBankAccount')!,
            'to_account_id': type == 'TRSF' ? r.integer('idBankAccountTransfer') : null,
            'recurring_id': r.integer('idRecurringTransaction'),
          });
        case 'recurringTransaction':
          data.recurring.add({
            'id': r.integer('id'),
            'from_date': r.date('fromDate')!,
            'to_date': r.date('toDate'),
            'amount_cents': r.cents('amount')!.abs(),
            'note': r.str('note'),
            'frequency': r.str('recurrency') ?? 'MONTHLY',
            'category_id': r.integer('idCategory'),
            'account_id': r.integer('idBankAccount')!,
            'type': r.str('type') ?? 'OUT',
            'last_date': r.date('lastInsertion'),
          });
        case 'budget':
          data.budgets.add({
            'category_id': r.integer('idCategory')!,
            'amount_cents': r.cents('amountLimit')!.abs(),
            'active': r.boolean('active', true) ? 1 : 0,
          });
      }
    } on Object {
      // A malformed row must not abort the whole import.
      data.skipped++;
    }
  }

  _fixReferences(data);
  _fixMainAccount(data.accounts);
  return data;
}

/// Sossoldi can leave references to rows that are no longer in the file.
/// Missing accounts get a placeholder so no money disappears; missing
/// categories and parents are dropped, so those rows read as uncategorised.
void _fixReferences(SossoldiData data) {
  final accounts = {for (final a in data.accounts) a['id']};
  final categories = {for (final c in data.categories) c['id']};
  void needAccount(Object? id) {
    if (id == null || accounts.contains(id)) return;
    accounts.add(id);
    data.accounts.add({
      'id': id,
      'name': 'Sossoldi #$id',
      'icon': 'wallet',
      'color': 0,
      'starting_cents': 0,
      'is_main': 0,
      'active': 1,
      'count_net_worth': 1,
      'position': data.accounts.length,
      'deleted_at': null,
    });
  }

  for (final c in data.categories) {
    if (!categories.contains(c['parent_id'])) c['parent_id'] = null;
  }
  for (final t in [...data.transactions, ...data.recurring]) {
    needAccount(t['account_id']);
    needAccount(t['to_account_id']);
    if (!categories.contains(t['category_id'])) t['category_id'] = null;
  }
  data.budgets.removeWhere((b) => !categories.contains(b['category_id']));
}

void _fixMainAccount(List<Map<String, Object?>> accounts) {
  final live = accounts.where((a) => a['deleted_at'] == null).toList();
  var main = live.where((a) => a['is_main'] == 1).firstOrNull;
  main ??= live.where((a) => a['active'] == 1).firstOrNull ?? live.firstOrNull;
  for (final a in accounts) {
    a['is_main'] = identical(a, main) ? 1 : 0;
  }
}

/// Replaces all local data with [data] in one transaction.
Future<void> replaceWithSossoldi(Database db, SossoldiData data) async {
  if (data.accounts.isEmpty) {
    throw SossoldiFormatException('The file has no accounts.');
  }
  await db.transaction((txn) async {
    for (final t in dataTables) {
      await txn.delete(t);
    }
    final batch = txn.batch();
    data.tables.forEach((table, rows) {
      for (final row in rows) {
        batch.insert(table, row);
      }
    });
    await batch.commit(noResult: true);
  });
}

class _Row {
  _Row(this.header, this.cells);
  final List<String> header;
  final List<dynamic> cells;

  String? str(String col) {
    final i = header.indexOf(col);
    if (i < 0 || i >= cells.length) return null;
    final v = cells[i].toString();
    return v.isEmpty ? null : v;
  }

  int? integer(String col) {
    final v = str(col);
    return v == null ? null : num.parse(v).toInt();
  }

  int? cents(String col) {
    final v = str(col);
    return v == null ? null : (double.parse(v) * 100).round();
  }

  bool boolean(String col, bool fallback) {
    final v = str(col);
    return v == null ? fallback : v == '1' || v.toLowerCase() == 'true';
  }

  /// Normalises the three Sossoldi date shapes to a local ISO string.
  String? date(String col) {
    final v = str(col);
    if (v == null) return null;
    final d = DateTime.parse(v);
    return (d.isUtc ? d.toLocal() : d).toIso8601String();
  }
}
