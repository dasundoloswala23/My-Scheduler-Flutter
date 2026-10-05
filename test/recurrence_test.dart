import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/models/task.dart';

void main() {
  group('nextOccurrence', () {
    test('a one-off task has no next date', () {
      expect(nextOccurrence(DateTime(2026, 10, 5), Recurrence.none), isNull);
    });

    test('daily moves one day', () {
      expect(
        nextOccurrence(DateTime(2026, 10, 5, 9, 30), Recurrence.daily),
        DateTime(2026, 10, 6, 9, 30),
      );
    });

    test('weekly moves seven days', () {
      expect(
        nextOccurrence(DateTime(2026, 10, 5), Recurrence.weekly),
        DateTime(2026, 10, 12),
      );
    });

    test('monthly moves one month', () {
      expect(
        nextOccurrence(DateTime(2026, 10, 5, 8), Recurrence.monthly),
        DateTime(2026, 11, 5, 8),
      );
    });

    test('yearly moves one year', () {
      expect(
        nextOccurrence(DateTime(2026, 10, 5, 8), Recurrence.yearly),
        DateTime(2027, 10, 5, 8),
      );
    });

    test('weekdays skips the weekend', () {
      // 2026-10-09 is a Friday, so the next weekday is Monday the 12th.
      final friday = DateTime(2026, 10, 9);
      expect(friday.weekday, DateTime.friday);

      final next = nextOccurrence(friday, Recurrence.weekdays)!;
      expect(next.weekday, DateTime.monday);
      expect(next, DateTime(2026, 10, 12));
    });

    test('weekdays moves one day in the middle of the week', () {
      final tuesday = DateTime(2026, 10, 6);
      expect(tuesday.weekday, DateTime.tuesday);
      expect(nextOccurrence(tuesday, Recurrence.weekdays), DateTime(2026, 10, 7));
    });

    test('a series always moves forward, never back', () {
      final start = DateTime(2026, 10, 5, 12);
      for (final r in Recurrence.values.where((r) => r != Recurrence.none)) {
        final next = nextOccurrence(start, r)!;
        expect(next.isAfter(start), isTrue, reason: '$r must advance');
      }
    });
  });
}
