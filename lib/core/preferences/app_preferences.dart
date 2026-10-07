import 'package:flutter/material.dart';

import '../../models/task.dart';

/// Which calendar surface the Calendar tab opens on.
enum CalendarViewPref { day, threeDay, week, month, agenda }

/// How tightly the calendar and board draw themselves.
///
/// This is a readability choice, not decoration: compact fits more of the day
/// on a laptop screen, detailed gives each event room for its time and
/// category.
enum CalendarDensity { compact, comfortable, detailed }

extension CalendarDensityX on CalendarDensity {
  String get label => switch (this) {
        CalendarDensity.compact => 'Compact',
        CalendarDensity.comfortable => 'Comfortable',
        CalendarDensity.detailed => 'Detailed',
      };

  /// Height of one hour in the time grid.
  double get hourHeight => switch (this) {
        CalendarDensity.compact => 48,
        CalendarDensity.comfortable => 64,
        CalendarDensity.detailed => 88,
      };

  /// Whether an event shows its time range and category under the title.
  bool get showEventDetail => this != CalendarDensity.compact;
}

/// Every user-facing preference that is not a notification setting.
///
/// Stored as one map on the user document so it syncs across devices with the
/// account, which is what section 17 of the brief asks for. Unknown values
/// decode back to the default rather than throwing, so a document written by a
/// newer build still loads in an older one.
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.calendarDefaultView = CalendarViewPref.week,
    this.calendarScrollHour = 9,
    this.weekStartsOnMonday = true,
    this.showWeekends = true,
    this.calendarDensity = CalendarDensity.comfortable,
    this.showSubtasksOnCards = true,
    this.subtaskPreviewCount = 4,
    this.defaultPriority = TaskPriority.none,
    this.defaultCategoryId,
    this.holidayCountries = const [],
    this.holidayCategories = const ['public', 'bank', 'mercantile'],
  });

  // Appearance
  final ThemeMode themeMode;

  // Calendar
  final CalendarViewPref calendarDefaultView;

  /// Hour of the day the time grid scrolls to when it opens. Earlier hours
  /// stay reachable by scrolling up; this only sets the starting viewport.
  final int calendarScrollHour;
  final bool weekStartsOnMonday;
  final bool showWeekends;
  final CalendarDensity calendarDensity;

  // Tasks
  final bool showSubtasksOnCards;

  /// How many subtasks a card shows before collapsing the rest behind
  /// "+N more", so one long checklist cannot swallow the board.
  final int subtaskPreviewCount;
  final TaskPriority defaultPriority;
  final String? defaultCategoryId;

  // Holidays
  /// ISO 3166-1 alpha-2 codes. Empty means the user has not chosen a country
  /// yet, and no holidays are shown — nothing is assumed on their behalf.
  final List<String> holidayCountries;

  /// Holiday category ids (see [HolidayCategory]) the calendar should show.
  final List<String> holidayCategories;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    CalendarViewPref? calendarDefaultView,
    int? calendarScrollHour,
    bool? weekStartsOnMonday,
    bool? showWeekends,
    CalendarDensity? calendarDensity,
    bool? showSubtasksOnCards,
    int? subtaskPreviewCount,
    TaskPriority? defaultPriority,
    Object? defaultCategoryId = _sentinel,
    List<String>? holidayCountries,
    List<String>? holidayCategories,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      calendarDefaultView: calendarDefaultView ?? this.calendarDefaultView,
      calendarScrollHour: calendarScrollHour ?? this.calendarScrollHour,
      weekStartsOnMonday: weekStartsOnMonday ?? this.weekStartsOnMonday,
      showWeekends: showWeekends ?? this.showWeekends,
      calendarDensity: calendarDensity ?? this.calendarDensity,
      showSubtasksOnCards: showSubtasksOnCards ?? this.showSubtasksOnCards,
      subtaskPreviewCount: subtaskPreviewCount ?? this.subtaskPreviewCount,
      defaultPriority: defaultPriority ?? this.defaultPriority,
      defaultCategoryId:
          defaultCategoryId == _sentinel ? this.defaultCategoryId : defaultCategoryId as String?,
      holidayCountries: holidayCountries ?? this.holidayCountries,
      holidayCategories: holidayCategories ?? this.holidayCategories,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'calendarDefaultView': calendarDefaultView.name,
        'calendarScrollHour': calendarScrollHour,
        'weekStartsOnMonday': weekStartsOnMonday,
        'showWeekends': showWeekends,
        'calendarDensity': calendarDensity.name,
        'showSubtasksOnCards': showSubtasksOnCards,
        'subtaskPreviewCount': subtaskPreviewCount,
        'defaultPriority': defaultPriority.name,
        'defaultCategoryId': defaultCategoryId,
        'holidayCountries': holidayCountries,
        'holidayCategories': holidayCategories,
      };

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    const fallback = AppPreferences();
    return AppPreferences(
      themeMode: _enumByName(ThemeMode.values, json['themeMode'], fallback.themeMode),
      calendarDefaultView: _enumByName(
          CalendarViewPref.values, json['calendarDefaultView'], fallback.calendarDefaultView),
      calendarScrollHour:
          ((json['calendarScrollHour'] as num?)?.toInt() ?? fallback.calendarScrollHour)
              .clamp(0, 23),
      weekStartsOnMonday: (json['weekStartsOnMonday'] as bool?) ?? fallback.weekStartsOnMonday,
      showWeekends: (json['showWeekends'] as bool?) ?? fallback.showWeekends,
      calendarDensity:
          _enumByName(CalendarDensity.values, json['calendarDensity'], fallback.calendarDensity),
      showSubtasksOnCards:
          (json['showSubtasksOnCards'] as bool?) ?? fallback.showSubtasksOnCards,
      subtaskPreviewCount:
          ((json['subtaskPreviewCount'] as num?)?.toInt() ?? fallback.subtaskPreviewCount)
              .clamp(1, 20),
      defaultPriority:
          _enumByName(TaskPriority.values, json['defaultPriority'], fallback.defaultPriority),
      defaultCategoryId: json['defaultCategoryId'] as String?,
      holidayCountries: _stringList(json['holidayCountries']) ?? fallback.holidayCountries,
      holidayCategories: _stringList(json['holidayCategories']) ?? fallback.holidayCategories,
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
      values.where((v) => v.name == raw).firstOrNull ?? fallback;

  static List<String>? _stringList(Object? raw) =>
      raw is List ? raw.whereType<String>().toList() : null;
}

const _sentinel = Object();
