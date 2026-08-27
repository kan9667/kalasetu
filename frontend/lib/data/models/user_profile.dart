import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 2)
class UserProfile extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String phone;

  @HiveField(3)
  final String? avatarUrl;

  @HiveField(4)
  final String craftType;

  @HiveField(5)
  final String locationCluster;

  @HiveField(6)
  final String preferredLanguage;

  UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarUrl,
    required this.craftType,
    required this.locationCluster,
    this.preferredLanguage = 'en',
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? phone,
    String? avatarUrl,
    String? craftType,
    String? locationCluster,
    String? preferredLanguage,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      craftType: craftType ?? this.craftType,
      locationCluster: locationCluster ?? this.locationCluster,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'craftType': craftType,
      'locationCluster': locationCluster,
      'preferredLanguage': preferredLanguage,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      craftType: json['craftType'] as String? ?? 'Handicraft',
      locationCluster: json['locationCluster'] as String? ?? 'Rural Cluster',
      preferredLanguage: json['preferredLanguage'] as String? ?? 'en',
    );
  }
}
