import 'package:sqflite/sqflite.dart';

import '../logic/schedule.dart';
import 'models.dart';

class Repo {
  Repo(this.db);
  final Database db;

  /// Includes soft-deleted accounts so old transactions can still show their name.
  Future<List<Account>> accounts() async =>
      (await db.query('accounts', orderBy: 'position, id')).map(Account.fromRow).toList();

  Future<List<Category>> categories() async =>
      (await db.query('categories', orderBy: 'position, id')).map(Category.fromRow).toList();

  Future<List<Txn>> transactions() async =>
      (await db.query('transactions', orderBy: 'date DESC, id DESC')).map(Txn.fromRow).toList();

  Future<List<Preset>> presets() async =>
      (await db.query('presets', orderBy: 'position, id')).map(Preset.fromRow).toList();

  /// Current balance of every account, deleted ones included.
  Future<Map<int, int>> balances() async {
    final rows = await db.rawQuery('''
      SELECT a.id, a.starting_cents
        + COALESCE((SELECT SUM(CASE type WHEN 'IN' THEN amount_cents ELSE -amount_cents END)
            FROM transactions WHERE account_id = a.id), 0)
        + COALESCE((SELECT SUM(amount_cents)
            FROM transactions WHERE type = 'TRSF' AND to_account_id = a.id), 0) AS balance
      FROM accounts a
    ''');
    return {for (final r in rows) r['id'] as int: r['balance'] as int};
  }

  /// [potId] pays the expense with money set aside in that piggy bank.
  Future<int> insertTxn(Txn t, {List<String> tags = const [], int? potId}) => db.transaction((txn) async {
    final id = await txn.insert('transactions', t.toRow()..remove('id'));
    await _setTags(txn, id, tags);
    await _setPot(txn, t.copyWithId(id), potId);
    return id;
  });

  Future<void> updateTxn(Txn t, {List<String> tags = const [], int? potId}) => db.transaction((txn) async {
    await txn.update('transactions', t.toRow(), where: 'id = ?', whereArgs: [t.id]);
    await _setTags(txn, t.id!, tags);
    await _setPot(txn, t, potId);
  });

  Future<void> _setPot(DatabaseExecutor txn, Txn t, int? potId) async {
    await txn.delete('pot_moves', where: 'transaction_id = ?', whereArgs: [t.id]);
    if (potId == null || t.type != TxType.expense) return;
    await txn.insert(
      'pot_moves',
      PotMove(potId: potId, date: t.date, amountCents: -t.amountCents, note: t.note, transactionId: t.id).toRow()
        ..remove('id'),
    );
  }

  /// Piggy bank each transaction was paid from.
  Future<Map<int, int>> transactionPots() async => {
    for (final r in await db.query('pot_moves', where: 'transaction_id IS NOT NULL'))
      r['transaction_id'] as int: r['pot_id'] as int,
  };

  Future<void> deleteTxn(int id) => db.transaction((txn) async {
    await txn.delete('pot_moves', where: 'transaction_id = ?', whereArgs: [id]);
    await txn.delete('transaction_tags', where: 'transaction_id = ?', whereArgs: [id]);
    await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
  });

  /// Tag names per transaction id.
  Future<Map<int, List<String>>> transactionTags() async {
    final rows = await db.rawQuery(
      'SELECT tt.transaction_id AS id, t.name FROM transaction_tags tt JOIN tags t ON t.id = tt.tag_id ORDER BY t.name',
    );
    final out = <int, List<String>>{};
    for (final r in rows) {
      out.putIfAbsent(r['id'] as int, () => []).add(r['name'] as String);
    }
    return out;
  }

  /// Tags ordered by how often they are used.
  Future<List<String>> tags() async => (await db.rawQuery('''
    SELECT t.name FROM tags t LEFT JOIN transaction_tags tt ON tt.tag_id = t.id
    GROUP BY t.id ORDER BY COUNT(tt.tag_id) DESC, t.name
  ''')).map((r) => r['name'] as String).toList();

