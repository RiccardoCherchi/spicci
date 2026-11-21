import '../data/models.dart';

/// Search criteria; null fields match everything.
class TxnFilter {
  const TxnFilter({this.query = '', this.type, this.categoryId, this.accountId, this.tag, this.from, this.to});

  final String query;
  final TxType? type;

  /// Matches the category itself and its subcategories.
  final int? categoryId;

  /// Matches either side of a transfer.
  final int? accountId;
  final String? tag;

  /// Inclusive day range.
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      query.trim().isEmpty &&
      type == null &&
      categoryId == null &&
      accountId == null &&
      tag == null &&
      from == null &&
      to == null;
}

List<Txn> applyFilter(
  TxnFilter f,
  Iterable<Txn> txns, {
  required Map<int, Category> categories,
  required Map<int, Account> accounts,
  required Map<int, List<String>> tags,
}) {
  final q = f.query.trim().toLowerCase();
  final end = f.to == null ? null : DateTime(f.to!.year, f.to!.month, f.to!.day + 1);
  bool matchesText(Txn t) {
    if (q.isEmpty) return true;
    final c = categories[t.categoryId];
    final haystack = [
      t.note,
      c?.name,
      categories[c?.parentId]?.name,
      accounts[t.accountId]?.name,
      accounts[t.toAccountId]?.name,
      ...?tags[t.id],
    ].whereType<String>().join('\n').toLowerCase();
    return haystack.contains(q);
  }

  return [
    for (final t in txns)
      if ((f.type == null || t.type == f.type) &&
          (f.categoryId == null ||
              t.categoryId == f.categoryId ||
              categories[t.categoryId]?.parentId == f.categoryId) &&
          (f.accountId == null || t.accountId == f.accountId || t.toAccountId == f.accountId) &&
          (f.tag == null || (tags[t.id]?.contains(f.tag) ?? false)) &&
          (f.from == null || !t.date.isBefore(f.from!)) &&
          (end == null || t.date.isBefore(end)) &&
          matchesText(t))
        t,
  ];
}
