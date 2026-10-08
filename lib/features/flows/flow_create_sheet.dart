import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/flows/flow_advisor.dart';
import '../../core/flows/flow_templates.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/project_flow.dart';
import 'flow_detail_page.dart';

Future<void> showCreateFlowSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateFlowSheet(),
    );

class _CreateFlowSheet extends ConsumerStatefulWidget {
  const _CreateFlowSheet();

  @override
  ConsumerState<_CreateFlowSheet> createState() => _CreateFlowSheetState();
}

class _CreateFlowSheetState extends ConsumerState<_CreateFlowSheet> {
  final _name = TextEditingController();
  FlowTemplate _template = kFlowTemplates.first;
  FlowMode _mode = kFlowTemplates.first.mode;
  String? _boardId;
  bool _busy = false;

  /// Stages from the advisor, when the user has accepted its suggestion. They
  /// replace the template's stages.
  List<String>? _advisorStages;

  @override
  void initState() {
    super.initState();
    _name.text = _template.name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<String> get _stages => _advisorStages ?? _template.stages;

  Future<void> _create() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(repoProvider).flows.createFlow(
            ProjectFlow(
              id: 'new',
              name: _name.text.trim(),
              boardId: _boardId,
              mode: _mode,
              icon: _template.icon,
            ),
            stageTitles: _stages,
          );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(MaterialPageRoute<void>(builder: (_) => FlowDetailPage(flowId: id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not create the flow. Try again.')));
    }
  }

  Future<void> _askAdvisor() async {
    final accepted = await showDialog<FlowSuggestion>(
      context: context,
      builder: (_) => const FlowAdvisorDialog(),
    );
    if (accepted == null || !mounted) return;
    setState(() {
      _advisorStages = accepted.stages;
      if (accepted.flowName.isNotEmpty) _name.text = accepted.flowName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(boardsProvider).value ?? const <Board>[];
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New Project Flow',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Name'),
                onSubmitted: (_) => _create(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: boards.any((b) => b.id == _boardId) ? _boardId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Board (optional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No board')),
                  for (final b in boards)
                    DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _boardId = v),
              ),
              const SizedBox(height: 16),
              Text('Start from', style: TextStyle(color: palette.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in kFlowTemplates)
                    ChoiceChip(
                      label: Text(t.name),
                      selected: _template.id == t.id && _advisorStages == null,
                      onSelected: (_) => setState(() {
                        _template = t;
                        _mode = t.mode;
                        _advisorStages = null;
                        _name.text = t.name;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _askAdvisor,
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Suggest stages from a goal'),
              ),
              const SizedBox(height: 14),
              Text(
                _stages.isEmpty
                    ? 'No stages yet. You can add your own on the next screen.'
                    : '${_stages.length} stages: ${_stages.join(' › ')}',
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
              const SizedBox(height: 4),
              Text('This creates stages only. No tasks are created.',
                  style: TextStyle(fontSize: 12, color: palette.textDisabled)),
              const SizedBox(height: 14),
              Text('How stages unlock',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              SegmentedButton<FlowMode>(
                segments: [
                  for (final m in FlowMode.values) ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 4),
              Text(_mode.description,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Create flow'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a goal, shows the advisor's suggested stages, and lets the user
/// add them all, customise them, or cancel. Accepting returns stage titles
/// only; nothing here creates a task.
class FlowAdvisorDialog extends StatefulWidget {
  const FlowAdvisorDialog({super.key, this.advisor = const TemplateFlowAdvisor()});

  final FlowAdvisor advisor;

  @override
  State<FlowAdvisorDialog> createState() => _FlowAdvisorDialogState();
}

class _FlowAdvisorDialogState extends State<FlowAdvisorDialog> {
  final _goal = TextEditingController();
  FlowSuggestion? _suggestion;
  List<TextEditingController>? _editing;
  bool _loading = false;

  @override
  void dispose() {
    _goal.dispose();
    for (final c in _editing ?? const <TextEditingController>[]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_goal.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final s = await widget.advisor.suggest(_goal.text);
    if (!mounted) return;
    setState(() {
      _suggestion = s;
      _editing = null;
      _loading = false;
    });
  }

  void _customize() {
    final s = _suggestion;
    if (s == null) return;
    setState(() => _editing = [for (final t in s.stages) TextEditingController(text: t)]);
  }

  void _accept(List<String> stages) {
    final s = _suggestion!;
    Navigator.pop(
      context,
      FlowSuggestion(flowName: s.flowName, stages: stages, source: s.source),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _suggestion;
    final editing = _editing;

    return AlertDialog(
      title: const Text('Flow Advisor'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _goal,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'What do you want to do?',
                  hintText: 'I want to launch my Flutter app',
                ),
                onSubmitted: (_) => _suggest(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _loading ? null : _suggest,
                  child: const Text('Suggest stages'),
                ),
              ),
              if (s != null) ...[
                const SizedBox(height: 12),
                Text(s.source,
                    style: TextStyle(fontSize: 12, color: context.palette.textSecondary)),
                const SizedBox(height: 8),
                if (s.isEmpty)
                  const Text(
                    'Nothing in the built-in templates matches that. Pick a template '
                    'or start from Custom and add your own stages.',
                  )
                else if (editing != null)
                  for (final (i, c) in editing.indexed)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: c,
                            decoration: InputDecoration(labelText: 'Stage ${i + 1}', isDense: true),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove stage',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            editing.removeAt(i).dispose();
                          }),
                        ),
                      ],
                    )
                else
                  for (final (i, t) in s.stages.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('${i + 1}.  $t'),
                    ),
                const SizedBox(height: 8),
                Text('Accepting creates these stages only. No tasks are created.',
                    style: TextStyle(fontSize: 12, color: context.palette.textDisabled)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (s != null && !s.isEmpty && editing == null)
          TextButton(onPressed: _customize, child: const Text('Customize')),
        if (s != null && !s.isEmpty)
          FilledButton(
            onPressed: () => _accept(
              editing == null
                  ? s.stages
                  : [
                      for (final c in editing)
                        if (c.text.trim().isNotEmpty) c.text.trim(),
                    ],
            ),
            child: Text(editing == null ? 'Add all' : 'Use these'),
          ),
      ],
    );
  }
}
