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
    final byDay = await dailyVersesFor([
      for (var i = 0; i <= Notifications.verseDays; i++)
        now.add(Duration(days: i)),
    ]);
    if (byDay.isEmpty) return;

    await Settings.instance.setCache(
      'verse-widget',
      jsonEncode({
        for (final e in byDay.entries)
          e.key: {'t': e.value.title ?? 'آية اليوم', 'v': e.value.verse},
      }),
    );
    try {
      await _widgetChannel.invokeMethod('update');
    } on MissingPluginException {
      // iOS: no widget.
    }

    if (Settings.instance.verseNotifEnabled) {
      await Notifications.scheduleVerses(byDay);
    }
  } catch (_) {
    // Offline with no cache yet: keep whatever was scheduled last time.
  }
}
