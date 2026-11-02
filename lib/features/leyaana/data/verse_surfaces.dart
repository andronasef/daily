import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/notifications.dart';
import '../../../core/settings.dart';
import 'repository.dart';

const _widgetChannel = MethodChannel('aio/widget');

/// Precomputes the next days' verses (deterministic per UTC day) and hands them
/// to the widget (via SharedPreferences, read natively) and the verse
/// notifications. Call on launch and when related settings change.
/// ponytail: buffer runs dry after [Notifications.verseDays] days without
/// opening the app; add a WorkManager refresh if that matters.
Future<void> refreshVerseSurfaces() async {
  try {
    final now = DateTime.now();
    final content = await dailyWidgetContentFor([
      for (var i = 0; i <= Notifications.verseDays; i++)
        now.add(Duration(days: i)),
    ]);
    if (content.values.every(
      (c) => c.dailyVerse == null && c.blessing == null && c.godName == null,
    )) {
      return;
    }
    final byDay = {
      for (final e in content.entries)
        if (e.value.dailyVerse != null) e.key: e.value.dailyVerse!,
    };

    await Settings.instance.setCache(
      'verse-widget',
      jsonEncode({
        for (final e in content.entries)
          e.key: {'items': verseWidgetItems(e.value)},
      }),
    );
    try {
      await _widgetChannel.invokeMethod('update');
    } on MissingPluginException {
      // iOS: no widget.
    }

    if (Settings.instance.verseNotifEnabled && byDay.isNotEmpty) {
      await Notifications.scheduleVerses(byDay);
    }
  } catch (_) {
    // Offline with no cache yet: keep whatever was scheduled last time.
  }
}

/// Display order is shared with the native tap-cycle. Keep full details separate
/// from the compact widget preview so opening it never loses the explanation.
List<Map<String, String>> verseWidgetItems(DailyContent content) {
  Map<String, String> named(String kind, String label, NamedContent? item) {
    final details = [
      if (item?.mean?.isNotEmpty == true) item!.mean!,
      if (item?.content?.isNotEmpty == true) item!.content!,
    ];
    final full = details.isEmpty
        ? (item?.name ?? 'افتح التطبيق لتحميل المحتوى')
        : details.join('\n\n');
    return {
      'kind': kind,
      't': item == null ? label : '$label · ${item.name}',
      'v': details.isEmpty ? full : details.first,
      'full': full,
    };
  }

  final verse = content.dailyVerse;
  return [
    {
      'kind': 'verse',
      't': verse?.title ?? 'آية اليوم',
      'v': verse?.verse ?? 'افتح التطبيق لتحميل آية اليوم',
      'full': verse?.verse ?? 'افتح التطبيق لتحميل آية اليوم',
    },
    named('blessing', 'البركة الروحية', content.blessing),
    named('godName', 'اسم الله', content.godName),
  ];
}
