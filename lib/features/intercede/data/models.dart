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
    final l = lastPrayedAt;
    if (l == null) return false;
    final now = DateTime.now();
    return l.year == now.year && l.month == now.month && l.day == now.day;
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

/// Every active prayer: pinned first, then not-yet-prayed-today (most neglected
/// at the very top), then today's done ones newest-first so the list empties as you go.
List<EntityPrayer> openPrayers(List<Entity> entities) {
  final pending = <EntityPrayer>[];
  final done = <EntityPrayer>[];
  for (final e in entities) {
    for (final p in e.prayers) {
      if (p.isDone) continue;
      (p.prayedToday ? done : pending).add(EntityPrayer(e, p));
    }
  }
  pending.sort((a, b) {
    if (a.prayer.pinned != b.prayer.pinned) return a.prayer.pinned ? -1 : 1;
    final al = a.prayer.lastPrayedAt, bl = b.prayer.lastPrayedAt;
    if (al == null && bl == null) {
      return a.prayer.title.compareTo(b.prayer.title);
    }
    if (al == null) return -1; // never prayed = most neglected
    if (bl == null) return 1;
    return al.compareTo(bl);
  });
  done.sort((a, b) => b.prayer.lastPrayedAt!.compareTo(a.prayer.lastPrayedAt!));
  return [...pending, ...done];
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
