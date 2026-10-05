import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.id,
    required super.email,
    required super.name,
    super.username,
    super.roleTitle,
    super.bio,
    super.themePreference,
    super.company,
    super.emailVerified,
    super.companyRequestPending,
    super.pendingCompanyName,
    super.stats,
    super.createdAt,
  });

  factory AppUserModel.fromJson(Map<String, dynamic> json) {
    final company = json['company'];
    final stats = json['stats'];
    return AppUserModel(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      username: json['username'] as String?,
      roleTitle: json['roleTitle'] as String?,
      bio: json['bio'] as String?,
      themePreference: json['themePreference'] as String? ?? 'system',
      company: company is Map
          ? UserCompany(
              id: company['id'].toString(),
              name: company['name'] as String? ?? '',
              website: company['website'] as String?,
            )
          : null,
      emailVerified: json['emailVerified'] as bool? ?? false,
      companyRequestPending: json['companyRequestPending'] as bool? ?? false,
      pendingCompanyName: json['pendingCompanyName'] as String?,
      stats: stats is Map
          ? UserStats(
              posts: stats['posts'] as int? ?? 0,
              reactions: stats['reactions'] as int? ?? 0,
              comments: stats['comments'] as int? ?? 0,
            )
          : const UserStats(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'username': username,
        'roleTitle': roleTitle,
        'bio': bio,
        'themePreference': themePreference,
        'company': company == null
            ? null
            : {
                'id': company!.id,
                'name': company!.name,
                'website': company!.website,
              },
        'emailVerified': emailVerified,
        'companyRequestPending': companyRequestPending,
        'pendingCompanyName': pendingCompanyName,
        'stats': {
          'posts': stats.posts,
          'reactions': stats.reactions,
          'comments': stats.comments,
        },
        'createdAt': createdAt?.toIso8601String(),
      };
}
