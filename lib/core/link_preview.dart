/// A link found in a task's description, reduced to what a card can draw
/// without a network call.
///
/// Fetching Open Graph metadata is not possible from the web build (the
/// browser blocks the cross-origin request) and is not worth a request per
/// card elsewhere, so the preview is derived from the URL itself. Hosts whose
/// thumbnail URL is derivable get an image; everything else falls back to the
/// domain, which is the behaviour section 7 of the brief asks for when
/// metadata cannot be fetched.
class LinkPreview {
  const LinkPreview({
    required this.url,
    required this.domain,
    this.siteName,
    this.thumbnailUrl,
  });

  final String url;

  /// `youtube.com`, with any `www.` removed.
  final String domain;

  /// A friendly name when the host is recognised, e.g. `YouTube`.
  final String? siteName;

  /// Only set when it can be derived from the URL with no request.
  final String? thumbnailUrl;

  bool get hasThumbnail => thumbnailUrl != null;

  /// The first http(s) link in [text], or null.
  static LinkPreview? firstIn(String text) {
    final match = _urlPattern.firstMatch(text);
    if (match == null) return null;
    return forUrl(match.group(0)!);
  }

  /// Every http(s) link in [text], in order, without duplicates.
  static List<LinkPreview> allIn(String text) {
    final seen = <String>{};
    final found = <LinkPreview>[];
    for (final match in _urlPattern.allMatches(text)) {
      final preview = forUrl(match.group(0)!);
      if (preview == null || !seen.add(preview.url)) continue;
      found.add(preview);
    }
    return found;
  }

  /// Builds a preview for one URL, or null if it cannot be parsed.
  ///
  /// This never throws: a malformed URL in a description must not stop the
  /// card from rendering.
  static LinkPreview? forUrl(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'[.,;:)\]]+$'), '');
    final uri = Uri.tryParse(trimmed);
    // `http://` parses but has no host, and a bare phrase parses as a relative
    // path — neither is something a card can preview.
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final domain = uri.host.replaceFirst(RegExp(r'^www\.'), '');

    return LinkPreview(
      url: trimmed,
      domain: domain,
      siteName: _siteNames[domain],
      thumbnailUrl: _thumbnailFor(uri, domain),
    );
  }

  /// Thumbnails that are a pure function of the URL, so no request is needed.
  static String? _thumbnailFor(Uri uri, String domain) {
    final videoId = switch (domain) {
      'youtube.com' || 'm.youtube.com' => uri.queryParameters['v'],
      'youtu.be' => uri.pathSegments.firstOrNull,
      _ => null,
    };
    if (videoId == null || videoId.isEmpty) return null;
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  static const _siteNames = <String, String>{
    'youtube.com': 'YouTube',
    'm.youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'github.com': 'GitHub',
    'figma.com': 'Figma',
    'notion.so': 'Notion',
    'docs.google.com': 'Google Docs',
    'drive.google.com': 'Google Drive',
    'tiktok.com': 'TikTok',
    'facebook.com': 'Facebook',
    'instagram.com': 'Instagram',
    'x.com': 'X',
    'twitter.com': 'X',
    'linkedin.com': 'LinkedIn',
  };

  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
}
