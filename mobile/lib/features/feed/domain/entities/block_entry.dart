enum BlockKind {
  block,
  mute;

  static BlockKind fromName(String? name) =>
      name == 'mute' ? BlockKind.mute : BlockKind.block;
}

/// A member the signed-in member blocked or muted. Entries made from an
/// anonymous post only ever show [label] "Anonymous member".
class BlockEntry {
  const BlockEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.anonymous,
    this.createdAt,
  });

  final String id;
  final BlockKind kind;
  final String label;
  final bool anonymous;
  final DateTime? createdAt;

  factory BlockEntry.fromJson(Map<String, dynamic> json) => BlockEntry(
        id: json['id'].toString(),
        kind: BlockKind.fromName(json['kind'] as String?),
        label: json['label'] as String? ?? 'Member',
        anonymous: json['anonymous'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
