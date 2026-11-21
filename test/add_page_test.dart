import 'package:flutter_test/flutter_test.dart';
import 'package:spicci/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'add_page_helpers.dart';

// Each add-page widget test lives in its own file: easy_localization does not
// reload its delegate for a second app in the same isolate.
void main() {
  sqfliteFfiInit();

  testWidgets('keypad amount, subcategory and default account are saved', (tester) async {
    final repo = await openAddPage(tester);
    await typeAmount(tester, ['1', '2', '.', '5']);
    await tester.tap(find.text('Food'));
    await settle(tester);
    await tester.tap(find.text('Groceries'));
    await tester.pump();
    await save(tester);

    final saved = (await repo.transactions()).single;
    final groceries = (await repo.categories()).firstWhere((c) => c.name == 'Groceries');
    expect(saved.amountCents, 1250);
    expect(saved.type, TxType.expense);
    expect(saved.categoryId, groceries.id);
    expect(saved.accountId, 1, reason: 'default account preselected');
    expect(find.text('open'), findsOneWidget, reason: 'page closed after save');
  });
}
