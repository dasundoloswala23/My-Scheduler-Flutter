import '../../models/holiday_entry.dart';

/// Built-in holiday tables.
///
/// The data lives here, away from any widget, so the calendar never hard-codes
/// a date and a new country is a new entry in [countries] plus a new branch in
/// [_forCountry]. Dates are computed per year rather than listed, so the table
/// does not expire.
///
/// Lunar holidays (Sri Lankan Poya days, Eid, Diwali) are not computable from a
/// civil-calendar rule and are deliberately absent; the user can add those by
/// hand and they are kept as [HolidaySource.user] entries.
class HolidayData {
  const HolidayData._();

  static const countries = <HolidayCountry>[
    HolidayCountry(code: 'LK', name: 'Sri Lanka', flag: '\u{1F1F1}\u{1F1F0}'),
    HolidayCountry(code: 'US', name: 'United States', flag: '\u{1F1FA}\u{1F1F8}'),
    HolidayCountry(code: 'GB', name: 'United Kingdom', flag: '\u{1F1EC}\u{1F1E7}'),
    HolidayCountry(code: 'IN', name: 'India', flag: '\u{1F1EE}\u{1F1F3}'),
    HolidayCountry(code: 'AU', name: 'Australia', flag: '\u{1F1E6}\u{1F1FA}'),
    HolidayCountry(code: 'CA', name: 'Canada', flag: '\u{1F1E8}\u{1F1E6}'),
  ];

  static HolidayCountry? country(String code) =>
      countries.where((c) => c.code == code).firstOrNull;

  /// Every built-in holiday for [countryCodes] across [years].
  static List<HolidayEntry> forYears(Iterable<String> countryCodes, Iterable<int> years) => [
        for (final code in countryCodes)
          for (final year in years) ..._forCountry(code, year),
      ];

  static List<HolidayEntry> _forCountry(String code, int year) => switch (code) {
        'LK' => _sriLanka(year),
        'US' => _unitedStates(year),
        'GB' => _unitedKingdom(year),
        'IN' => _india(year),
        'AU' => _australia(year),
        'CA' => _canada(year),
        _ => const [],
      };

  // -------------------------------------------------------------- countries

  static List<HolidayEntry> _sriLanka(int year) {
    final easter = _easter(year);
    return [
      _e('LK', DateTime(year, 1, 15), 'Tamil Thai Pongal Day', HolidayCategory.public),
      _e('LK', DateTime(year, 2, 4), 'Independence Day', HolidayCategory.national),
      _e('LK', easter.subtract(const Duration(days: 2)), 'Good Friday',
          HolidayCategory.religious),
      _e('LK', DateTime(year, 4, 13), 'Day before Sinhala & Tamil New Year',
          HolidayCategory.public),
      _e('LK', DateTime(year, 4, 14), 'Sinhala & Tamil New Year', HolidayCategory.public),
      _e('LK', DateTime(year, 5, 1), 'May Day', HolidayCategory.mercantile),
      _e('LK', DateTime(year, 10, 5), "World Teachers' Day", HolidayCategory.observance),
      _e('LK', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.public),
    ];
  }

  static List<HolidayEntry> _unitedStates(int year) => [
        _e('US', DateTime(year, 1, 1), "New Year's Day", HolidayCategory.public),
        _e('US', _nthWeekday(year, 1, DateTime.monday, 3), 'Martin Luther King Jr. Day',
            HolidayCategory.public),
        _e('US', _nthWeekday(year, 2, DateTime.monday, 3), "Presidents' Day",
            HolidayCategory.public),
        _e('US', _lastWeekday(year, 5, DateTime.monday), 'Memorial Day', HolidayCategory.public),
        _e('US', DateTime(year, 6, 19), 'Juneteenth', HolidayCategory.public),
        _e('US', DateTime(year, 7, 4), 'Independence Day', HolidayCategory.national),
        _e('US', _nthWeekday(year, 9, DateTime.monday, 1), 'Labor Day', HolidayCategory.public),
        _e('US', _nthWeekday(year, 10, DateTime.monday, 2), 'Columbus Day',
            HolidayCategory.observance),
        _e('US', DateTime(year, 11, 11), 'Veterans Day', HolidayCategory.public),
        _e('US', _nthWeekday(year, 11, DateTime.thursday, 4), 'Thanksgiving',
            HolidayCategory.public),
        _e('US', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.public),
      ];

