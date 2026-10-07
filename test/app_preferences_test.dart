import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/link_preview.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/models/task.dart';

void main() {
  group('AppPreferences defaults', () {
    test('match the defaults the brief asks for', () {
      const prefs = AppPreferences();
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.calendarDefaultView, CalendarViewPref.week);
      expect(prefs.calendarScrollHour, 9);
      expect(prefs.showSubtasksOnCards, isTrue);
      expect(prefs.holidayCategories, ['public', 'bank', 'mercantile']);
    });

    test('no country is assumed on the user\'s behalf', () {
      expect(const AppPreferences().holidayCountries, isEmpty);
    });
  });

  group('AppPreferences serialisation', () {
    test('round-trips every field', () {
      const original = AppPreferences(
        themeMode: ThemeMode.dark,
        calendarDefaultView: CalendarViewPref.threeDay,
        calendarScrollHour: 6,
        weekStartsOnMonday: false,
        showWeekends: false,
        calendarDensity: CalendarDensity.detailed,
        showSubtasksOnCards: false,
        subtaskPreviewCount: 6,
        defaultPriority: TaskPriority.high,
        defaultCategoryId: 'cat-1',
        holidayCountries: ['LK', 'US'],
        holidayCategories: ['public'],
      );

      final restored = AppPreferences.fromJson(original.toJson());

      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.calendarDefaultView, CalendarViewPref.threeDay);
      expect(restored.calendarScrollHour, 6);
      expect(restored.weekStartsOnMonday, isFalse);
      expect(restored.showWeekends, isFalse);
      expect(restored.calendarDensity, CalendarDensity.detailed);
      expect(restored.showSubtasksOnCards, isFalse);
      expect(restored.subtaskPreviewCount, 6);
      expect(restored.defaultPriority, TaskPriority.high);
      expect(restored.defaultCategoryId, 'cat-1');
      expect(restored.holidayCountries, ['LK', 'US']);
      expect(restored.holidayCategories, ['public']);
    });

    test('an empty document decodes to the defaults', () {
      expect(AppPreferences.fromJson(const {}).calendarScrollHour, 9);
      expect(AppPreferences.fromJson(const {}).themeMode, ThemeMode.system);
    });

    test('an unknown enum value falls back instead of throwing', () {
      final prefs = AppPreferences.fromJson(const {
        'themeMode': 'sepia',
        'calendarDensity': 'enormous',
        'calendarDefaultView': 'fortnight',
      });
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.calendarDensity, CalendarDensity.comfortable);
      expect(prefs.calendarDefaultView, CalendarViewPref.week);
    });

    test('an out-of-range scroll hour is clamped to a real hour', () {
      expect(AppPreferences.fromJson(const {'calendarScrollHour': 99}).calendarScrollHour, 23);
      expect(AppPreferences.fromJson(const {'calendarScrollHour': -4}).calendarScrollHour, 0);
    });

    test('copyWith can clear the default category', () {
      const prefs = AppPreferences(defaultCategoryId: 'cat-1');
      expect(prefs.copyWith(defaultCategoryId: null).defaultCategoryId, isNull);
      // Omitting it leaves the value alone, rather than clearing it.
      expect(prefs.copyWith(calendarScrollHour: 7).defaultCategoryId, 'cat-1');
    });
  });

  group('CalendarDensity', () {
    test('compact is shorter than detailed', () {
      expect(CalendarDensity.compact.hourHeight,
          lessThan(CalendarDensity.detailed.hourHeight));
    });

    test('only compact hides the event detail line', () {
      expect(CalendarDensity.compact.showEventDetail, isFalse);
      expect(CalendarDensity.comfortable.showEventDetail, isTrue);
      expect(CalendarDensity.detailed.showEventDetail, isTrue);
    });
  });

  group('LinkPreview', () {
    test('finds a link in a description', () {
      final preview = LinkPreview.firstIn('see https://github.com/flutter/flutter for more');
      expect(preview?.domain, 'github.com');
      expect(preview?.siteName, 'GitHub');
    });

    test('derives a YouTube thumbnail from the URL alone', () {
      final watch = LinkPreview.forUrl('https://www.youtube.com/watch?v=abc123');
      expect(watch?.siteName, 'YouTube');
      expect(watch?.thumbnailUrl, 'https://img.youtube.com/vi/abc123/hqdefault.jpg');

      final short = LinkPreview.forUrl('https://youtu.be/abc123');
      expect(short?.thumbnailUrl, 'https://img.youtube.com/vi/abc123/hqdefault.jpg');
    });

    test('an unrecognised host still gives the domain to fall back on', () {
      final preview = LinkPreview.forUrl('https://www.example.co.uk/some/page?q=1');
      expect(preview?.domain, 'example.co.uk');
      expect(preview?.siteName, isNull);
      expect(preview?.hasThumbnail, isFalse);
    });

    test('trailing punctuation is not part of the URL', () {
      expect(LinkPreview.firstIn('go to https://example.com.')?.url, 'https://example.com');
    });

    test('text with no link, and unparseable input, return null', () {
      expect(LinkPreview.firstIn('no links here at all'), isNull);
      expect(LinkPreview.forUrl('http://'), isNull);
      expect(LinkPreview.forUrl('not a url'), isNull);
    });

    test('allIn returns each distinct link once, in order', () {
      final found = LinkPreview.allIn(
        'https://a.com then https://b.com then https://a.com again',
      );
      expect(found.map((l) => l.domain), ['a.com', 'b.com']);
    });
  });
}
