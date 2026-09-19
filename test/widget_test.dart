import 'package:flutter_test/flutter_test.dart';
import 'package:aio/features/leyaana/data/daily_pick.dart';

// Guards the port of temp/leyaana's daily-pick hash. If any of these drift, the
// app would show a different verse than the PWA. Ground-truth values computed by
// hand from the JS recurrence: hash = (hash<<5)-hash+charCode.
void main() {
  test('hashValue matches JS reference values', () {
    expect(hashValue('a'), 97);
    expect(hashValue('ab'), 3105);
    expect(hashValue('abc'), 96354);
    expect(hashValue(''), 0);
  });

  test('pickIndex is deterministic and in range', () {
    final a = pickIndex('2026-07-24', 'nour', 'verse', 200);
    final b = pickIndex('2026-07-24', 'nour', 'verse', 200);
    expect(a, b);
    expect(a, inInclusiveRange(0, 199));
    // Different type key => different seed => (very likely) different slot.
    expect(pickIndex('2026-07-24', 'nour', 'godName', 200), isNot(a));
  });

  test('getPeriodKey formats', () {
    final d = DateTime.utc(2026, 7, 24, 12);
    expect(getPeriodKey('daily', d), '2026-07-24');
    expect(getPeriodKey('monthly', d), '2026-07');
    expect(getPeriodKey('weekly', d), startsWith('W'));
  });
}
