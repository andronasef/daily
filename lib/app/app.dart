import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/settings.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'theme.dart';

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
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Settings.instance.onboarded ? const HomePage() : const Onboarding(),
    );
  }
}
