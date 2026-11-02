import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/settings.dart';
import 'models.dart';

class WidgetPrayerTap {
  const WidgetPrayerTap(this.key, this.prayerId, this.at);
  final String key;
  final String prayerId;
  final DateTime at;

  static WidgetPrayerTap? parse(dynamic raw) {
    if (raw is! Map) return null;
    final key = raw['k'], id = raw['id'], at = raw['at'];
    if (key is! String ||
        !RegExp(r'^[a-z0-9]{1,64}$').hasMatch(key) ||
        id is! String ||
        id.isEmpty ||
        at is! int ||
        at <= 0 ||
        at >
            DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch) {
      return null;
    }
    return WidgetPrayerTap(key, id, DateTime.fromMillisecondsSinceEpoch(at));
  }
}

String intercedeWidgetSnapshot(
  List<Entity> entities, {
  PrayerSort sort = PrayerSort.random,
  DateTime? now,
}) {
  final ordered = openPrayers(entities, sort: sort, now: now);
  final counted = countedPrayers(ordered).map((i) => i.prayer.id).toSet();
  return jsonEncode({
    'items': [
      for (final item in ordered)
        {
          'id': item.prayer.id,
          't': item.prayer.title,
          'e': item.entity.name,
          'last': item.prayer.lastPrayedAt?.millisecondsSinceEpoch,
          'c': counted.contains(item.prayer.id),
        },
    ],
  });
}

/// Only Kotlin owns the queue file. No cached SharedPreferences reads or clears.
class IntercedeWidgetBridge {
  IntercedeWidgetBridge();
  static const _channel = MethodChannel('aio/widget');
  Future<void> _publishing = Future.value();

  Future<void> publish(String snapshot) {
    final next = _publishing.then((_) async {
      await Settings.instance.setCache('intercede-widget', snapshot);
      try {
        await _channel.invokeMethod<void>('update');
      } on MissingPluginException {
        // Unit tests and platforms with no Android widget implementation.
      }
    });
    _publishing = next.catchError((Object _) {});
    return next;
  }

  Future<List<WidgetPrayerTap>> peek() async {
    try {
      final raw = await _channel.invokeMethod<String>('peekIntercedeTaps');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map(WidgetPrayerTap.parse)
          .whereType<WidgetPrayerTap>()
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  Future<void> ack(List<String> keys) =>
      _channel.invokeMethod<void>('ackIntercedeTaps', keys);
}