  Future<void> _setTags(DatabaseExecutor txn, int transactionId, List<String> names) async {
    await txn.delete('transaction_tags', where: 'transaction_id = ?', whereArgs: [transactionId]);
    for (final name in names.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet()) {
      await txn.insert('tags', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
      final id = (await txn.query('tags', columns: ['id'], where: 'name = ?', whereArgs: [name])).first['id'];
      await txn.insert('transaction_tags', {'transaction_id': transactionId, 'tag_id': id});
    }
  }

  Future<int> saveAccount(Account a) async {
    if (a.id == null) {
      final position = await _nextPosition('accounts');
      return db.insert(
        'accounts',
        a.toRow()
          ..remove('id')
          ..['position'] = position,
      );
    }
    await db.update('accounts', a.toRow(), where: 'id = ?', whereArgs: [a.id]);
    return a.id!;
  }

  /// Soft delete, because transactions keep referencing the account. If it was
  /// the default, the first remaining account takes over.
  Future<void> deleteAccount(int id) => db.transaction((txn) async {
    await txn.update(
      'accounts',
      {'deleted_at': DateTime.now().toIso8601String(), 'is_main': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    final live = await txn.query('accounts', where: 'deleted_at IS NULL', orderBy: 'position, id');
    if (live.isNotEmpty && !live.any((a) => a['is_main'] == 1)) {
      await txn.update('accounts', {'is_main': 1}, where: 'id = ?', whereArgs: [live.first['id']]);
    }
  });

  Future<void> setMainAccount(int id) => db.transaction((txn) async {
    await txn.update('accounts', {'is_main': 0});
    await txn.update('accounts', {'is_main': 1}, where: 'id = ?', whereArgs: [id]);
  });

  Future<int> saveCategory(Category c) async {
    if (c.id == null) {
      final position = await _nextPosition('categories');
      return db.insert(
        'categories',
        c.toRow()
          ..remove('id')
          ..['position'] = position,
      );
    }
    await db.update('categories', c.toRow(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  /// Soft deletes the category and its subcategories.
  Future<void> deleteCategory(int id) => db.update(
    'categories',
    {'deleted_at': DateTime.now().toIso8601String()},
    where: 'id = ? OR parent_id = ?',
    whereArgs: [id, id],
  );

  Future<int> savePreset(Preset p) async {
    if (p.id == null) {
      final position = await _nextPosition('presets');
      return db.insert(
        'presets',
        p.toRow()
          ..remove('id')
          ..['position'] = position,
      );
    }
    await db.update('presets', p.toRow(), where: 'id = ?', whereArgs: [p.id]);
    return p.id!;
  }

  Future<void> deletePreset(int id) => db.delete('presets', where: 'id = ?', whereArgs: [id]);

  /// Stores [ids] in the given order. Only the listed rows move, so hidden or
  /// deleted rows never shift the visible order.
  Future<void> reorder(String table, List<int> ids) async {
    final batch = db.batch();
    for (final (i, id) in ids.indexed) {
      batch.update(table, {'position': i}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // Scheduled items: subscriptions and planned expenses.

  Future<List<Scheduled>> scheduled() async =>
      (await db.query('recurring', orderBy: 'id')).map((r) => Scheduled.fromRow(r, nextOccurrence)).toList();

  Future<int> saveScheduled(Scheduled s) async {
    if (s.id == null) return db.insert('recurring', s.toRow()..remove('id'));
    await db.update('recurring', s.toRow(), where: 'id = ?', whereArgs: [s.id]);
    return s.id!;
  }

  Future<void> archiveScheduled(int id) =>
      db.update('recurring', {'archived_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  /// Records the payment, takes what it can from the linked piggy bank and moves
  /// on to the next due date. Returns the new transaction id.
  Future<int> payScheduled(Scheduled s, {required int amountCents, required DateTime date, required int accountId}) =>
      db.transaction((txn) async {
        final id = await txn.insert(
          'transactions',
          Txn(
            date: date,
            amountCents: amountCents,
            type: s.type,
            note: s.name,
            categoryId: s.categoryId,
            accountId: accountId,
            recurringId: s.id,
          ).toRow()..remove('id'),
        );
        final pot = (await txn.query(
          'pots',
          where: 'recurring_id = ? AND archived_at IS NULL',
          whereArgs: [s.id],
        )).map(Pot.fromRow).firstOrNull;
        if (pot != null && s.type == TxType.expense) {
          final balance = await _potBalance(txn, pot.id!);
          final take = balance < amountCents ? balance : amountCents;
          if (take > 0) {
            await txn.insert(
              'pot_moves',
              PotMove(potId: pot.id!, date: date, amountCents: -take, note: s.name, transactionId: id).toRow()
                ..remove('id'),
            );
          }
        }
        await _moveOn(txn, s, paidOn: date);
        return id;
      });

  /// Moves to the next due date without recording anything.
  Future<void> skipScheduled(Scheduled s) => db.transaction((txn) => _moveOn(txn, s));

  Future<void> snoozeScheduled(int id, DateTime until) =>
      db.update('recurring', {'snooze_until': until.toIso8601String()}, where: 'id = ?', whereArgs: [id]);

  Future<void> _moveOn(DatabaseExecutor txn, Scheduled s, {DateTime? paidOn}) async {
    final next = following(s);
    await txn.update(
      'recurring',
      {
        'next_due': (next ?? s.nextDue).toIso8601String(),
        'snooze_until': null,
        if (paidOn != null) 'last_date': paidOn.toIso8601String(),
        if (next == null) 'archived_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  // Piggy banks.

  Future<List<Pot>> pots() async => (await db.query('pots', orderBy: 'position, id')).map(Pot.fromRow).toList();

  Future<Map<int, int>> potBalances() async => {
    for (final r in await db.rawQuery('SELECT pot_id, SUM(amount_cents) AS total FROM pot_moves GROUP BY pot_id'))
      r['pot_id'] as int: r['total'] as int,
  };

  Future<int> _potBalance(DatabaseExecutor txn, int potId) async =>
      ((await txn.rawQuery('SELECT COALESCE(SUM(amount_cents), 0) AS t FROM pot_moves WHERE pot_id = ?', [
            potId,
          ])).first['t']
          as int);

  Future<List<PotMove>> potMoves(int potId) async => (await db.query(
    'pot_moves',
    where: 'pot_id = ?',
    whereArgs: [potId],
    orderBy: 'date DESC, id DESC',
  )).map(PotMove.fromRow).toList();

  Future<int> savePot(Pot pot) async {
    if (pot.id == null) {
      final position = await _nextPosition('pots');
      return db.insert(
        'pots',
        pot.toRow()
          ..remove('id')
          ..['position'] = position,
      );
    }
    await db.update('pots', pot.toRow(), where: 'id = ?', whereArgs: [pot.id]);
    return pot.id!;
  }

  Future<void> addPotMove(PotMove move) => db.insert('pot_moves', move.toRow()..remove('id'));

  Future<void> deletePotMove(int id) => db.delete('pot_moves', where: 'id = ?', whereArgs: [id]);

  /// Closes a piggy bank; whatever is left goes back to the account's free money.
  Future<void> closePot(int id) => db.transaction((txn) async {
    final balance = await _potBalance(txn, id);
    if (balance != 0) {
      await txn.insert(
        'pot_moves',
        PotMove(potId: id, date: DateTime.now(), amountCents: -balance).toRow()..remove('id'),
      );
    }
    await txn.update('pots', {'archived_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  });

  /// Puts this month's share into every piggy bank linked to a planned expense,
  /// once the saving day has passed. Returns the deposits made.
  Future<List<(Pot, int)>> runAutoSaving(DateTime now, int savingDay) async {
    final month = monthKey(now);
    if (now.isBefore(savingDate(now.year, now.month, savingDay))) return const [];
    final schedules = {for (final s in await scheduled()) s.id: s};
    final balances = await potBalances();
    final made = <(Pot, int)>[];
    for (final pot in await pots()) {
      final s = schedules[pot.recurringId];
      if (pot.archivedAt != null || s == null || s.archivedAt != null || pot.autoMonth == month) continue;
      final quota = monthlyQuota(
        targetCents: s.amountCents,
        savedCents: balances[pot.id] ?? 0,
        now: now,
        due: s.nextDue,
        savingDay: savingDay,
        doneThisMonth: false,
      );
      await db.transaction((txn) async {
        if (quota > 0) {
          await txn.insert(
            'pot_moves',
            PotMove(potId: pot.id!, date: now, amountCents: quota, auto: true).toRow()..remove('id'),
          );
        }
        await txn.update('pots', {'auto_month': month}, where: 'id = ?', whereArgs: [pot.id]);
      });
      if (quota > 0) made.add((pot, quota));
    }
    return made;
  }

  // Budgets.

  Future<List<Budget>> budgets() async =>
      (await db.query('budgets', where: 'active = 1', orderBy: 'id')).map(Budget.fromRow).toList();

  Future<void> saveBudget(Budget b) async {
    if (b.id == null) {
      await db.insert('budgets', b.toRow()..remove('id'));
    } else {
      await db.update('budgets', b.toRow(), where: 'id = ?', whereArgs: [b.id]);
    }
  }

  Future<void> deleteBudget(int id) => db.delete('budgets', where: 'id = ?', whereArgs: [id]);

  Future<int> _nextPosition(String table) async =>
      ((await db.rawQuery('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM $table')).first['p'] as int);
}
