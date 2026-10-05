/// Data restored from the on-device cache, with the time it was last synced.
class Cached<T> {
  const Cached(this.data, this.savedAt);

  final T data;
  final DateTime savedAt;
}

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String syncedAgo(DateTime savedAt) {
  final diff = DateTime.now().difference(savedAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
