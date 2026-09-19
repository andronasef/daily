import 'package:flutter_test/flutter_test.dart';

import 'package:aio/core/format/arabic.dart';

void main() {
  group('matchesQuery', () {
    final verse = {
      '_id': 'abc123',
      '_type': 'verse',
      'title': 'الرجاء',
      'verse': 'إلهي أنت رجائي من صغري',
    };

    test('empty query matches everything', () {
      expect(matchesQuery(verse, ''), isTrue);
      expect(matchesQuery(verse, '   '), isTrue);
    });

    test('matches the title', () {
      expect(matchesQuery(verse, 'رجاء'), isTrue);
    });

    test('matches the body, not just the title', () {
      expect(matchesQuery(verse, 'صغري'), isTrue);
    });

    test('alef and ya spellings fold together', () {
      expect(matchesQuery(verse, 'الهي'), isTrue);
      expect(matchesQuery({'verse': 'الهى'}, 'إلهي'), isTrue);
    });

    test('harakat in the stored text do not block a plain query', () {
      expect(matchesQuery({'verse': 'رَجَائِي'}, 'رجائي'), isTrue);
    });

    test('ta marbuta matches ha', () {
      expect(matchesQuery({'name': 'النعمة'}, 'النعمه'), isTrue);
    });

    test('does not match unrelated text', () {
      expect(matchesQuery(verse, 'سلام'), isFalse);
    });

    test('ignores internal fields so an id never matches', () {
      expect(matchesQuery(verse, 'abc123'), isFalse);
    });
  });
}
