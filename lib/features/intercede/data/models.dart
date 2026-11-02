import '../../../core/format/arabic.dart';

export '../../../core/format/dates.dart';

class PrayerLog {
  PrayerLog({required this.prayedAt, this.note});
  final DateTime prayedAt;
  final String? note;
}

class Prayer {
  Prayer({
    required this.id,
    required this.title,
    this.startedAt,
    this.completedAt,
    this.outcome,
    this.pinned = false,
    this.logs = const [],
  });

  final String id;
  final String title;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? outcome;
  final bool pinned;
  final List<PrayerLog> logs;

  bool get isDone => completedAt != null;

  /// Already prayed at some point today — drives the daily checklist.
  bool get prayedToday {
    return prayedOn(DateTime.now());
  }

  bool prayedOn(DateTime now) {
    final last = lastPrayedAt?.toLocal();
    final day = now.toLocal();
    return last != null &&
        last.year == day.year &&
        last.month == day.month &&
        last.day == day.day;
  }

  DateTime? get lastPrayedAt => logs.isEmpty
      ? null
      : logs.map((l) => l.prayedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class Entity {
  Entity({
    required this.id,
    required this.name,
    this.note,
    this.createdAt,
    this.prayers = const [],
  });

  final String id;
  final String name;
  final String? note;
  final DateTime? createdAt;
  final List<Prayer> prayers;

  List<Prayer> get active {
    final list = prayers.where((p) => !p.isDone).toList();
    list.sort((a, b) {
      final al = a.lastPrayedAt;
      final bl = b.lastPrayedAt;
      if (al == null && bl == null) return 0;
      if (al == null) return -1;
      if (bl == null) return 1;
      return al.compareTo(bl);
    });
    return list;
  }

  List<Prayer> get archived {
    final list = prayers.where((p) => p.isDone).toList();
    list.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return list;
  }

  DateTime? get lastPrayedAt {
    final dates = prayers
        .map((p) => p.lastPrayedAt)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

/// A prayer together with the entity it belongs to, for the flat lists that
/// cut across entities (the daily checklist and the archive).
class EntityPrayer {
  EntityPrayer(this.entity, this.prayer);
  final Entity entity;
  final Prayer prayer;
}

enum PrayerSort {
  random('عشوائي'),
  neglected('الأكتر إهمالاً'),
  oldest('الأقدم إضافة'),
  newest('الأحدث إضافة'),
  alphabetical('أبجدي');

  const PrayerSort(this.label);
  final String label;
  static PrayerSort fromName(String? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => random);
}

/// Stable across rebuilds, input order and process restarts; local day first.
int _dailyRank(String id, DateTime day) {
  var hash = 0x811c9dc5;
  for (final c in '${day.year}-${day.month}-${day.day}:$id'.codeUnits) {
    hash = ((hash ^ c) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

List<EntityPrayer> countedPrayers(List<EntityPrayer> items) =>
    items.any((i) => i.prayer.pinned)
    ? items.where((i) => i.prayer.pinned).toList()
    : items;

List<EntityPrayer> openPrayers(
  List<Entity> entities, {
  PrayerSort sort = PrayerSort.random,
  DateTime? now,
}) {
  final day = (now ?? DateTime.now()).toLocal();
  final items = [
    for (final e in entities)
      for (final p in e.prayers)
        if (!p.isDone) EntityPrayer(e, p),
  ];
  int dates(DateTime? a, DateTime? b, {bool descending = false}) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  items.sort((a, b) {
    final ap = a.prayer, bp = b.prayer;
    final ad = ap.prayedOn(day), bd = bp.prayedOn(day);
    if (ad != bd) return ad ? 1 : -1;
    if (ad) {
      final result = bp.lastPrayedAt!.compareTo(ap.lastPrayedAt!);
      return result != 0 ? result : ap.id.compareTo(bp.id);
    }
    if (ap.pinned != bp.pinned) return ap.pinned ? -1 : 1;
    final result = switch (sort) {
      PrayerSort.random => _dailyRank(
        ap.id,
        day,
      ).compareTo(_dailyRank(bp.id, day)),
      PrayerSort.neglected =>
        ap.lastPrayedAt == null
            ? (bp.lastPrayedAt == null ? 0 : -1)
            : bp.lastPrayedAt == null
            ? 1
            : ap.lastPrayedAt!.compareTo(bp.lastPrayedAt!),
      PrayerSort.oldest => dates(ap.startedAt, bp.startedAt),
      PrayerSort.newest => dates(ap.startedAt, bp.startedAt, descending: true),
      PrayerSort.alphabetical => normalizeArabic(
        ap.title,
      ).compareTo(normalizeArabic(bp.title)),
    };
    return result != 0 ? result : ap.id.compareTo(bp.id);
  });
  return items;
}

/// Every completed prayer across all entities, most recently answered first.
List<EntityPrayer> answeredPrayers(List<Entity> entities) {
  final all = <EntityPrayer>[];
  for (final e in entities) {
    for (final p in e.prayers) {
      if (p.isDone) all.add(EntityPrayer(e, p));
    }
  }
  all.sort((a, b) => b.prayer.completedAt!.compareTo(a.prayer.completedAt!));
  return all;
}
