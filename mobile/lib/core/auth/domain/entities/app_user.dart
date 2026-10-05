import 'package:equatable/equatable.dart';

class UserCompany extends Equatable {
  const UserCompany({required this.id, required this.name});
  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

class UserStats extends Equatable {
  const UserStats({this.posts = 0, this.reactions = 0, this.comments = 0});
  final int posts;
  final int reactions;
  final int comments;

  @override
  List<Object?> get props => [posts, reactions, comments];
}

/// What a member must have before the API accepts a community post.
enum PostingRequirement { displayName, activeCompany }

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.username,
    this.roleTitle,
    this.bio,
    this.themePreference = 'system',
    this.company,
    this.companyRequestPending = false,
    this.pendingCompanyName,
    this.stats = const UserStats(),
    this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String? username;
  final String? roleTitle;
  final String? bio;
  final String themePreference;
  final UserCompany? company;
  final bool companyRequestPending;
  final String? pendingCompanyName;
  final UserStats stats;
  final DateTime? createdAt;

  List<PostingRequirement> get missingForPosting => [
        if (name.trim().isEmpty) PostingRequirement.displayName,
        if (company == null) PostingRequirement.activeCompany,
      ];

  bool get canPost => missingForPosting.isEmpty;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  List<Object?> get props => [
        id,
        email,
        name,
        username,
        roleTitle,
        bio,
        themePreference,
        company,
        companyRequestPending,
        pendingCompanyName,
        stats,
        createdAt,
      ];
}
