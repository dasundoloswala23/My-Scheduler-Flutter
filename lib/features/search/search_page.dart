import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../task_detail/task_detail_sheet.dart';

/// What a result points at, so the list can show the right icon and act on a tap.
enum SearchKind { task, subtask, note, board, list, category }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.task,
  });

  final SearchKind kind;
  final String title;
  final String subtitle;
  final Task? task;
}

/// Filters applied on top of the text query.
class SearchFilters {
  const SearchFilters({
    this.categoryId,
    this.boardId,
    this.priority,
    this.completed,
    this.hasReminder = false,
    this.hasAttachment = false,
    this.scheduled,
  });

  final String? categoryId;
  final String? boardId;
  final TaskPriority? priority;
  final bool? completed;
  final bool hasReminder;
  final bool hasAttachment;
  final bool? scheduled;

  bool get isEmpty =>
      categoryId == null &&
      boardId == null &&
      priority == null &&
      completed == null &&
      !hasReminder &&
      !hasAttachment &&
      scheduled == null;

  SearchFilters copyWith({
    Object? categoryId = _keep,
    Object? boardId = _keep,
    Object? priority = _keep,
    Object? completed = _keep,
    bool? hasReminder,
    bool? hasAttachment,
    Object? scheduled = _keep,
  }) =>
      SearchFilters(
        categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
        boardId: boardId == _keep ? this.boardId : boardId as String?,
        priority: priority == _keep ? this.priority : priority as TaskPriority?,
        completed: completed == _keep ? this.completed : completed as bool?,
        hasReminder: hasReminder ?? this.hasReminder,
        hasAttachment: hasAttachment ?? this.hasAttachment,
        scheduled: scheduled == _keep ? this.scheduled : scheduled as bool?,
      );
}

const _keep = Object();

