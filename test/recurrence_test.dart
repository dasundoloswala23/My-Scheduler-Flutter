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

    group('month ends are clamped, never overflowed', () {
      test('31 January becomes the last day of February, not 3 March', () {
        expect(nextOccurrence(DateTime(2027, 1, 31, 9), Recurrence.monthly), DateTime(2027, 2, 28, 9));
      });

      test('in a leap year it becomes 29 February', () {
        expect(nextOccurrence(DateTime(2028, 1, 31, 9), Recurrence.monthly), DateTime(2028, 2, 29, 9));
      });

      test('30 March becomes 30 April, and 31 March becomes 30 April', () {
        expect(nextOccurrence(DateTime(2027, 3, 30), Recurrence.monthly), DateTime(2027, 4, 30));
        expect(nextOccurrence(DateTime(2027, 3, 31), Recurrence.monthly), DateTime(2027, 4, 30));
      });

      test('a day that exists in the next month is kept', () {
        expect(nextOccurrence(DateTime(2027, 4, 30), Recurrence.monthly), DateTime(2027, 5, 30));
      });

      test('December rolls into January of the next year', () {
        expect(nextOccurrence(DateTime(2026, 12, 15, 8, 30), Recurrence.monthly),
            DateTime(2027, 1, 15, 8, 30));
      });

      test('29 February repeats yearly on 28 February in a common year', () {
        expect(nextOccurrence(DateTime(2028, 2, 29), Recurrence.yearly), DateTime(2029, 2, 28));
      });

      test('the time of day is untouched by clamping', () {
        final next = nextOccurrence(DateTime(2027, 1, 31, 17, 45), Recurrence.monthly)!;
        expect((next.hour, next.minute), (17, 45));
      });

      test('known limitation: a clamped monthly series stays on the lower day', () {
        // 31 Jan -> 28 Feb -> 28 Mar. Only the current date is stored, not the
        // day the series began on, so it cannot return to the 31st. This test
        // documents the behaviour so that a future fix is a deliberate change.
        final feb = nextOccurrence(DateTime(2027, 1, 31), Recurrence.monthly)!;
        final mar = nextOccurrence(feb, Recurrence.monthly)!;
        expect(mar, DateTime(2027, 3, 28));
      });
    });

    group('calendar days, not 24 hour blocks', () {
      test('keeps the wall-clock time across a long run of days', () {
        // Adding Duration(days: 1) adds 24 hours, which drifts an hour across a
        // daylight-saving change in a zone that has one. Calendar arithmetic
        // does not. This machine's zone may have no DST, so the check is that
        // the hour and minute are identical after many steps.
        var date = DateTime(2026, 1, 1, 9, 15);
        for (var i = 0; i < 400; i++) {
          date = nextOccurrence(date, Recurrence.daily)!;
          expect((date.hour, date.minute), (9, 15), reason: 'drifted after ${i + 1} days');
        }
      });

      test('weekly lands on the same weekday, a week on', () {
        final next = nextOccurrence(DateTime(2026, 10, 5, 9), Recurrence.weekly)!;
        expect(next.weekday, DateTime.monday);
        expect(next.day, 12);
      });

      test('weekdays skips a weekend that crosses a month boundary', () {
        // Friday 30 October 2026 -> Monday 2 November.
        final friday = DateTime(2026, 10, 30, 9);
        expect(friday.weekday, DateTime.friday);
        expect(nextOccurrence(friday, Recurrence.weekdays), DateTime(2026, 11, 2, 9));
      });
    });
  });
}
