import 'package:flutter/foundation.dart';

/// The kinds of holiday the app can show, and which the user can filter by.
enum HolidayCategory { public, bank, mercantile, national, religious, observance }

extension HolidayCategoryX on HolidayCategory {
  /// The stable string stored in preferences and on holiday documents.
  String get id => name;

  String get label => switch (this) {
        HolidayCategory.public => 'Public holiday',
        HolidayCategory.bank => 'Bank holiday',
        HolidayCategory.mercantile => 'Mercantile holiday',
        HolidayCategory.national => 'National holiday',
        HolidayCategory.religious => 'Religious holiday',
        HolidayCategory.observance => 'Observance',
      };

  String get pluralLabel => switch (this) {
        HolidayCategory.public => 'Public holidays',
        HolidayCategory.bank => 'Bank holidays',
        HolidayCategory.mercantile => 'Mercantile holidays',
        HolidayCategory.national => 'National holidays',
        HolidayCategory.religious => 'Religious holidays',
        HolidayCategory.observance => 'Observances',
      };

  static HolidayCategory fromId(Object? raw) =>
      HolidayCategory.values.where((c) => c.name == raw).firstOrNull ??
      HolidayCategory.public;
}

/// Where a holiday came from. User-added entries are never overwritten by the
/// built-in table, and the UI only offers Delete on the ones the user owns.
enum HolidaySource { builtIn, user }

/// One holiday on one date in one country.
///
/// This is calendar metadata, deliberately not a [Task]: it has no board, no
/// list, no position and no drag behaviour, so holiday data can never collide
/// with the task drag-and-drop system.
@immutable
class HolidayEntry {
  const HolidayEntry({
    required this.id,
    required this.countryCode,
    required this.date,
    required this.name,
    this.category = HolidayCategory.public,
    this.description = '',
    this.source = HolidaySource.builtIn,
  });

  final String id;

  /// ISO 3166-1 alpha-2, e.g. `LK`, `US`.
  final String countryCode;
  final DateTime date;
  final String name;
  final HolidayCategory category;
  final String description;
  final HolidaySource source;

  bool get isPublic =>
      category == HolidayCategory.public ||
      category == HolidayCategory.bank ||
      category == HolidayCategory.national;

  bool isOn(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  Map<String, dynamic> toJson() => {
        'countryCode': countryCode,
        'date': date.toIso8601String(),
        'name': name,
        'category': category.id,
        'description': description,
        'isPublic': isPublic,
        'source': source.name,
      };
}

/// A country the user can turn on in Holiday settings.
@immutable
class HolidayCountry {
  const HolidayCountry({required this.code, required this.name, required this.flag});

  final String code;
  final String name;

  /// Regional-indicator emoji, used as the marker on the calendar.
  final String flag;
}

/// The four kinds of holiday the settings screen offers.
///
/// Documents and preferences keep the finer [HolidayCategory] ids, so nothing
/// already stored changes meaning. "Other" simply stands for the three that
/// are not a public, bank or mercantile holiday.
enum HolidayGroup { public, bank, mercantile, other }

extension HolidayGroupX on HolidayGroup {
  String get label => switch (this) {
        HolidayGroup.public => 'Public holidays',
        HolidayGroup.bank => 'Bank holidays',
        HolidayGroup.mercantile => 'Mercantile holidays',
        HolidayGroup.other => 'Other (national, religious, observances)',
      };

  /// The stored category ids this group switches on and off together.
  List<String> get categoryIds => switch (this) {
        HolidayGroup.public => [HolidayCategory.public.id],
        HolidayGroup.bank => [HolidayCategory.bank.id],
        HolidayGroup.mercantile => [HolidayCategory.mercantile.id],
        HolidayGroup.other => [
            HolidayCategory.national.id,
            HolidayCategory.religious.id,
            HolidayCategory.observance.id,
          ],
      };

  /// True when any of the group's categories is selected.
  bool isOn(Iterable<String> selected) => categoryIds.any(selected.contains);

  /// [selected] with this group switched on or off.
  Set<String> toggled(Iterable<String> selected, {required bool on}) {
    final next = {...selected};
    if (on) {
      next.addAll(categoryIds);
    } else {
      next.removeAll(categoryIds);
    }
    return next;
  }
}
