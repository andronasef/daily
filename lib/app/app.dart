import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/settings.dart';
import '../features/leyaana/ui/widget_content_page.dart';
import '../features/intercede/data/store.dart';
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

class AioAppState extends State<AioApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  static const _widgetChannel = MethodChannel('aio/widget');
  bool _readingWidgetOpen = false;
  late bool _dark = Settings.instance.isDark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'verseOpenAvailable') await _openWidgetContent();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _openWidgetContent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  /// Coming back to the app is the cheapest moment to drain the تشفع outbox.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      IntercedeStore.instance.onResume();
      _openWidgetContent();
    }
  }

  Future<void> _openWidgetContent() async {
    if (_readingWidgetOpen || _navigator.currentState == null) return;
    _readingWidgetOpen = true;
    try {
      while (mounted) {
        final raw = await _widgetChannel.invokeMethod<String>(
          'consumeVerseOpen',
        );
        if (raw == null) break;
        final item = jsonDecode(raw);
        if (item is! Map) continue;
        final title = item['t'];
        final body = item['full'] ?? item['v'];
        if (title is! String || body is! String) continue;
        if (!mounted) return;
        _navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => WidgetContentPage(title: title, body: body),
          ),
        );
      }
    } on MissingPluginException {
      // Non-Android platforms and widget tests have no native launch payload.
    } on PlatformException {
      // A failed platform read must not prevent the normal home screen.
    } on FormatException {
      // Ignore invalid launch JSON.
    } finally {
      _readingWidgetOpen = false;
    }
  }

  void setDark(bool v) {
    Settings.instance.isDark = v;
    setState(() => _dark = v);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'يومي',
      navigatorKey: _navigator,
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
