import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../app/app.dart';
import '../../core/notifications.dart';
import '../../core/settings.dart';
import '../../core/updater.dart';
import '../leyaana/data/verse_surfaces.dart';
import '../onboarding/onboarding_screen.dart';

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
        (e) => setState(
          () => _updateStatus = switch (e.status) {
            OtaStatus.DOWNLOADING => 'تحميل ${u.version}… ${e.value}%',
            OtaStatus.INSTALLING => 'بنثبّت…',
            _ => 'تعذّر التحديث: ${e.status.name}',
          },
        ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لازم تسمح بالإشعارات من إعدادات الجهاز.'),
            ),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لازم تسمح بالإشعارات من إعدادات الجهاز.'),
            ),
          );
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
    final timeLabel = TimeOfDay(
      hour: _s.notifHour,
      minute: _s.notifMinute,
    ).format(context);
    final anyReminder = _s.notifEnabled || _s.verseNotifEnabled;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Section('التذكيرات'),
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
            enabled: anyReminder,
            title: const Text('وقت التذكير'),
            subtitle: anyReminder
                ? null
                : const Text('فعّل تذكير عشان تحدد الوقت'),
            trailing: Text(
              timeLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: anyReminder ? cs.primary : null,
              ),
            ),
            onTap: anyReminder ? _pickTime : null,
          ),
          const _Section('المظهر'),
          SwitchListTile(
            title: const Text('الوضع الليلي'),
            secondary: Icon(_s.isDark ? Icons.dark_mode : Icons.light_mode),
            value: _s.isDark,
            onChanged: (v) {
              AioApp.of(context).setDark(v);
              setState(() {});
            },
          ),
          const _Section('حسابك'),
          ListTile(
            title: const Text('تعديل الاسم والنوع'),
            subtitle: Text('الاسم الحالي: ${_s.name}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const Onboarding())),
          ),
          const _Section('المفاتيح'),
          _SecretField(
            controller: _token,
            label: 'Sanity write token',
            helper: 'لتعديل ليا انا وتشفع — بيتحفظ على الجهاز بس',
            onChanged: (v) => _s.sanityToken = v,
          ),
          _SecretField(
            controller: _gemini,
            label: 'Gemini API key',
            helper: 'لترجمة لليوم فقط — بيتحفظ على الجهاز بس',
            onChanged: (v) => _s.geminiKey = v,
          ),
          const _Section('التطبيق'),
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

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 28, 16, 4),
      child: Text(
        title,
        style: t.textTheme.titleSmall?.copyWith(
          color: t.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label, helper;
  final ValueChanged<String> onChanged;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'إظهار' : 'إخفاء',
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
      onChanged: widget.onChanged,
    ),
  );
}
