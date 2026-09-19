import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'background.dart';
import 'settings.dart';
import 'theme.dart';
import 'notifications.dart';
import 'onboarding.dart';
import 'home.dart';
import 'verse_surfaces.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.init();
  await Notifications.init();
  runApp(const AioApp());
  // Not awaited: network shouldn't delay first frame.
  refreshVerseSurfaces();
  initDailyPrefetch();
  prefetchJftNow();
}

/// Holds theme mode so Settings can flip dark/light live. Single-user app, so a
/// plain lookup over a StatefulWidget is enough — no state package.
class AioApp extends StatefulWidget {
  const AioApp({super.key});

  static AioAppState of(BuildContext context) =>
      context.findAncestorStateOfType<AioAppState>()!;

  @override
  State<AioApp> createState() => AioAppState();
}

class AioAppState extends State<AioApp> {
  late bool _dark = Settings.instance.isDark;

  void setDark(bool v) {
    Settings.instance.isDark = v;
    setState(() => _dark = v);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'يومي',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: Settings.instance.onboarded ? const HomePage() : const Onboarding(),
    );
  }
}
