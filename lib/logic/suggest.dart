import '../data/models.dart';

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<String> _words(String text) => _word.allMatches(text.toLowerCase()).map((m) => m[0]!).toList();

/// Learns which categories go with which note words, from the user's own history.
class CategorySuggester {
  CategorySuggester(Iterable<Txn> history) {
    for (final t in history) {
      final note = t.note?.trim();
      if (t.categoryId == null || note == null || note.isEmpty) continue;
      _bump(_byNote.putIfAbsent(_words(note).join(' '), () => {}), t.categoryId!);
      for (final w in _words(note).toSet().where((w) => w.length >= 3)) {
        _bump(_byWord.putIfAbsent(w, () => {}), t.categoryId!);
      }
    }
  }

  final _byNote = <String, Map<int, int>>{};
  final _byWord = <String, Map<int, int>>{};

  static void _bump(Map<int, int> counts, int id) => counts.update(id, (n) => n + 1, ifAbsent: () => 1);

  /// Best category for [note] among those [allowed], or null. An identical past
  /// note wins; otherwise each word (or the word being typed, as a prefix) votes.
  int? suggest(String note, {bool Function(int categoryId)? allowed}) {
    final words = _words(note);
    if (words.isEmpty) return null;
    final scores = <int, double>{};
    void add(Map<int, int>? counts, double weight) {
      counts?.forEach((id, n) {
        if (allowed == null || allowed(id)) scores.update(id, (s) => s + n * weight, ifAbsent: () => n * weight);
      });
    }

    add(_byNote[words.join(' ')], 10);
    for (final (i, w) in words.indexed) {
      if (w.length < 3) continue;
      add(_byWord[w], 1);
      // The last word may still be half typed.
      if (i == words.length - 1) {
        for (final e in _byWord.entries) {
          if (e.key != w && e.key.startsWith(w)) add(e.value, 0.5);
        }
      }
    }
    if (scores.isEmpty) return null;
    return scores.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
