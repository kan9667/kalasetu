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

  @HiveField(7)
  final String state;

  @HiveField(8)
  final String? experienceYears;

  @HiveField(9)
  final String? pehchanId;

  UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarUrl,
    required this.craftType,
    required this.locationCluster,
    this.preferredLanguage = 'en',
    this.state = '',
    this.experienceYears,
    this.pehchanId,
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? phone,
    String? avatarUrl,
    String? craftType,
    String? locationCluster,
    String? preferredLanguage,
    String? state,
    String? experienceYears,
    String? pehchanId,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      craftType: craftType ?? this.craftType,
      locationCluster: locationCluster ?? this.locationCluster,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      state: state ?? this.state,
      experienceYears: experienceYears ?? this.experienceYears,
      pehchanId: pehchanId ?? this.pehchanId,
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
      'state': state,
      'experienceYears': experienceYears,
      'pehchanId': pehchanId,
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
      state: json['state'] as String? ?? '',
      experienceYears: json['experienceYears'] as String?,
      pehchanId: json['pehchanId'] as String?,
    );
  }
}