/// Global search across tasks, subtasks, notes, boards, lists and categories.
///
/// Everything is already streamed into memory for the board and calendar, so
/// this filters what is there instead of issuing more Firestore queries.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';
  SearchFilters _filters = const SearchFilters();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SearchHit> _results() {
    final q = _query.trim().toLowerCase();
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final notes = ref.read(notesProvider).value ?? const <Note>[];
    final boards = ref.read(boardsProvider).value ?? const <Board>[];
    final lists = ref.read(listsProvider).value ?? const <TaskList>[];
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final categoryById = ref.read(categoryByIdProvider);

    bool matches(String text) => q.isEmpty || text.toLowerCase().contains(q);

    bool passesFilters(Task t) {
      final f = _filters;
      if (f.categoryId != null && t.categoryId != f.categoryId) return false;
      if (f.boardId != null && t.boardId != f.boardId) return false;
      if (f.priority != null && t.priority != f.priority) return false;
      if (f.completed != null && t.completed != f.completed) return false;
      if (f.hasReminder && t.reminderOffsets.isEmpty) return false;
      if (f.hasAttachment && t.attachmentCount == 0 && t.attachments.isEmpty) return false;
      if (f.scheduled != null && (t.startDateTime != null) != f.scheduled) return false;
      return true;
    }

    final hits = <SearchHit>[];

    for (final task in tasks) {
      if (!passesFilters(task)) continue;

      if (matches(task.title) || matches(task.description)) {
        hits.add(SearchHit(
          kind: SearchKind.task,
          title: task.title,
          subtitle: [
            categoryById[task.categoryId]?.name,
            if (task.startDateTime != null) DateFormat('MMM d, h:mm a').format(task.startDateTime!),
            if (task.completed) 'Completed',
          ].whereType<String>().join(' · '),
          task: task,
        ));
      }

      for (final sub in task.subtasks) {
        if (matches(sub.title)) {
          hits.add(SearchHit(
            kind: SearchKind.subtask,
            title: sub.title,
            subtitle: 'Subtask of ${task.title}',
            task: task,
          ));
        }
      }
    }

    // Non-task results only make sense when no task-specific filter is on.
    if (_filters.isEmpty) {
      for (final note in notes) {
        if (matches(note.title) || matches(note.body)) {
          hits.add(SearchHit(kind: SearchKind.note, title: note.title, subtitle: 'Note'));
        }
      }
      for (final board in boards) {
        if (matches(board.name)) {
          hits.add(SearchHit(kind: SearchKind.board, title: board.name, subtitle: 'Board'));
        }
      }
      for (final list in lists) {
        if (matches(list.name)) {
          hits.add(SearchHit(kind: SearchKind.list, title: list.name, subtitle: 'List'));
        }
      }
      for (final category in categories) {
        if (matches(category.name)) {
          hits.add(SearchHit(kind: SearchKind.category, title: category.name, subtitle: 'Category'));
        }
      }
    }

    return hits;
  }

  @override
  Widget build(BuildContext context) {
    // Watch the sources so results refresh as data arrives.
    ref.watch(tasksProvider);
    ref.watch(notesProvider);
    final hits = _query.trim().isEmpty && _filters.isEmpty ? <SearchHit>[] : _results();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search tasks, boards, notes…',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            filters: _filters,
            onChanged: (f) => setState(() => _filters = f),
          ),
          Expanded(
            child: hits.isEmpty
                ? _EmptyResults(hasQuery: _query.trim().isNotEmpty || !_filters.isEmpty)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: hits.length,
                    itemBuilder: (context, i) => _HitTile(hit: hits[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters, required this.onChanged});

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _Chip(
            label: filters.categoryId == null
                ? 'Category'
                : categories.where((c) => c.id == filters.categoryId).firstOrNull?.name ?? 'Category',
            active: filters.categoryId != null,
            onTap: () async {
              final chosen = await _pick<Category?>(
                context,
                'Category',
                [null, ...categories],
                (c) => c?.name ?? 'Any category',
              );
              onChanged(filters.copyWith(categoryId: chosen?.id));
            },
          ),
          _Chip(
            label: filters.boardId == null
                ? 'Board'
                : boards.where((b) => b.id == filters.boardId).firstOrNull?.name ?? 'Board',
            active: filters.boardId != null,
            onTap: () async {
              final chosen = await _pick<Board?>(
                context,
                'Board',
                [null, ...boards],
                (b) => b?.name ?? 'Any board',
              );
              onChanged(filters.copyWith(boardId: chosen?.id));
            },
          ),
          _Chip(
            label: filters.priority == null ? 'Priority' : filters.priority!.label,
            active: filters.priority != null,
            onTap: () async {
              final chosen = await _pick<TaskPriority?>(
                context,
                'Priority',
                [null, ...TaskPriority.values],
                (p) => p?.label ?? 'Any priority',
              );
              onChanged(filters.copyWith(priority: chosen));
            },
          ),
          _Chip(
            label: switch (filters.completed) {
              true => 'Completed',
              false => 'Not done',
              _ => 'Status',
            },
            active: filters.completed != null,
            onTap: () => onChanged(filters.copyWith(
              completed: switch (filters.completed) {
                null => false,
                false => true,
                true => null,
              },
            )),
          ),
          _Chip(
            label: 'Scheduled',
            active: filters.scheduled == true,
            onTap: () => onChanged(filters.copyWith(scheduled: filters.scheduled == true ? null : true)),
          ),
          _Chip(
            label: 'Has reminder',
            active: filters.hasReminder,
            onTap: () => onChanged(filters.copyWith(hasReminder: !filters.hasReminder)),
          ),
          _Chip(
            label: 'Has attachment',
            active: filters.hasAttachment,
            onTap: () => onChanged(filters.copyWith(hasAttachment: !filters.hasAttachment)),
          ),
        ],
      ),
    );
  }

  Future<T?> _pick<T>(
    BuildContext context,
    String title,
    List<T> options,
    String Function(T) label,
  ) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final option in options)
              ListTile(title: Text(label(option)), onTap: () => Navigator.pop(context, option)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? context.palette.selected : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppColors.primary : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? context.palette.accent : context.palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});
  final SearchHit hit;

  IconData get _icon => switch (hit.kind) {
        SearchKind.task => Icons.check_circle_outline,
        SearchKind.subtask => Icons.subdirectory_arrow_right,
        SearchKind.note => Icons.sticky_note_2_outlined,
        SearchKind.board => Icons.view_week_outlined,
        SearchKind.list => Icons.list,
        SearchKind.category => Icons.label_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_icon, size: 20, color: context.palette.accent),
        title: Text(hit.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: hit.subtitle.isEmpty
            ? null
            : Text(hit.subtitle, style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
        onTap: hit.task == null ? null : () => showTaskDetailSheet(context, hit.task!),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasQuery ? Icons.search_off : Icons.search, size: 40, color: context.palette.textSecondary),
            const SizedBox(height: 14),
            Text(
              hasQuery ? 'No results' : 'Search your workspace',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? 'Try a different word, or clear a filter.'
                  : 'Find tasks, subtasks, notes, boards, lists and categories.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
