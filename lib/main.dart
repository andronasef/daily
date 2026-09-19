import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/background.dart';
import 'core/notifications.dart';
import 'core/settings.dart';
import 'features/leyaana/data/verse_surfaces.dart';

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
