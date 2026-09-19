import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over SharedPreferences. Mirrors temp/leyaana/src/utils/settings.ts
/// plus the notification time. Single user, so a global instance is fine.
class Settings {
  Settings._(this._prefs);

  final SharedPreferences _prefs;
  static Settings? _instance;

  static Future<Settings> init() async {
    _instance ??= Settings._(await SharedPreferences.getInstance());
    return _instance!;
  }

  static Settings get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Settings.init() must be awaited before use.');
    }
    return i;
  }

  // Keys
  static const _name = 'name';
  static const _isMale = 'isMale';
  static const _isDark = 'isDark';
  static const _onboarded = 'onboarded';
  static const _notifEnabled = 'notifEnabled';
  static const _notifHour = 'notifHour';
  static const _notifMinute = 'notifMinute';
  static const _verseNotif = 'verseNotifEnabled';

  String get name => _prefs.getString(_name) ?? '';
  set name(String v) => _prefs.setString(_name, v.trim());

  /// leyaana falls back to a prompt string when no name is set; keep parity so
  /// the daily-pick userKey matches the PWA exactly.
  String get personKey =>
      name.isEmpty ? '[لو سمحت دخل اسمك في الاعدادات]' : name;

  bool get isMale => _prefs.getBool(_isMale) ?? true;
  set isMale(bool v) => _prefs.setBool(_isMale, v);

  bool get isDark => _prefs.getBool(_isDark) ?? false;
  set isDark(bool v) => _prefs.setBool(_isDark, v);

  bool get onboarded => _prefs.getBool(_onboarded) ?? false;
  set onboarded(bool v) => _prefs.setBool(_onboarded, v);

  bool get notifEnabled => _prefs.getBool(_notifEnabled) ?? false;
  set notifEnabled(bool v) => _prefs.setBool(_notifEnabled, v);

  int get notifHour => _prefs.getInt(_notifHour) ?? 7;
  set notifHour(int v) => _prefs.setInt(_notifHour, v);

  int get notifMinute => _prefs.getInt(_notifMinute) ?? 0;
  set notifMinute(int v) => _prefs.setInt(_notifMinute, v);

  bool get verseNotifEnabled => _prefs.getBool(_verseNotif) ?? false;
  set verseNotifEnabled(bool v) => _prefs.setBool(_verseNotif, v);

  /// Sanity write token for the ليا انا editor and تشفع. Entered in Settings,
  /// kept on-device.
  String get sanityToken => _prefs.getString('sanityWriteToken') ?? '';
  set sanityToken(String v) => _prefs.setString('sanityWriteToken', v.trim());

  /// Gemini API key for the لليوم فقط translation. Entered in Settings.
  String get geminiKey => _prefs.getString('geminiKey') ?? '';
  set geminiKey(String v) => _prefs.setString('geminiKey', v.trim());
  // Generic string cache (used by sections 2 & 3 for offline/per-day data).
  String? getCache(String key) => _prefs.getString(key);
  Future<void> setCache(String key, String value) =>
      _prefs.setString(key, value);
}
