// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 2;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      id: fields[0] as String,
      name: fields[1] as String,
      phone: fields[2] as String,
      avatarUrl: fields[3] as String?,
      craftType: fields[4] as String,
      locationCluster: fields[5] as String,
      preferredLanguage: fields[6] as String? ?? 'en',
      state: fields[7] as String? ?? '',
      experienceYears: fields[8] as String?,
      pehchanId: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.phone)
      ..writeByte(3)
      ..write(obj.avatarUrl)
      ..writeByte(4)
      ..write(obj.craftType)
      ..writeByte(5)
      ..write(obj.locationCluster)
      ..writeByte(6)
      ..write(obj.preferredLanguage)
      ..writeByte(7)
      ..write(obj.state)
      ..writeByte(8)
      ..write(obj.experienceYears)
      ..writeByte(9)
      ..write(obj.pehchanId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
