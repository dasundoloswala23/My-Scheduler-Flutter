import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import 'more_page.dart';

/// Screenshot 9: notes, empty until the first one is added.
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider).value ?? const <Note>[];

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Notes',
      floatingActionButton: notes.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(context, ref, null),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
      child: notes.isEmpty
          ? EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: 'Your notes live here',
              actionLabel: 'Add Note',
              onAction: () => _edit(context, ref, null),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                for (final note in notes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _edit(context, ref, note),
                      title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        note.body.isEmpty
                            ? (note.updatedAt == null
                                ? 'No content yet'
                                : DateFormat('MMM d, h:mm a').format(note.updatedAt!))
                            : note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => ref.read(repoProvider).deleteNote(note.id),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Note? note) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final bodyController = TextEditingController(text: note?.body ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'New note' : 'Edit note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyController,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Write something…'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    titleController.dispose();
    bodyController.dispose();

    if (saved != true || title.isEmpty) return;
    final repo = ref.read(repoProvider);
    if (note == null) {
      await repo.addNote(Note(id: 'new', title: title, body: body));
    } else {
      await repo.saveNote(Note(id: note.id, title: title, body: body, categoryId: note.categoryId));
    }
  }
}
