import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'add_page_helpers.dart';

// Each add-page widget test lives in its own file: easy_localization does not
// reload its delegate for a second app in the same isolate.
void main() {
  sqfliteFfiInit();

  testWidgets('note suggests the category used before, and tags are saved', (tester) async {
    late int groceries;
    final repo = await openAddPage(
      tester,
      before: (repo) async {
        groceries = (await repo.categories()).firstWhere((c) => c.name == 'Groceries').id!;
        await repo.insertTxn(
          Txn(
            date: DateTime(2025),
            amountCents: 100,
            type: TxType.expense,
            accountId: 1,
            categoryId: groceries,
            note: 'Esselunga',
          ),
          tags: ['home'],
        );
      },
    );
    await typeAmount(tester, ['3']);
    await tester.enterText(find.byType(TextField), 'Esselunga Viale');
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('tags')));
    await settle(tester);
    await tester.tap(find.text('#home'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await settle(tester);
    await save(tester);

    final saved = (await repo.transactions()).first;
    expect(saved.note, 'Esselunga Viale');
    expect(saved.categoryId, groceries);
    expect((await repo.transactionTags())[saved.id], ['home']);
  });
}
