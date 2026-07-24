import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';

/// One daily local reminder at the user's chosen time.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _id = 1;
  static const _channelId = 'daily_reminder';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Fall back to UTC if the platform can't report its zone.
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    // Re-arm on launch so the schedule survives reboots / app updates.
    if (Settings.instance.notifEnabled) {
      await schedule(
        Settings.instance.notifHour,
        Settings.instance.notifMinute,
      );
    }
  }

  /// Ask OS permission (Android 13+ / iOS). Returns granted.
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  static tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  static Future<void> schedule(int hour, int minute) async {
    await cancel();
    await _plugin.zonedSchedule(
      id: _id,
      title: 'وقت خلوتك 🕊️',
      body: 'افتح التطبيق واقضي وقتك النهارده',
      scheduledDate: _nextInstance(hour, minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'التذكير اليومي',
          channelDescription: 'تذكير يومي بوقت الخلوة',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel() => _plugin.cancel(id: _id);
}
