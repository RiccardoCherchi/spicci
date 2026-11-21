enum TxType {
  expense('OUT'),
  income('IN'),
  transfer('TRSF');

  const TxType(this.code);
  final String code;

  static TxType fromCode(String code) => values.firstWhere((t) => t.code == code, orElse: () => expense);
}

class Account {
  const Account({
    this.id,
    required this.name,
    this.icon = 'banknote',
    this.color = 0,
    this.startingCents = 0,
    this.isMain = false,
    this.active = true,
    this.countNetWorth = true,
    this.position = 0,
    this.deletedAt,
  });

  final int? id;
  final String name;
  final String icon;
  final int color;
  final int startingCents;
  final bool isMain;
  final bool active;
  final bool countNetWorth;
  final int position;
  final String? deletedAt;

  factory Account.fromRow(Map<String, Object?> r) => Account(
    id: r['id'] as int,
    name: r['name'] as String,
    icon: r['icon'] as String,
    color: r['color'] as int,
    startingCents: r['starting_cents'] as int,
    isMain: r['is_main'] == 1,
    active: r['active'] == 1,
    countNetWorth: r['count_net_worth'] == 1,
    position: r['position'] as int,
    deletedAt: r['deleted_at'] as String?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'starting_cents': startingCents,
    'is_main': isMain ? 1 : 0,
    'active': active ? 1 : 0,
    'count_net_worth': countNetWorth ? 1 : 0,
    'position': position,
    'deleted_at': deletedAt,
  };
}

class Category {
  const Category({
    this.id,
    required this.name,
    required this.type,
    this.icon = 'tag',
    this.color = 0,
    this.note,
    this.parentId,
    this.position = 0,
    this.deletedAt,
  });

  final int? id;
  final String name;

  /// `IN`, `OUT` or `BOTH`.
  final String type;
  final String icon;
  final int color;
  final String? note;
  final int? parentId;
  final int position;
  final String? deletedAt;

  bool matches(TxType t) => type == 'BOTH' || type == t.code;

  factory Category.fromRow(Map<String, Object?> r) => Category(
    id: r['id'] as int,
    name: r['name'] as String,
    type: r['type'] as String,
    icon: r['icon'] as String,
    color: r['color'] as int,
    note: r['note'] as String?,
    parentId: r['parent_id'] as int?,
    position: r['position'] as int,
    deletedAt: r['deleted_at'] as String?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'type': type,
    'icon': icon,
    'color': color,
    'note': note,
    'parent_id': parentId,
    'position': position,
    'deleted_at': deletedAt,
  };
}

class Txn {
  const Txn({
    this.id,
    required this.date,
    required this.amountCents,
    required this.type,
    this.note,
    this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.recurringId,
  });

  final int? id;
  final DateTime date;
  final int amountCents;
  final TxType type;
  final String? note;
  final int? categoryId;
  final int accountId;
  final int? toAccountId;
  final int? recurringId;

  Txn copyWithId(int id) => Txn(
    id: id,
    date: date,
    amountCents: amountCents,
    type: type,
    note: note,
    categoryId: categoryId,
    accountId: accountId,
    toAccountId: toAccountId,
    recurringId: recurringId,
  );

  /// Effect on total wealth: transfers are neutral.
  int get signedCents => switch (type) {
    TxType.expense => -amountCents,
    TxType.income => amountCents,
    TxType.transfer => 0,
  };

  factory Txn.fromRow(Map<String, Object?> r) => Txn(
    id: r['id'] as int,
    date: DateTime.parse(r['date'] as String),
    amountCents: r['amount_cents'] as int,
    type: TxType.fromCode(r['type'] as String),
    note: r['note'] as String?,
    categoryId: r['category_id'] as int?,
    accountId: r['account_id'] as int,
    toAccountId: r['to_account_id'] as int?,
    recurringId: r['recurring_id'] as int?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'date': date.toIso8601String(),
    'amount_cents': amountCents,
    'type': type.code,
    'note': note,
    'category_id': categoryId,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'recurring_id': recurringId,
  };
}

