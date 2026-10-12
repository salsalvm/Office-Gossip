class CommunityMember {
  const CommunityMember(
      {required this.id,
      required this.name,
      required this.role,
      required this.team,
      this.muted = false});
  final String id;
  final String name;
  final String role;
  final String team;

  /// The signed-in member muted this person, so their posts are hidden.
  final bool muted;
}
