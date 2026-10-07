import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/position.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import 'more_page.dart';

/// Screenshot 6: areas of life, with the active task count per category.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  static const _palette = [
    0xFF6C5CE7, 0xFF3B82F6, 0xFF30A46C, 0xFFE8A33D,
    0xFFE5484D, 0xFFEC4899, 0xFF14B8A6, 0xFF6B7280,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final counts = activeTaskCountByCategory(tasks);

    return SubPage(
      eyebrow: 'Areas of life',
      title: 'Categories',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref, categories),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      child: categories.isEmpty
          ? EmptyState(
              icon: Icons.label_outline,
              title: 'Your categories live here',
              actionLabel: 'Add Category',
              onAction: () => _add(context, ref, categories),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                for (final c in categories)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c.colorValue).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.label, size: 18, color: Color(c.colorValue)),
                      ),
                      title: Text(c.name,
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(c.colorValue))),
                      subtitle: Text('${counts[c.id] ?? 0} active tasks',
                          style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          final repo = ref.read(repoProvider);
                          if (v == 'rename') {
                            final name = await promptText(context, 'Category name', initial: c.name);
                            if (name != null) {
                              await repo.saveCategory(Category(
                                id: c.id,
                                name: name,
                                colorValue: c.colorValue,
                                position: c.position,
                              ));
                            }
                          } else if (v == 'color') {
                            final next = _palette[(_palette.indexOf(c.colorValue) + 1) % _palette.length];
                            await repo.saveCategory(Category(
                              id: c.id,
                              name: c.name,
                              colorValue: next,
                              position: c.position,
                            ));
                          } else if (v == 'delete') {
                            await repo.deleteCategory(c.id);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'color', child: Text('Next colour')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<Category> existing) async {
    final name = await promptText(context, 'New category');
    if (name == null) return;
    await ref.read(repoProvider).addCategory(Category(
          id: 'new',
          name: name,
          colorValue: _palette[existing.length % _palette.length],
          position: Position.between(existing.lastOrNull?.position, null),
        ));
  }
}
