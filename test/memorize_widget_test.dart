import 'package:aio/features/memorize/data/memorize_models.dart';
import 'package:aio/features/memorize/data/widget_surfaces.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'memorization widget retains due metadata and excludes mastered verses',
    () {
      final now = DateTime(2026, 11, 3);
      MemorizeVerse verse(String id, SrsState state) => MemorizeVerse(
        id: id,
        title: 'مرجع',
        verse: 'آية $id',
        translation: 'تفسير',
        createdAt: now,
        dueDate: now,
        state: state,
      );
      final items = memorizeWidgetItems([
        verse('new', SrsState.newCard),
        verse('learning', SrsState.learning),
        verse('mastered', SrsState.mastered),
      ]);
      expect(items.map((item) => item['id']), ['new', 'learning']);
      expect(items.first['new'], true);
      expect(items.last['new'], false);
      expect(items.first['due'], now.millisecondsSinceEpoch);
      expect(items.first['full'], 'آية new\n\nتفسير');
    },
  );
}
