import 'package:workmanager/workmanager.dart';

import 'sections/just_for_today.dart';
import 'settings.dart';

const _jftTask = 'jftPrefetch';

/// Runs in its own isolate with no app state, so everything it touches has to
/// be re-initialised here.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _jftTask) return true;
    await Settings.init();
    if (Settings.instance.geminiKey.isEmpty) return true; // nothing we can do
    if (jftCachedForToday()) return true;
    try {
      await loadJft();
      return true;
    } catch (_) {
      return false; // let WorkManager back off and retry
    }
  });
}

/// Warms لليوم فقط once a day so opening the section is instant instead of
/// waiting on jftna.org plus a Gemini translation.
///
/// ponytail: ExistingPeriodicWorkPolicy.keep, not replace — replace would reset
/// the 24h timer on every launch, so for a daily-use app the task would never
/// fire. The cost is that changing [frequency] needs an app reinstall.
Future<void> initDailyPrefetch() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'jft-daily',
    _jftTask,
    frequency: const Duration(hours: 24),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
  );
}

/// Belt and braces: WorkManager can be deferred for hours under Doze, so top
/// the cache up on launch too. Cheap when today is already cached.
Future<void> prefetchJftNow() async {
  if (Settings.instance.geminiKey.isEmpty || jftCachedForToday()) return;
  try {
    await loadJft();
  } catch (_) {
    // The screen will retry and show a real error if it still fails.
  }
}