class Preset {
  const Preset({
    this.id,
    required this.label,
    required this.amountCents,
    this.type = TxType.expense,
    this.categoryId,
    required this.accountId,
    this.note,
    this.position = 0,
  });

  final int? id;
  final String label;
  final int amountCents;
  final TxType type;
  final int? categoryId;
  final int accountId;
  final String? note;
  final int position;

  factory Preset.fromRow(Map<String, Object?> r) => Preset(
    id: r['id'] as int,
    label: r['label'] as String,
    amountCents: r['amount_cents'] as int,
    type: TxType.fromCode(r['type'] as String),
    categoryId: r['category_id'] as int?,
    accountId: r['account_id'] as int,
    note: r['note'] as String?,
    position: r['position'] as int,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'label': label,
    'amount_cents': amountCents,
    'type': type.code,
    'category_id': categoryId,
    'account_id': accountId,
    'note': note,
    'position': position,
  };

  Txn toTxn(DateTime date) => Txn(
    date: date,
    amountCents: amountCents,
    type: type,
    note: note ?? label,
    categoryId: categoryId,
    accountId: accountId,
  );
}

/// How often a scheduled item repeats. Codes match Sossoldi's `recurrency`.
enum Freq {
  daily('DAILY', days: 1),
  weekly('WEEKLY', days: 7),
  monthly('MONTHLY', months: 1),
  bimonthly('BIMONTHLY', months: 2),
  quarterly('QUARTERLY', months: 3),
  semester('SEMESTER', months: 6),
  annual('ANNUAL', months: 12),
  once('ONCE');

  const Freq(this.code, {this.days = 0, this.months = 0});
  final String code;
  final int days;
  final int months;

  /// How many times it happens in a year; 0 for one-off items.
  double get perYear => days > 0 ? 365 / days : (months > 0 ? 12 / months : 0);

  static Freq fromCode(String code) => values.firstWhere((f) => f.code == code, orElse: () => monthly);
}

/// A subscription (SUB) or a planned big expense (PLAN). Nothing is recorded
/// until the user confirms the payment.
class Scheduled {
  const Scheduled({
    this.id,
    required this.kind,
    required this.name,
    required this.amountCents,
    this.type = TxType.expense,
    required this.freq,
    required this.fromDate,
    this.toDate,
    this.categoryId,
    required this.accountId,
    required this.nextDue,
    this.remindDays = 3,
    this.snoozeUntil,
    this.archivedAt,
    this.lastDate,
  });

  final int? id;

  /// 'SUB' or 'PLAN'.
  final String kind;
  final String name;
  final int amountCents;
  final TxType type;
  final Freq freq;

  /// First occurrence; its day of month anchors later ones.
  final DateTime fromDate;
  final DateTime? toDate;
  final int? categoryId;
  final int accountId;
  final DateTime nextDue;
  final int remindDays;
  final DateTime? snoozeUntil;
  final String? archivedAt;
  final DateTime? lastDate;

  bool get isPlanned => kind == 'PLAN';

