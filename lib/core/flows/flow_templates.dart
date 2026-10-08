import '../../models/project_flow.dart';

/// A starting shape for a flow: a name, a mode and stage titles. A template
/// creates stages only. It never creates tasks; the user links the tasks they
/// already have, or adds new ones, afterwards.
class FlowTemplate {
  const FlowTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.stages,
    this.mode = FlowMode.sequential,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final List<String> stages;
  final FlowMode mode;
}

const List<FlowTemplate> kFlowTemplates = [
  FlowTemplate(
    id: 'mobile_app_launch',
    name: 'Mobile App Launch',
    description: 'From first plan to a live app and what follows.',
    icon: 'smartphone',
    stages: [
      'Planning',
      'Development',
      'Internal QA',
      'Beta Testing',
      'Store Preparation',
      'Google Play',
      'App Store',
      'Marketing',
      'Post Launch',
    ],
  ),
  FlowTemplate(
    id: 'website_launch',
    name: 'Website Launch',
    description: 'Plan, build, test and publish a website.',
    icon: 'language',
    stages: [
      'Discovery',
      'Design',
      'Development',
      'Content',
      'Testing',
      'Launch',
      'Post Launch',
    ],
  ),
  FlowTemplate(
    id: 'client_project',
    name: 'Client Project',
    description: 'Deliver work for a client, from brief to hand-over.',
    icon: 'work_outline',
    stages: [
      'Brief',
      'Proposal',
      'Kick-off',
      'Delivery',
      'Review',
      'Hand-over',
      'Invoice',
    ],
  ),
  FlowTemplate(
    id: 'product_launch',
    name: 'Product Launch',
    description: 'Take a product to market.',
    icon: 'inventory_2',
    stages: [
      'Research',
      'Product Definition',
      'Build',
      'Beta',
      'Go-to-market',
      'Launch',
      'Feedback',
    ],
  ),
  FlowTemplate(
    id: 'youtube_channel_launch',
    name: 'YouTube Channel Launch',
    description: 'Set up a channel and publish the first videos.',
    icon: 'smart_display',
    stages: [
      'Channel Concept',
      'Branding',
      'Equipment & Setup',
      'First Videos',
      'Publish',
      'Promote',
      'Review Analytics',
    ],
  ),
  FlowTemplate(
    id: 'custom',
    name: 'Custom',
    description: 'Start empty and add your own stages.',
    icon: 'tune',
    stages: [],
    mode: FlowMode.flexible,
  ),
];

FlowTemplate? flowTemplateById(String id) =>
    kFlowTemplates.where((t) => t.id == id).firstOrNull;
