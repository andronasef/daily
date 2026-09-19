/// Folds the spelling differences that would otherwise make an Arabic search
/// miss: harakat, tatweel, the alef/ya/ta-marbuta variants.
String normalizeArabic(String input) => input
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp('[\u0623\u0625\u0622\u0671]'), '\u0627')
    .replaceAll('\u0649', '\u064A')
    .replaceAll('\u0629', '\u0647')
    .toLowerCase()
    .trim();

/// Matches a raw admin document against a query, across every text field it
/// has — title and body alike, so searching a phrase you remember works
/// whether it was the heading or the content.
bool matchesQuery(Map<String, dynamic> item, String query) {
  final q = normalizeArabic(query);
  if (q.isEmpty) return true;
  for (final entry in item.entries) {
    if (entry.key.startsWith('_')) continue;
    final v = entry.value;
    if (v is! String) continue;
    if (normalizeArabic(v).contains(q)) return true;
  }
  return false;
}