  factory Scheduled.fromRow(Map<String, Object?> r, DateTime Function(DateTime from, Freq f, DateTime? last) next) {
    final from = DateTime.parse(r['from_date'] as String);
    final freq = Freq.fromCode(r['frequency'] as String);
    final last = r['last_date'] == null ? null : DateTime.parse(r['last_date'] as String);
    return Scheduled(
      id: r['id'] as int,
      kind: r['kind'] as String,
      name: (r['note'] as String?) ?? '',
      amountCents: r['amount_cents'] as int,
      type: TxType.fromCode(r['type'] as String),
      freq: freq,
      fromDate: from,
      toDate: r['to_date'] == null ? null : DateTime.parse(r['to_date'] as String),
      categoryId: r['category_id'] as int?,
      accountId: r['account_id'] as int,
      // Rows imported from Sossoldi have no next_due yet.
      nextDue: r['next_due'] == null ? next(from, freq, last) : DateTime.parse(r['next_due'] as String),
      remindDays: r['remind_days'] as int,
      snoozeUntil: r['snooze_until'] == null ? null : DateTime.parse(r['snooze_until'] as String),
      archivedAt: r['archived_at'] as String?,
      lastDate: last,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'kind': kind,
    'note': name,
    'amount_cents': amountCents,
    'type': type.code,
    'frequency': freq.code,
    'from_date': fromDate.toIso8601String(),
    'to_date': toDate?.toIso8601String(),
    'category_id': categoryId,
    'account_id': accountId,
    'next_due': nextDue.toIso8601String(),
    'remind_days': remindDays,
    'snooze_until': snoozeUntil?.toIso8601String(),
    'archived_at': archivedAt,
    'last_date': lastDate?.toIso8601String(),
  };
}

/// Money set aside inside an account. It never changes the account balance,
/// so the app keeps matching the bank.
class Pot {
  const Pot({
    this.id,
    required this.accountId,
    required this.name,
    this.icon = 'piggy-bank',
    this.color = 0,
    this.targetCents,
    this.targetDate,
    this.recurringId,
    this.autoMonth,
    this.position = 0,
    this.archivedAt,
  });

  final int? id;
  final int accountId;
  final String name;
  final String icon;
  final int color;
  final int? targetCents;
  final DateTime? targetDate;

  /// The planned expense this pot saves for; it then fills automatically.
  final int? recurringId;

  /// Month ("2026-11") of the last automatic deposit.
  final String? autoMonth;
  final int position;
  final String? archivedAt;

  factory Pot.fromRow(Map<String, Object?> r) => Pot(
    id: r['id'] as int,
    accountId: r['account_id'] as int,
    name: r['name'] as String,
    icon: r['icon'] as String,
    color: r['color'] as int,
    targetCents: r['target_cents'] as int?,
    targetDate: r['target_date'] == null ? null : DateTime.parse(r['target_date'] as String),
    recurringId: r['recurring_id'] as int?,
    autoMonth: r['auto_month'] as String?,
    position: r['position'] as int,
    archivedAt: r['archived_at'] as String?,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'account_id': accountId,
    'name': name,
    'icon': icon,
    'color': color,
    'target_cents': targetCents,
    'target_date': targetDate?.toIso8601String(),
    'recurring_id': recurringId,
    'auto_month': autoMonth,
    'position': position,
    'archived_at': archivedAt,
  };
}

class PotMove {
  const PotMove({
    this.id,
    required this.potId,
    required this.date,
    required this.amountCents,
    this.note,
    this.transactionId,
    this.auto = false,
  });

  final int? id;
  final int potId;
  final DateTime date;

  /// Positive puts money in, negative takes it out.
  final int amountCents;
  final String? note;

  /// Set when the money left the pot through a real expense.
  final int? transactionId;
  final bool auto;

  factory PotMove.fromRow(Map<String, Object?> r) => PotMove(
    id: r['id'] as int,
    potId: r['pot_id'] as int,
    date: DateTime.parse(r['date'] as String),
    amountCents: r['amount_cents'] as int,
    note: r['note'] as String?,
    transactionId: r['transaction_id'] as int?,
    auto: r['auto'] == 1,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'pot_id': potId,
    'date': date.toIso8601String(),
    'amount_cents': amountCents,
    'note': note,
    'transaction_id': transactionId,
    'auto': auto ? 1 : 0,
  };
}

/// Monthly spending limit for a category and its subcategories.
class Budget {
  const Budget({this.id, required this.categoryId, required this.amountCents, this.active = true});
  final int? id;
  final int categoryId;
  final int amountCents;
  final bool active;

  factory Budget.fromRow(Map<String, Object?> r) => Budget(
    id: r['id'] as int,
    categoryId: r['category_id'] as int,
    amountCents: r['amount_cents'] as int,
    active: r['active'] == 1,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'category_id': categoryId,
    'amount_cents': amountCents,
    'active': active ? 1 : 0,
  };
}
