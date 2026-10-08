import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/holidays/holiday_data.dart';
import 'package:myschedule/core/holidays/holiday_service.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/holiday_entry.dart';

/// Finds one holiday by name in a list, or fails the test saying so.
HolidayEntry _named(List<HolidayEntry> entries, String name) {
  final match = entries.where((e) => e.name == name);
  expect(match, isNotEmpty, reason: 'expected a holiday called "$name"');
  return match.first;
}

void main() {
  group('HolidayData computes dates per year', () {
    test('fixed-date holidays land on their date', () {
      final lk = HolidayData.forYears(['LK'], [2026]);
      expect(_named(lk, 'Independence Day').date, DateTime(2026, 2, 4));
      expect(_named(lk, 'May Day').date, DateTime(2026, 5, 1));
    });

    test('nth-weekday holidays move with the year', () {
      // US Thanksgiving is the fourth Thursday of November.
      for (final (year, expected) in [
        (2024, DateTime(2024, 11, 28)),
        (2025, DateTime(2025, 11, 27)),
        (2026, DateTime(2026, 11, 26)),
      ]) {
        final us = HolidayData.forYears(['US'], [year]);
        expect(_named(us, 'Thanksgiving').date, expected);
      }
    });

    test('last-weekday holidays land in the right week', () {
      // US Memorial Day is the last Monday of May.
      expect(_named(HolidayData.forYears(['US'], [2026]), 'Memorial Day').date,
          DateTime(2026, 5, 25));
      expect(_named(HolidayData.forYears(['US'], [2027]), 'Memorial Day').date,
          DateTime(2027, 5, 31));
    });

    test('Easter-derived holidays follow Easter', () {
      // Easter Sunday 2026 is 5 April, so Good Friday is 3 April and Easter
      // Monday is 6 April.
      final gb = HolidayData.forYears(['GB'], [2026]);
      expect(_named(gb, 'Good Friday').date, DateTime(2026, 4, 3));
      expect(_named(gb, 'Easter Monday').date, DateTime(2026, 4, 6));
    });

    test('Victoria Day is the Monday strictly before 25 May', () {
      // 25 May 2026 is itself a Monday, the case a naive rule gets wrong.
      expect(DateTime(2026, 5, 25).weekday, DateTime.monday);
      expect(_named(HolidayData.forYears(['CA'], [2026]), 'Victoria Day').date,
          DateTime(2026, 5, 18));
    });

    test('an unknown country contributes nothing rather than throwing', () {
      expect(HolidayData.forYears(['ZZ'], [2026]), isEmpty);
    });

    test('ids are stable across calls', () {
      final first = HolidayData.forYears(['LK'], [2026]).map((e) => e.id).toList();
      final second = HolidayData.forYears(['LK'], [2026]).map((e) => e.id).toList();
      expect(first, second);
    });
  });

  group('HolidayService filtering', () {
    const allCategories = ['public', 'bank', 'mercantile', 'national', 'religious', 'observance'];

    test('no selected country means no holidays', () {
      const service = HolidayService(
        preferences: AppPreferences(holidayCountries: [], holidayCategories: allCategories),
      );
      expect(service.entriesForYears([2026]), isEmpty);
    });

    test('selecting two countries shows both', () {
      const service = HolidayService(
        preferences:
            AppPreferences(holidayCountries: ['LK', 'US'], holidayCategories: allCategories),
      );
      final codes = service.entriesForYears([2026]).map((e) => e.countryCode).toSet();
      expect(codes, {'LK', 'US'});
    });

    test('unticking a country removes only its holidays', () {
      const service = HolidayService(
        preferences: AppPreferences(holidayCountries: ['LK'], holidayCategories: allCategories),
      );
      final codes = service.entriesForYears([2026]).map((e) => e.countryCode).toSet();
      expect(codes, {'LK'});
    });

    test('category filter hides the categories that are off', () {
      const service = HolidayService(
        preferences: AppPreferences(holidayCountries: ['LK'], holidayCategories: ['public']),
      );
      final categories = service.entriesForYears([2026]).map((e) => e.category).toSet();
      expect(categories, {HolidayCategory.public});
      // The observance is filtered out rather than silently recategorised.
      expect(service.entriesForYears([2026]).map((e) => e.name),
          isNot(contains("World Teachers' Day")));
    });

    test('a user holiday shows whatever countries are selected', () {
      final service = HolidayService(
        preferences: const AppPreferences(holidayCountries: [], holidayCategories: ['public']),
        userHolidays: [
          Holiday(id: 'mine', name: 'Poya', date: DateTime(2026, 3, 3), category: 'public'),
        ],
      );
      final entries = service.entriesForYears([2026]);
      expect(entries.map((e) => e.name), ['Poya']);
      expect(entries.single.source, HolidaySource.user);
    });

    test('entriesOn returns only that day', () {
      const service = HolidayService(
        preferences: AppPreferences(holidayCountries: ['LK'], holidayCategories: allCategories),
      );
      final onIndependenceDay = service.entriesOn(DateTime(2026, 2, 4));
      expect(onIndependenceDay.map((e) => e.name), contains('Independence Day'));
      expect(service.entriesOn(DateTime(2026, 2, 5)), isEmpty);
    });

    test('entriesByDay keys every requested day it has a holiday for', () {
      const service = HolidayService(
        preferences: AppPreferences(holidayCountries: ['LK'], holidayCategories: allCategories),
      );
      final days = [
        DateTime(2026, 2, 3),
        DateTime(2026, 2, 4),
        DateTime(2026, 2, 5),
      ];
      final byDay = service.entriesByDay(days);
      expect(byDay.on(DateTime(2026, 2, 4)).map((e) => e.name), contains('Independence Day'));
      expect(byDay.on(DateTime(2026, 2, 3)), isEmpty);
      expect(byDay.on(DateTime(2026, 2, 5)), isEmpty);
    });

    test('results are sorted by date', () {
      const service = HolidayService(
        preferences:
            AppPreferences(holidayCountries: ['LK', 'US'], holidayCategories: allCategories),
      );
      final dates = service.entriesForYears([2026]).map((e) => e.date).toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });
  });
  group('holiday groups: Public / Bank / Mercantile / Other', () {
    test('Other stands for national, religious and observance together', () {
      expect(HolidayGroup.other.categoryIds, ['national', 'religious', 'observance']);
      expect(HolidayGroup.values.map((g) => g.label.split(' ').first),
          ['Public', 'Bank', 'Mercantile', 'Other']);
    });

    test('switching a group on and off changes only its own categories', () {
      final on = HolidayGroup.other.toggled(['public'], on: true);
      expect(on, {'public', 'national', 'religious', 'observance'});
      expect(HolidayGroup.other.toggled(on, on: false), {'public'});
      expect(HolidayGroup.public.isOn({'bank'}), isFalse);
      expect(HolidayGroup.other.isOn({'religious'}), isTrue);
    });

    test('Sri Lanka with Mercantile on and Public off shows only mercantile holidays', () {
      var cats = <String>{'public', 'bank', 'mercantile'};
      cats = HolidayGroup.public.toggled(cats, on: false);
      cats = HolidayGroup.bank.toggled(cats, on: false);
      final prefs = AppPreferences(holidayCountries: const ['LK'], holidayCategories: cats.toList());

      // The choice survives a save and a reload.
      final restored = AppPreferences.fromJson(prefs.toJson());
      final entries = HolidayService(preferences: restored).entriesForYears([2026]);

      expect(entries, isNotEmpty);
      expect(entries.map((e) => e.category).toSet(), {HolidayCategory.mercantile});
      expect(entries.map((e) => e.name), contains('May Day'));
      expect(entries.map((e) => e.name), isNot(contains('Christmas Day')));
    });

    test('turning Other on brings back national, religious and observance holidays', () {
      final cats = HolidayGroup.other.toggled({'mercantile'}, on: true);
      final prefs = AppPreferences(holidayCountries: const ['LK'], holidayCategories: cats.toList());
      final names = HolidayService(preferences: prefs).entriesForYears([2026]).map((e) => e.name);
      expect(names, contains('Independence Day'));
      expect(names, contains("World Teachers' Day"));
    });

    test('several countries each keep their own holidays under the same groups', () {
      const prefs = AppPreferences(
          holidayCountries: ['LK', 'US'], holidayCategories: ['public']);
      final names = HolidayService(preferences: prefs).entriesForYears([2026]).map((e) => e.name);
      expect(names, contains('Juneteenth'));
      expect(names, contains('Christmas Day'));
    });
  });
}
