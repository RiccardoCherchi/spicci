import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/db.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/data/palette.dart';
import 'package:spicci/data/repo.dart';
import 'package:spicci/import/sossoldi_csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final csv = File('test/fixtures/sossoldi_sample.csv').readAsStringSync();

  test('parses rows by header name', () {
    final d = parseSossoldiCsv(csv);
    expect(d.accounts, hasLength(3));
    expect(d.categories, hasLength(4));
    expect(d.transactions, hasLength(4));
    expect(d.recurring, hasLength(1));
    expect(d.budgets, hasLength(1));
    expect(d.skipped, 1, reason: 'row with an invalid date');

    final fineco = d.accounts.first;
    expect(fineco['starting_cents'], 150050);
    expect(fineco['icon'], 'bank', reason: 'Material name mapped to Solar');
    expect(fineco['is_main'], 1, reason: 'first active account becomes main');
    expect(d.accounts[2]['deleted_at'], isNotNull);

    final byId = {for (final t in d.transactions) t['id']: t};
    expect(byId[10]!['date'], '2025-03-01T14:05:00.000');
    expect(byId[11]!['date'], '2024-02-23T00:00:00.000');
    expect(byId[11]!['note'], 'Stipendio, febbraio');
    expect(byId[12]!['date'], '2024-01-15T10:00:00.000');
    expect(byId[12]!['to_account_id'], 2);
    expect(byId[12]!['category_id'], isNull);
    expect(byId[13]!['note'], '007');
    expect(byId[13]!['amount_cents'], 999);

    expect(d.categories[1]['parent_id'], 4);
    expect(d.recurring.single['type'], 'OUT', reason: 'missing type defaults to OUT');
    expect(d.recurring.single['frequency'], 'MONTHLY');
  });

  test('handles columns in a different order and missing optional columns', () {
    const small =
        'name,table_name,id,symbol,color,startingValue,active,mainAccount\r\n'
        'Wallet,bankAccount,7,payments,1,10,1,1\r\n';
    final d = parseSossoldiCsv(small);
    expect(d.accounts.single['id'], 7);
    expect(d.accounts.single['name'], 'Wallet');
    expect(d.accounts.single['position'], 0);
    expect(d.accounts.single['count_net_worth'], 1);
  });

  test('fills in references to rows missing from the file', () {
    const csv =
        'table_name,id,name,type,symbol,color,parent,date,amount,idCategory,idBankAccount,idBankAccountTransfer\r\n'
        'categoryTransaction,1,Food,OUT,restaurant,1,99,,,,,\r\n'
        'transaction,10,,OUT,,,,2025-01-01,5,42,7,\r\n'
        'transaction,11,,TRSF,,,,2025-01-02,5,,7,8\r\n';
    final d = parseSossoldiCsv(csv);
    expect(d.categories.single['parent_id'], isNull, reason: 'parent 99 is missing');
    expect(d.transactions.first['category_id'], isNull, reason: 'category 42 is missing');
    expect(d.accounts.map((a) => a['id']), [7, 8], reason: 'placeholder accounts');
    expect(d.accounts.where((a) => a['is_main'] == 1).single['id'], 7);
  });

  test('rejects files without table_name', () {
    expect(() => parseSossoldiCsv('a,b\r\n1,2\r\n'), throwsA(isA<SossoldiFormatException>()));
  });

  test('out-of-range colour index does not throw', () {
    expect(categoryColor(99), categoryPalette[99 % categoryPalette.length]);
  });

  test('replaces database content and keeps references', () async {
    final db = await openAppDb(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    final repo = Repo(db);
    expect(await repo.categories(), isNotEmpty, reason: 'seeded');

    await replaceWithSossoldi(db, parseSossoldiCsv(csv));

    final accounts = await repo.accounts();
    expect(accounts.map((a) => a.id), [1, 2, 3]);
    expect(accounts.where((a) => a.isMain).single.name, 'Fineco');
    final cats = await repo.categories();
    expect(cats, hasLength(4));
    final txns = await repo.transactions();
    expect(txns.first.id, 10, reason: 'newest first');
    expect(txns.firstWhere((t) => t.id == 12).type, TxType.transfer);
    // Starting value, minus the expense, plus the salary, minus the transfer to Cash.
    final balances = await repo.balances();
    expect(balances[1], 150050 - 550 + 200000 - 10000);
    expect(balances[2], 5000 + 10000, reason: 'transfer received');
  });
}
