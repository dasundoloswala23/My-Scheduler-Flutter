import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import 'more_page.dart';

/// Screenshot 11: holidays. Starts empty, with a one-tap import of the Sri
/// Lanka public holidays so the calendar has something to show.
class HolidaysPage extends ConsumerWidget {
  const HolidaysPage({super.key});

  /// Fixed-date Sri Lankan public holidays. Poya days move each year, so only
  /// the fixed ones are seeded; the rest can be added by hand.
  static const _sriLankaFixed = <(int, int, String)>[
    (1, 15, 'Tamil Thai Pongal Day'),
    (2, 4, 'Independence Day'),
    (5, 1, 'May Day'),
    (10, 5, "World Teachers' Day"),
    (12, 25, 'Christmas Day'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidays = ref.watch(holidaysProvider).value ?? const <Holiday>[];

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Holidays',
      actions: [
        if (holidays.isNotEmpty)
          IconButton(
            tooltip: 'Import Sri Lanka holidays',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _seed(ref),
          ),
      ],
      floatingActionButton: holidays.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _add(context, ref),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
      child: holidays.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: EmptyState(
                    icon: Icons.celebration_outlined,
                    title: 'Your holidays live here',
                    actionLabel: 'Add Holiday',
                    onAction: () => _add(context, ref),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: TextButton.icon(
                    onPressed: () => _seed(ref),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Import Sri Lanka holidays'),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                for (final h in holidays)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(DateFormat('dd').format(h.date),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(DateFormat('MMM').format(h.date).toUpperCase(),
                                style: const TextStyle(fontSize: 9, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(h.region, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => ref.read(repoProvider).deleteHoliday(h.id),
                      ),
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
    if (date == null) return;
    await ref.read(repoProvider).addHoliday(Holiday(id: 'new', name: name, date: date));
  }

  Future<void> _seed(WidgetRef ref) async {
    final repo = ref.read(repoProvider);
    final existing = ref.read(holidaysProvider).value ?? const <Holiday>[];
    final year = DateTime.now().year;
    for (final (month, day, name) in _sriLankaFixed) {
      final date = DateTime(year, month, day);
      final already = existing.any((h) =>
          h.name == name && h.date.year == date.year && h.date.month == date.month && h.date.day == date.day);
      if (already) continue;
      await repo.addHoliday(Holiday(id: 'new', name: name, date: date));
    }
  }
}
