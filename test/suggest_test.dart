import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:spicci/logic/suggest.dart';

Txn _t(String note, int category) =>
    Txn(date: DateTime(2025), amountCents: 100, type: TxType.expense, accountId: 1, categoryId: category, note: note);

void main() {
  final s = CategorySuggester([
    _t('Esselunga spesa', 2),
    _t('Esselunga', 2),
    _t('Esselunga regalo Marco', 25),
    _t('Terea', 23),
    _t('Caffè bar Sport', 4),
    _t('Pizza con amici', 3),
  ]);

  test('identical note wins', () => expect(s.suggest('terea'), 23));
  test('most frequent category for a shared word', () => expect(s.suggest('Esselunga via Roma'), 2));
  test('half-typed word matches by prefix', () => expect(s.suggest('Essel'), 2));
  test('accents and case are handled', () => expect(s.suggest('CAFFÈ'), 4));
  test('no match gives null', () => expect(s.suggest('xyz'), isNull));
  test('short words are ignored', () => expect(s.suggest('a'), isNull));
  test('respects allowed categories', () => expect(s.suggest('Esselunga', allowed: (id) => id != 2), 25));
}
