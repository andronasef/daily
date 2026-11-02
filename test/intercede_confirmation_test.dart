import 'package:aio/features/intercede/ui/intercede_screen.dart';
import 'package:flutter/material.dart';
import 'package:aio/features/intercede/data/models.dart';
import 'package:aio/features/intercede/ui/widgets/prayer_checklist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'today’s prayed requests expand separately from pending requests',
    (tester) async {
      final entity = Entity(id: 'e', name: 'person');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrayerChecklist(
              items: [
                EntityPrayer(
                  entity,
                  Prayer(id: 'pending', title: 'Pending request'),
                ),
                EntityPrayer(
                  entity,
                  Prayer(
                    id: 'done',
                    title: 'Prayed request',
                    logs: [PrayerLog(prayedAt: DateTime.now())],
                  ),
                ),
              ],
              header: const Text('Today'),
              itemBuilder: (item) => Text(item.prayer.title),
            ),
          ),
        ),
      );
      expect(find.text('Pending request'), findsOneWidget);
      expect(find.text('Prayed request'), findsNothing);
      await tester.tap(find.text('تم الصلاة النهاردة (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Prayed request'), findsOneWidget);
      expect(find.text('Pending request'), findsOneWidget);
      await tester.tap(find.text('تم الصلاة النهاردة (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Prayed request'), findsNothing);
    },
  );

  testWidgets(
    'praying requires explicit confirmation and cancel saves nothing',
    (tester) async {
      String? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await askNote(context, prayerTitle: 'طلب اختبار');
                returned = true;
              },
              child: const Text('pray'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pray'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('طلب اختبار'), findsOneWidget);
      expect(returned, isFalse);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      returned = false;
      await tester.tap(find.text('pray'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أيوه، صليت'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, '');
    },
  );
}
