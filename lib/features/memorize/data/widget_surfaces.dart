import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/settings.dart';
import 'memorize_db.dart';
import 'memorize_models.dart';

List<Map<String, Object>> memorizeWidgetItems(List<MemorizeVerse> verses) => [
  for (final verse in verses)
    if (verse.state != SrsState.mastered)
      {
        'id': verse.id,
        't': verse.title,
        'v': verse.verse,
        'full': [
          verse.verse,
          if (verse.translation.isNotEmpty) verse.translation,
        ].join('\n\n'),
        'due': verse.dueDate.millisecondsSinceEpoch,
        'new': verse.state == SrsState.newCard,
      },
];

Future<void> _publishing = Future.value();

/// Local data only. Refresh after edits/reviews so mastered/deleted cards vanish.
Future<void> refreshMemorizeWidget() {
  final next = _publishing.then((_) async {
    try {
      final db = await MemorizeDb.open();
      final items = memorizeWidgetItems(await db.getAll());
      await Settings.instance.setCache('memorize-widget', jsonEncode(items));
      await const MethodChannel('aio/widget').invokeMethod<void>('update');
    } catch (_) {
      // A widget must never block a saved review or a platform without SQLite.
    }
  });
  _publishing = next;
  return next;
}
