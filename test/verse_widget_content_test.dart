import 'package:aio/features/leyaana/data/repository.dart';
import 'package:aio/features/leyaana/data/verse_surfaces.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:aio/features/leyaana/ui/widget_content_page.dart';

void main() {
  testWidgets(
    'opened widget item retains its complete scrollable explanation',
    (tester) async {
      final body = List.filled(40, 'تفاصيل البركة الروحية').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: WidgetContentPage(title: 'بركة مختارة', body: body),
        ),
      );
      expect(find.text('بركة مختارة'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        body,
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    },
  );

  test('widget cycles verse, blessing, God name with full text preserved', () {
    final items = verseWidgetItems(
      DailyContent(
        dailyVerse: Verse(id: 'v', title: 'مرجع', verse: 'آية'),
        weeklyVerse: null,
        monthlyVerse: null,
        blessing: NamedContent(
          id: 'b',
          name: 'بركة',
          mean: 'معنى',
          content: 'شرح البركة',
        ),
        godName: NamedContent(
          id: 'g',
          name: 'اسم',
          mean: 'المعنى',
          content: 'شرح الاسم',
        ),
      ),
    );
    expect(items.map((i) => i['kind']), ['verse', 'blessing', 'godName']);
    expect(items[0]['full'], 'آية');
    expect(items[1]['full'], 'معنى\n\nشرح البركة');
    expect(items[2]['full'], 'المعنى\n\nشرح الاسم');
    expect(items[1]['t'], contains('بركة'));
  });
  test('missing content keeps three explicit empty states', () {
    final items = verseWidgetItems(
      DailyContent(
        dailyVerse: null,
        weeklyVerse: null,
        monthlyVerse: null,
        blessing: null,
        godName: null,
      ),
    );
    expect(items, hasLength(3));
    expect(items.every((item) => item['v']!.isNotEmpty), isTrue);
  });
}
