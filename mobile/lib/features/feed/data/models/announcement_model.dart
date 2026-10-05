import '../../domain/entities/announcement.dart';

class AnnouncementModel extends Announcement {
  const AnnouncementModel({
    required super.id,
    required super.message,
    required super.audience,
    required super.time,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) =>
      AnnouncementModel(
        id: json['id'].toString(),
        message: json['message'] as String? ?? '',
        audience: AnnouncementAudience.values.firstWhere(
          (value) => value.name == json['audience'],
          orElse: () => AnnouncementAudience.everyone,
        ),
        time: json['time'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'message': message, 'audience': audience.name, 'time': time};
}
