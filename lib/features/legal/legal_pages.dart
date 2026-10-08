import 'package:flutter/material.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import 'legal_content.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _LegalPage(title: 'Privacy Policy', sections: kPrivacySections);
}

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _LegalPage(title: 'Terms of Service', sections: kTermsSections);
}

class _LegalPage extends StatelessWidget {
  const _LegalPage({required this.title, required this.sections});

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text('$kAppName · Last updated $kLegalUpdated',
                    style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                for (final s in sections) ...[
                  const SizedBox(height: 20),
                  Text(s.heading,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(s.body, style: const TextStyle(fontSize: 14, height: 1.45)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable Terms and Privacy Policy links, shown under the sign-in form.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(onPressed: () => open(const TermsPage()), child: const Text('Terms')),
        Text('·', style: TextStyle(color: context.palette.textSecondary)),
        TextButton(
            onPressed: () => open(const PrivacyPolicyPage()),
            child: const Text('Privacy Policy')),
      ],
    );
  }
}
