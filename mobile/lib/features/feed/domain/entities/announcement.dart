enum AnnouncementAudience { everyone, user, company }

/// A "Flash update" published by the Office Gossip admin team.
class Announcement {
  const Announcement({
    required this.id,
    required this.message,
    required this.audience,
    required this.time,
  });

  final String id;
  final String message;
  final AnnouncementAudience audience;
  final String time;
}
