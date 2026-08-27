import 'package:hive/hive.dart';

/// Repository for authentication operations with Hive persistence
class AuthRepository {
  static const String _boxName = 'auth_box';
  static const String _keyUserId = 'user_id';
  static const String _keyPhoneNumber = 'phone_number';
  static const String _keyIsAuthenticated = 'is_authenticated';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<bool> isAuthenticated() async {
    final box = await _getBox();
    return box.get(_keyIsAuthenticated, defaultValue: false) as bool;
  }

  Future<String?> getUserId() async {
    final box = await _getBox();
    return box.get(_keyUserId) as String?;
  }

  Future<String?> getPhoneNumber() async {
    final box = await _getBox();
    return box.get(_keyPhoneNumber) as String?;
  }

  Future<void> savePhoneNumber(String phoneNumber) async {
    final box = await _getBox();
    await box.put(_keyPhoneNumber, phoneNumber);
  }

  Future<void> saveAuthData(String userId, String phoneNumber) async {
    final box = await _getBox();
    await box.put(_keyUserId, userId);
    await box.put(_keyPhoneNumber, phoneNumber);
    await box.put(_keyIsAuthenticated, true);
  }

  Future<void> clearAuthData() async {
    final box = await _getBox();
    await box.delete(_keyUserId);
    await box.delete(_keyPhoneNumber);
    await box.put(_keyIsAuthenticated, false);
  }
}
