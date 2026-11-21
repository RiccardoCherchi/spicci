import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const _schema = [
  '''CREATE TABLE accounts(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    icon TEXT NOT NULL,
    color INTEGER NOT NULL,
    starting_cents INTEGER NOT NULL DEFAULT 0,
    is_main INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    count_net_worth INTEGER NOT NULL DEFAULT 1,
    position INTEGER NOT NULL DEFAULT 0,
    deleted_at TEXT)''',
  '''CREATE TABLE categories(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    icon TEXT NOT NULL,
    color INTEGER NOT NULL,
    note TEXT,
    parent_id INTEGER,
    position INTEGER NOT NULL DEFAULT 0,
    deleted_at TEXT)''',
  '''CREATE TABLE transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    type TEXT NOT NULL,
    note TEXT,
    category_id INTEGER,
    account_id INTEGER NOT NULL,
    to_account_id INTEGER,
    recurring_id INTEGER)''',
  'CREATE INDEX transactions_date ON transactions(date)',
  '''CREATE TABLE recurring(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_date TEXT NOT NULL,
    to_date TEXT,
    amount_cents INTEGER NOT NULL,
    note TEXT,
    frequency TEXT NOT NULL,
    category_id INTEGER,
    account_id INTEGER NOT NULL,
    type TEXT NOT NULL DEFAULT 'OUT',
    last_date TEXT)''',
  '''CREATE TABLE budgets(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NOT NULL,
    amount_cents INTEGER NOT NULL,
    active INTEGER NOT NULL DEFAULT 1)''',
  'CREATE TABLE tags(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)',
  '''CREATE TABLE transaction_tags(
    transaction_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (transaction_id, tag_id))''',
  '''CREATE TABLE presets(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    label TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    type TEXT NOT NULL,
    category_id INTEGER,
    account_id INTEGER NOT NULL,
    note TEXT,
    position INTEGER NOT NULL DEFAULT 0)''',
];

/// Tables in the order a full replace must clear them.
/// Schema changes after version 1; index 0 upgrades 1 to 2, and so on.
const _migrations = [
  [
    // "recurring" holds every scheduled item: subscriptions (SUB) and planned big expenses (PLAN).
    "ALTER TABLE recurring ADD COLUMN kind TEXT NOT NULL DEFAULT 'SUB'",
    'ALTER TABLE recurring ADD COLUMN next_due TEXT',
    'ALTER TABLE recurring ADD COLUMN remind_days INTEGER NOT NULL DEFAULT 3',
    'ALTER TABLE recurring ADD COLUMN snooze_until TEXT',
    'ALTER TABLE recurring ADD COLUMN archived_at TEXT',
    '''CREATE TABLE pots(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      icon TEXT NOT NULL,
      color INTEGER NOT NULL,
      target_cents INTEGER,
      target_date TEXT,
      recurring_id INTEGER,
      auto_month TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      archived_at TEXT)''',
    '''CREATE TABLE pot_moves(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pot_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      note TEXT,
      transaction_id INTEGER,
      auto INTEGER NOT NULL DEFAULT 0)''',
  ],
];

const dataTables = [
  'pot_moves',
  'pots',
  'transaction_tags',
  'tags',
  'presets',
  'budgets',
  'recurring',
  'transactions',
  'categories',
  'accounts',
];

// ((English, Italian), icon, colour index, subcategories)
const _expenseSeed = [
  (
    ('Food', 'Cibo'),
    'chef-hat',
    1,
    [
      (('Groceries', 'Spesa'), 'cart-large-2'),
      (('Restaurants', 'Ristoranti'), 'pizza'),
      (('Bars & coffee', 'Bar e caffè'), 'cup-hot'),
    ],
  ),
  (
    ('Transport', 'Trasporti'),
    'car',
    5,
    [
      (('Fuel', 'Carburante'), 'gas-station'),
      (('Public transport', 'Mezzi pubblici'), 'tram'),
      (('Parking & tolls', 'Parcheggi e pedaggi'), 'parking'),
    ],
  ),
  (
    ('Home', 'Casa'),
    'home-2',
    7,
    [
      (('Rent', 'Affitto'), 'key'),
      (('Utilities', 'Bollette'), 'lightbulb'),
      (('Maintenance', 'Manutenzione'), 'wrench'),
    ],
  ),
  (
    ('Shopping', 'Shopping'),
    'bag-4',
    3,
    [(('Clothes', 'Abbigliamento'), 't-shirt'), (('Electronics', 'Elettronica'), 'laptop')],
  ),
  (('Health', 'Salute'), 'pill', 2, [(('Pharmacy', 'Farmacia'), 'pills'), (('Doctor', 'Medico'), 'stethoscope')]),
  (
    ('Leisure', 'Svago'),
    'confetti',
    4,
    [
      (('Subscriptions', 'Abbonamenti'), 'tv'),
      (('Going out', 'Uscite'), 'wineglass'),
      (('Sport', 'Sport'), 'dumbbell-large'),
    ],
  ),
  (('Tobacco', 'Tabacchi'), 'cigarette', 12, <((String, String), String)>[]),
  (('Travel', 'Viaggi'), 'plane', 6, <((String, String), String)>[]),
  (('Gifts', 'Regali'), 'gift', 41, <((String, String), String)>[]),
  (('Other', 'Altro'), 'tag', 19, <((String, String), String)>[]),
];

const _incomeSeed = [
  (('Salary', 'Stipendio'), 'case', 8),
  (('Side income', 'Extra'), 'hand-money', 21),
  (('Refunds', 'Rimborsi'), 'refresh-circle', 29),
  (('Other income', 'Altre entrate'), 'piggy-bank', 17),
];

/// [italian] picks the language of the seeded names; they are plain data afterwards.
Future<Database> openAppDb({DatabaseFactory? factory, String? path, bool italian = false}) async {
  final f = factory ?? databaseFactory;
  // Application Support is backed up by iOS but, unlike Documents, never shown in the Files app.
  final dbPath = path ?? p.join((await getApplicationSupportDirectory()).path, 'spicci.db');
  return f.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1 + _migrations.length,
      onCreate: (db, _) async {
        final batch = db.batch();
        for (final sql in [..._schema, ..._migrations.expand((m) => m)]) {
          batch.execute(sql);
        }
        await batch.commit(noResult: true);
        await seed(db, italian: italian);
      },
      onUpgrade: (db, from, to) async {
        for (final m in _migrations.sublist(from - 1, to - 1)) {
          for (final sql in m) {
            await db.execute(sql);
          }
        }
      },
    ),
  );
}

Future<void> seed(DatabaseExecutor db, {bool italian = false}) async {
  String name((String, String) n) => italian ? n.$2 : n.$1;
  await db.insert('accounts', {
    'name': italian ? 'Conto principale' : 'Main account',
    'icon': 'bank',
    'color': 2,
    'is_main': 1,
  });
  var pos = 0;
  for (final (n, icon, color, subs) in _expenseSeed) {
    final parent = await db.insert('categories', {
      'name': name(n),
      'type': 'OUT',
      'icon': icon,
      'color': color,
      'position': pos++,
    });
    for (final (i, (sn, subIcon)) in subs.indexed) {
      await db.insert('categories', {
        'name': name(sn),
        'type': 'OUT',
        'icon': subIcon,
        'color': color,
        'parent_id': parent,
        'position': i,
      });
    }
  }
  for (final (n, icon, color) in _incomeSeed) {
    await db.insert('categories', {'name': name(n), 'type': 'IN', 'icon': icon, 'color': color, 'position': pos++});
  }
}
