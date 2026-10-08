import 'flow_templates.dart';

/// Stages suggested for a goal such as "I want to launch my Flutter app".
class FlowSuggestion {
  const FlowSuggestion({
    required this.flowName,
    required this.stages,
    required this.source,
  });

  final String flowName;
  final List<String> stages;

  /// Plain words for where the suggestion came from, shown to the user so a
  /// canned template is never mistaken for something it is not.
  final String source;

  bool get isEmpty => stages.isEmpty;
}

/// Suggests the stages of a flow from a description of a goal.
///
/// This is only a boundary. A suggestion is a list of stage titles, nothing
/// more: accepting it creates stages, never tasks. Whatever implementation sits
/// behind it, the caller shows the result and waits for the user to accept,
/// edit or cancel it.
abstract class FlowAdvisor {
  Future<FlowSuggestion> suggest(String goal);
}

/// Matches words in the goal against the built-in templates.
///
/// There is no AI behind this and it does not claim there is. It is keyword
/// matching over the same templates the template picker offers, labelled as
/// such. A real model could replace it by implementing [FlowAdvisor].
class TemplateFlowAdvisor implements FlowAdvisor {
  const TemplateFlowAdvisor();

  static const _keywords = <String, List<String>>{
    'mobile_app_launch': ['app', 'flutter', 'android', 'ios', 'mobile', 'play store', 'app store'],
    'website_launch': ['website', 'web site', 'site', 'landing page', 'web app'],
    'youtube_channel_launch': ['youtube', 'channel', 'vlog', 'video series'],
    'product_launch': ['product', 'launch', 'release'],
    'client_project': ['client', 'customer', 'freelance', 'contract'],
  };

  @override
  Future<FlowSuggestion> suggest(String goal) async {
    final text = goal.toLowerCase();

    // The template whose keywords match the most wins; ties keep the order of
    // [_keywords], so the more specific kinds come first.
    FlowTemplate? best;
    var bestScore = 0;
    for (final entry in _keywords.entries) {
      final score = entry.value.where(text.contains).length;
      if (score > bestScore) {
        bestScore = score;
        best = flowTemplateById(entry.key);
      }
    }

    if (best == null) {
      return const FlowSuggestion(flowName: '', stages: [], source: 'No matching template');
    }
    return FlowSuggestion(
      flowName: best.name,
      stages: best.stages,
      source: 'Built-in "${best.name}" template (keyword match, not AI)',
    );
  }
}
