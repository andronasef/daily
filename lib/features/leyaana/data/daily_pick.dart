import '../../../core/settings.dart';

/// JS: hash = (hash<<5)-hash+code; hash |= 0; return Math.abs(hash).
/// `|= 0` forces 32-bit signed wraparound — Dart ints are 64-bit, so clamp
/// each step with toSigned(32).
int hashValue(String value) {
  int hash = 0;
  for (int i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.codeUnitAt(i)).toSigned(32);
  }
  return hash.abs();
}

/// JS getPeriodKey uses date.toISOString() (UTC), so day/week/month buckets are
/// UTC-based. Keep that or the index diverges near midnight.
String getPeriodKey(String period, [DateTime? date]) {
  final utc = (date ?? DateTime.now()).toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');

  if (period == 'monthly') return '$y-$m';
  if (period == 'daily') return '$y-$m-$d';

  // weekly: days since epoch of UTC midnight, +4 so the boundary lands Sunday.
  final daysSinceEpoch =
      (DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch /
              86400000)
          .floor();
  return 'W${((daysSinceEpoch + 4) / 7).floor()}';
}

int pickIndex(String periodKey, String userKey, String typeKey, int length) {
  return hashValue('$periodKey:$userKey:$typeKey') % length;
}

/// Picks the same item the PWA would for the current UTC period + this user.
Map<String, dynamic>? pick(
  List<Map<String, dynamic>> items,
  String typeKey,
  String period,
) {
  if (items.isEmpty) return null;
  final key = getPeriodKey(period);
  final idx = pickIndex(
    key,
    Settings.instance.personKey,
    typeKey,
    items.length,
  );
  return items[idx];
}
