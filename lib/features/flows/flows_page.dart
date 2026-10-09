import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/flows/flow_engine.dart';
import '../../core/flows/flow_filters.dart';
import '../../core/flows/flow_providers.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/project_flow.dart';
import '../more/more_page.dart';
import 'flow_create_sheet.dart';
import 'flow_detail_page.dart';

/// Every Project Flow, with filters, search and board and category pickers.
class ProjectFlowsPage extends ConsumerStatefulWidget {
  const ProjectFlowsPage({super.key});

  @override
  ConsumerState<ProjectFlowsPage> createState() => _ProjectFlowsPageState();
}

class _ProjectFlowsPageState extends ConsumerState<ProjectFlowsPage> {
  FlowFilter _filter = FlowFilter.all;
  final _search = TextEditingController();
  String? _boardId;
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flows = ref.watch(flowsProvider).value ?? const <ProjectFlow>[];
    final results = ref.watch(flowResultsProvider);
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];

    final shown = filterFlows(
      flows: flows,
      results: results,
      filter: _filter,
      search: _search.text,
      boardId: _boardId,
      categoryId: _categoryId,
      now: DateTime.now(),
    );

    return SubPage(
      eyebrow: 'Plan a project',
      title: 'Project Flows',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateFlowSheet(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New flow'),
      ),
      child: flows.isEmpty
          ? EmptyState(
              icon: Icons.rocket_launch_outlined,
              title: 'Plan a project in stages',
              actionLabel: 'New flow',
              onAction: () => showCreateFlowSheet(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search flows',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in FlowFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.label),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Picker<String>(
                        label: 'Board',
                        value: _boardId,
                        items: {for (final b in boards) b.id: b.name},
                        onChanged: (v) => setState(() => _boardId = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Picker<String>(
                        label: 'Category',
                        value: _categoryId,
                        items: {for (final c in categories) c.id: c.name},
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No flows match.',
                          style: TextStyle(color: context.palette.textSecondary)),
                    ),
                  )
                else
                  for (final flow in shown) _FlowCard(flow: flow, result: results[flow.id]),
              ],
            ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      initialValue: items.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text('All ${label.toLowerCase()}s')),
        for (final e in items.entries)
          DropdownMenuItem<T?>(
              value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.flow, required this.result});

  final ProjectFlow flow;
  final FlowResult? result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = result;
    final status = r?.status ?? flow.status;
    final blocked = r != null && isBlocked(r);
    final current = r?.stages
        .where((s) => s.stage.id == r.currentStageId)
        .map((s) => s.stage.title)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => FlowDetailPage(flowId: flow.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rocket_launch_outlined, color: Color(flow.colorValue), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(flow.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  _StatusChip(
                    label: blocked ? 'Blocked' : status.label,
                    color: blocked
                        ? palette.danger
                        : switch (status) {
                            FlowStatus.completed => palette.success,
                            FlowStatus.active => context.palette.accent,
                            _ => palette.textSecondary,
                          },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: r?.progress ?? 0, minHeight: 7),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${r?.completedStages ?? 0}/${r?.totalStages ?? 0} stages',
                    style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                  ),
                  if (current != null) ...[
                    Text('  ·  ', style: TextStyle(color: palette.textSecondary)),
                    Flexible(
                      child: Text('Now: $current',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const Spacer(),
                  if (flow.dueDate != null)
                    Text('Due ${DateFormat('MMM d').format(flow.dueDate!)}',
                        style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );
}