  static List<HolidayEntry> _unitedKingdom(int year) {
    final easter = _easter(year);
    return [
      _e('GB', DateTime(year, 1, 1), "New Year's Day", HolidayCategory.bank),
      _e('GB', easter.subtract(const Duration(days: 2)), 'Good Friday', HolidayCategory.bank),
      _e('GB', easter.add(const Duration(days: 1)), 'Easter Monday', HolidayCategory.bank),
      _e('GB', _nthWeekday(year, 5, DateTime.monday, 1), 'Early May bank holiday',
          HolidayCategory.bank),
      _e('GB', _lastWeekday(year, 5, DateTime.monday), 'Spring bank holiday',
          HolidayCategory.bank),
      _e('GB', _lastWeekday(year, 8, DateTime.monday), 'Summer bank holiday',
          HolidayCategory.bank),
      _e('GB', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.bank),
      _e('GB', DateTime(year, 12, 26), 'Boxing Day', HolidayCategory.bank),
    ];
  }

  static List<HolidayEntry> _india(int year) => [
        _e('IN', DateTime(year, 1, 26), 'Republic Day', HolidayCategory.national),
        _e('IN', DateTime(year, 8, 15), 'Independence Day', HolidayCategory.national),
        _e('IN', DateTime(year, 10, 2), 'Gandhi Jayanti', HolidayCategory.national),
        _e('IN', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.public),
      ];

  static List<HolidayEntry> _australia(int year) {
    final easter = _easter(year);
    return [
      _e('AU', DateTime(year, 1, 1), "New Year's Day", HolidayCategory.public),
      _e('AU', DateTime(year, 1, 26), 'Australia Day', HolidayCategory.national),
      _e('AU', easter.subtract(const Duration(days: 2)), 'Good Friday', HolidayCategory.public),
      _e('AU', easter.add(const Duration(days: 1)), 'Easter Monday', HolidayCategory.public),
      _e('AU', DateTime(year, 4, 25), 'Anzac Day', HolidayCategory.national),
      _e('AU', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.public),
      _e('AU', DateTime(year, 12, 26), 'Boxing Day', HolidayCategory.public),
    ];
  }

  static List<HolidayEntry> _canada(int year) {
    final easter = _easter(year);
    return [
      _e('CA', DateTime(year, 1, 1), "New Year's Day", HolidayCategory.public),
      _e('CA', easter.subtract(const Duration(days: 2)), 'Good Friday', HolidayCategory.public),
      _e('CA', _mondayBefore(DateTime(year, 5, 25)), 'Victoria Day', HolidayCategory.public),
      _e('CA', DateTime(year, 7, 1), 'Canada Day', HolidayCategory.national),
      _e('CA', _nthWeekday(year, 9, DateTime.monday, 1), 'Labour Day', HolidayCategory.public),
      _e('CA', _nthWeekday(year, 10, DateTime.monday, 2), 'Thanksgiving',
          HolidayCategory.public),
      _e('CA', DateTime(year, 11, 11), 'Remembrance Day', HolidayCategory.observance),
      _e('CA', DateTime(year, 12, 25), 'Christmas Day', HolidayCategory.public),
      _e('CA', DateTime(year, 12, 26), 'Boxing Day', HolidayCategory.bank),
    ];
  }

  // ---------------------------------------------------------------- helpers

  static HolidayEntry _e(
    String country,
    DateTime date,
    String name,
    HolidayCategory category,
  ) =>
      HolidayEntry(
        // Stable and derivable, so the same holiday keeps its identity between
        // runs without anything being written to the database.
        id: 'builtin:$country:${date.year}-${date.month}-${date.day}:$name',
        countryCode: country,
        date: DateTime(date.year, date.month, date.day),
        name: name,
        category: category,
      );

  /// The [n]th [weekday] of [month], 1-based.
  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    final first = DateTime(year, month, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime(year, month, 1 + offset + (n - 1) * 7);
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    final last = DateTime(year, month + 1, 0);
    final offset = (last.weekday - weekday + 7) % 7;
    return DateTime(year, month, last.day - offset);
  }

  /// The Monday strictly before [date]. Victoria Day is "the Monday preceding
  /// May 25", so a May 25 that is itself a Monday steps back a full week.
  static DateTime _mondayBefore(DateTime date) {
    final back = (date.weekday - DateTime.monday + 7) % 7;
    return date.subtract(Duration(days: back == 0 ? 7 : back));
  }

  /// Gregorian Easter Sunday (Anonymous Gregorian / Meeus algorithm).
  static DateTime _easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}
