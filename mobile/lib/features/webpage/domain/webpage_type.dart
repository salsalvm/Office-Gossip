/// Pages served from the Office Gossip website, loaded as `<domain>/<path>`.
enum WebpageType {
  help('contact', 'Help & contact'),
  privacy('privacy', 'Privacy policy'),
  terms('terms', 'Terms & conditions'),

  /// Loads the domain itself (no path), e.g. the member's company site.
  company('company', 'Company website');

  const WebpageType(this.path, this.title);

  /// Route param and URL path segment, e.g. `privacy`.
  final String path;
  final String title;

  static WebpageType? fromPath(String? value) {
    for (final type in values) {
      if (type.path == value) return type;
    }
    return null;
  }

  Uri urlFor(String domain) {
    if (this == WebpageType.company) return Uri.parse(domain);
    final base = domain.endsWith('/') ? domain : '$domain/';
    return Uri.parse(base).resolve(path);
  }
}
