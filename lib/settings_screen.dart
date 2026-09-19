import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import 'updater.dart';

import 'main.dart';
import 'settings.dart';
import 'notifications.dart';
import 'onboarding.dart';
import 'verse_surfaces.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = Settings.instance;
  late final _token = TextEditingController(text: _s.sanityToken);
  late final _gemini = TextEditingController(text: _s.geminiKey);
  String? _updateStatus;

  @override
  void dispose() {
    _token.dispose();
    _gemini.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() => _updateStatus = 'بندوّر على تحديث…');
    try {
      final u = await checkForUpdate();
      if (u == null) {
        setState(() => _updateStatus = 'إنت على آخر إصدار.');
        return;
      }
      installUpdate(u).listen(
        (e) => setState(() => _updateStatus = switch (e.status) {
              OtaStatus.DOWNLOADING => 'تحميل ${u.version}… ${e.value}%',
              OtaStatus.INSTALLING => 'بنثبّت…',
              _ => 'تعذّر التحديث: ${e.status.name}',
            }),
        onError: (_) => setState(() => _updateStatus = 'تعذّر التحديث.'),
      );
    } catch (_) {
      setState(() => _updateStatus = 'تعذّر الاتصال بالتحديثات.');
    }
  }

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

  Future<void> _toggleVerse(bool on) async {
    if (on) {
      final granted = await Notifications.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لازم تسمح بالإشعارات من إعدادات الجهاز.')));
        }
        return;
      }
    }
    _s.verseNotifEnabled = on;
    if (on) {
      await refreshVerseSurfaces();
    } else {
      await Notifications.cancelVerses();
    }
    setState(() {});
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
    if (_s.verseNotifEnabled) await refreshVerseSurfaces();
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
          SwitchListTile(
            title: const Text('آية اليوم في الإشعار'),
            subtitle: const Text('إشعار بالآية كاملة في نفس وقت التذكير'),
            value: _s.verseNotifEnabled,
            onChanged: _toggleVerse,
          ),
          ListTile(
            enabled: _s.notifEnabled || _s.verseNotifEnabled,
            title: const Text('وقت التذكير'),
            trailing: Text(timeLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: (_s.notifEnabled || _s.verseNotifEnabled) ? _pickTime : null,
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
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _token,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Sanity write token',
                helperText: 'لتعديل ليا انا وتشفع — بيتحفظ على الجهاز بس',
              ),
              onChanged: (v) => _s.sanityToken = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _gemini,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Gemini API key',
                helperText: 'لترجمة لليوم فقط — بيتحفظ على الجهاز بس',
              ),
              onChanged: (v) => _s.geminiKey = v,
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('التحقق من تحديث'),
            subtitle: _updateStatus == null ? null : Text(_updateStatus!),
            trailing: const Icon(Icons.system_update),
            onTap: _update,
          ),
        ],
      ),
    );
  }
}
