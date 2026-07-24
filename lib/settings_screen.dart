import 'package:flutter/material.dart';

import 'main.dart';
import 'settings.dart';
import 'notifications.dart';
import 'onboarding.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = Settings.instance;

  Future<void> _toggleReminder(bool on) async {
    if (on) {
      final granted = await Notifications.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لازم تسمح بالإشعارات من إعدادات الجهاز.')));
        }
        return;
      }
      await Notifications.schedule(_s.notifHour, _s.notifMinute);
    } else {
      await Notifications.cancel();
    }
    setState(() => _s.notifEnabled = on);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _s.notifHour, minute: _s.notifMinute),
    );
    if (picked == null) return;
    _s
      ..notifHour = picked.hour
      ..notifMinute = picked.minute;
    if (_s.notifEnabled) {
      await Notifications.schedule(picked.hour, picked.minute);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = TimeOfDay(hour: _s.notifHour, minute: _s.notifMinute)
        .format(context);
    final dark = _s.isDark;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('التذكير اليومي'),
            subtitle: Text('تنبيه واحد كل يوم الساعة $timeLabel'),
            value: _s.notifEnabled,
            onChanged: _toggleReminder,
          ),
          ListTile(
            enabled: _s.notifEnabled,
            title: const Text('وقت التذكير'),
            trailing: Text(timeLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: _s.notifEnabled ? _pickTime : null,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('الوضع الليلي'),
            value: dark,
            onChanged: (v) {
              AioApp.of(context).setDark(v);
              setState(() {});
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('تعديل الاسم والنوع'),
            subtitle: Text('الاسم الحالي: ${_s.name}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Onboarding()),
            ),
          ),
        ],
      ),
    );
  }
}
