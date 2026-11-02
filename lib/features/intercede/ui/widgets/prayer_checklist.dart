import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Keeps today's completed prayers available without crowding pending requests.
class PrayerChecklist extends StatelessWidget {
  const PrayerChecklist({
    super.key,
    required this.items,
    required this.header,
    required this.itemBuilder,
  });
  final List<EntityPrayer> items;
  final Widget header;
  final Widget Function(EntityPrayer) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((item) => !item.prayer.prayedToday);
    final prayed = items.where((item) => item.prayer.prayedToday).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 10),
        for (final item in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: itemBuilder(item),
          ),
        if (prayed.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('prayed-today'),
            title: Text('تم الصلاة النهاردة (${prayed.length})'),
            leading: const Icon(Icons.check_circle_outline),
            children: [for (final item in prayed) itemBuilder(item)],
          ),
      ],
    );
  }
}
