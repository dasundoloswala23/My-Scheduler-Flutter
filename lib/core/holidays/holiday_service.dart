import '../../models/collections.dart';
import '../../models/holiday_entry.dart';
import '../preferences/app_preferences.dart';
import 'holiday_data.dart';

/// Turns the user's holiday preferences plus their own entries into the list
/// the calendar draws.
///
/// The UI never reaches for [HolidayData] directly — it asks this service —
/// which is what keeps holiday dates out of widgets and makes a new country a
/// data change rather than a UI change.
class HolidayService {
  const HolidayService({required this.preferences, this.userHolidays = const []});

  final AppPreferences preferences;

  /// Holidays the user added by hand. These always show, whatever countries
  /// are selected, because the user asked for them explicitly.
  final List<Holiday> userHolidays;

  Set<String> get _enabledCategories => preferences.holidayCategories.toSet();

  bool _categoryEnabled(HolidayCategory category) => _enabledCategories.contains(category.id);

  /// Every holiday to show in [years], already filtered by the selected
  /// countries and categories and sorted by date.
  List<HolidayEntry> entriesForYears(Iterable<int> years) {
    final builtIn = HolidayData.forYears(preferences.holidayCountries, years)
        .where((h) => _categoryEnabled(h.category));

    final yearSet = years.toSet();
    final mine = userHolidays.where((h) => yearSet.contains(h.date.year)).map(_fromUser);

    final all = [...builtIn, ...mine]..sort((a, b) => a.date.compareTo(b.date));
    return all;
  }

  /// Holidays falling on [day].
  List<HolidayEntry> entriesOn(DateTime day) =>
      entriesForYears({day.year}).where((h) => h.isOn(day)).toList();

  /// Holidays falling on any of [days], keyed by `yyyy-mm-dd`.
  ///
  /// Views that draw a week or a month use this so they generate the year's
  /// table once instead of once per cell.
  Map<String, List<HolidayEntry>> entriesByDay(Iterable<DateTime> days) {
    final years = {for (final d in days) d.year};
    final wanted = {for (final d in days) _key(d)};
    final result = <String, List<HolidayEntry>>{};
    for (final entry in entriesForYears(years)) {
      final key = _key(entry.date);
      if (!wanted.contains(key)) continue;
      (result[key] ??= []).add(entry);
    }
    return result;
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  HolidayEntry _fromUser(Holiday h) => HolidayEntry(
        id: h.id,
        countryCode: h.countryCode,
        date: DateTime(h.date.year, h.date.month, h.date.day),
        name: h.name,
        category: HolidayCategoryX.fromId(h.category),
        source: HolidaySource.user,
      );
}

/// Convenience for views that already hold a day→holidays map.
extension HolidayDayLookup on Map<String, List<HolidayEntry>> {
  List<HolidayEntry> on(DateTime day) =>
      this['${day.year}-${day.month}-${day.day}'] ?? const [];
}
