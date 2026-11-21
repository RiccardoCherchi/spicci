import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/logic/filter.dart';

void main() {
  final categories = {
    1: const Category(id: 1, name: 'Food', type: 'OUT'),
    2: const Category(id: 2, name: 'Groceries', type: 'OUT', parentId: 1),
    3: const Category(id: 3, name: 'Salary', type: 'IN'),
  };
  final accounts = {1: const Account(id: 1, name: 'Fineco'), 2: const Account(id: 2, name: 'Cash')};
  final txns = [
    Txn(
      id: 1,
      date: DateTime(2025, 3, 2, 18),
      amountCents: 100,
      type: TxType.expense,
      accountId: 1,
      categoryId: 2,
      note: 'Esselunga',
    ),
    Txn(id: 2, date: DateTime(2025, 3, 1), amountCents: 100, type: TxType.income, accountId: 1, categoryId: 3),
    Txn(id: 3, date: DateTime(2025, 2, 28), amountCents: 100, type: TxType.transfer, accountId: 1, toAccountId: 2),
  ];
  final tags = {
    1: ['holiday'],
  };
  List<int?> run(TxnFilter f) =>
      applyFilter(f, txns, categories: categories, accounts: accounts, tags: tags).map((t) => t.id).toList();

  test('empty filter keeps everything', () => expect(run(const TxnFilter()), [1, 2, 3]));
  test('parent category includes subcategories', () => expect(run(const TxnFilter(categoryId: 1)), [1]));
  test('account matches both sides of a transfer', () => expect(run(const TxnFilter(accountId: 2)), [3]));
  test('text searches note, category, account and tags', () {
    expect(run(const TxnFilter(query: 'essel')), [1]);
    expect(run(const TxnFilter(query: 'food')), [1]);
    expect(run(const TxnFilter(query: 'cash')), [3]);
    expect(run(const TxnFilter(query: 'HOLIDAY')), [1]);
  });
  test('day range is inclusive', () {
    expect(run(TxnFilter(from: DateTime(2025, 3, 1), to: DateTime(2025, 3, 2))), [1, 2]);
  });
  test('type and tag', () {
    expect(run(const TxnFilter(type: TxType.income)), [2]);
    expect(run(const TxnFilter(tag: 'holiday')), [1]);
  });
}
