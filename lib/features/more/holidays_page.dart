import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/holidays/holiday_data.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/holiday_entry.dart';
import 'more_page.dart';

/// Holiday settings: which countries' calendars to show, which kinds of
/// holiday to include, and any the user adds themselves.
///
/// No date is written here. The countries and categories are preferences on
/// the user document, and the dates come from `HolidayData` through
/// `HolidayService`, so turning a country off removes its holidays from the
/// calendar immediately and nothing has to be cleaned up.
class HolidaysPage extends ConsumerWidget {
  const HolidaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final save = ref.watch(savePreferencesProvider);
    final palette = context.palette;

    final selectedCountries = prefs.holidayCountries.toSet();
    final selectedCategories = prefs.holidayCategories.toSet();

    // A preview of what the calendar will actually show this year, so the
    // effect of a tick is visible without leaving the screen.
    final preview = ref.watch(holidayServiceProvider).entriesForYears([DateTime.now().year]);

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Holidays',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add your own holiday',
        child: const Icon(Icons.add),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _Label('Countries', palette: palette),
          Card(
            child: Column(
              children: [
                for (final country in HolidayData.countries)
                  CheckboxListTile(
                    value: selectedCountries.contains(country.code),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        Text(country.flag, style: const TextStyle(fontSize: 17)),
                        const SizedBox(width: 10),
                        Text(country.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    onChanged: (on) {
                      final next = {...selectedCountries};
                      if (on == true) {
                        next.add(country.code);
                      } else {
                        next.remove(country.code);
                      }
                      save(prefs.copyWith(holidayCountries: next.toList()..sort()));
                    },
                  ),
              ],
            ),
          ),
          if (selectedCountries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                'No country is selected, so the calendar shows no holidays. '
                'Nothing is assumed for you.',
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
            ),
          const SizedBox(height: 18),
          _Label('Holiday types', palette: palette),
          Card(
            child: Column(
              children: [
                for (final group in HolidayGroup.values)
                  CheckboxListTile(
                    value: group.isOn(selectedCategories),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(group.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    onChanged: (on) {
                      final next = group.toggled(selectedCategories, on: on == true);
                      save(prefs.copyWith(holidayCategories: next.toList()));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Label('On your calendar this year', palette: palette),
          if (preview.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Nothing yet. Pick a country above, or add a holiday of your own.',
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final entry in preview)
                    _HolidayRow(
                      entry: entry,
                      onDelete: entry.source == HolidaySource.user
                          ? () => ref.read(repoProvider).deleteHoliday(entry.id)
                          : null,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Lunar holidays such as Poya days, Eid and Diwali move each year '
              'and are not in the built-in tables. Add those with the + button.',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, 'Holiday name');
    if (name == null || !context.mounted) return;

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;

    final category = await showModalBottomSheet<HolidayCategory>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('What kind of holiday?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final c in HolidayCategory.values)
              ListTile(
                title: Text(c.label),
                onTap: () => Navigator.pop(sheetContext, c),
              ),
          ],
        ),
      ),
    );
    if (category == null) return;

    await ref.read(repoProvider).addHoliday(Holiday(
          id: 'new',
          name: name,
          date: date,
          category: category.id,
        ));
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.palette});
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: palette.textSecondary,
          ),
        ),
      );
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({required this.entry, this.onDelete});

  final HolidayEntry entry;

  /// Only the user's own holidays can be deleted; a built-in one is turned off
  /// by unticking its country or category instead.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final flag = HolidayData.country(entry.countryCode)?.flag;

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: palette.tint(palette.warning),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('dd').format(entry.date),
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, color: palette.warning)),
            Text(DateFormat('MMM').format(entry.date).toUpperCase(),
                style: TextStyle(fontSize: 9, color: palette.textSecondary)),
          ],
        ),
      ),
      title: Text(
        flag == null || flag.isEmpty ? entry.name : '$flag  ${entry.name}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(entry.category.label,
          style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
    );
  }
}
