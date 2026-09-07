import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../core/config/api_config.dart';
import '../models/user_profile.dart';

/// Repository for authentication operations with Hive persistence and live backend integration
class AuthRepository {
  static const String _boxName = 'auth_box';
  static const String _keyUserId = 'user_id';
  static const String _keyPhoneNumber = 'phone_number';
  static const String _keyIsAuthenticated = 'is_authenticated';
  static const String _keyAccessToken = 'access_token';

  final Dio _dio;
  final String? _explicitBaseUrl;

  AuthRepository({String? baseUrl, Dio? dio})
      : _explicitBaseUrl = baseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? ApiConfig.baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  void _syncBaseUrl() {
    _dio.options.baseUrl = _explicitBaseUrl ?? ApiConfig.baseUrl;
  }

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

  Future<String?> getAccessToken() async {
    final box = await _getBox();
    return box.get(_keyAccessToken) as String?;
  }

  Future<void> savePhoneNumber(String phoneNumber) async {
    final box = await _getBox();
    await box.put(_keyPhoneNumber, phoneNumber);
  }

  Future<void> saveAuthData(String userId, String phoneNumber, {String? token}) async {
    final box = await _getBox();
    await box.put(_keyUserId, userId);
    await box.put(_keyPhoneNumber, phoneNumber);
    await box.put(_keyIsAuthenticated, true);
    if (token != null) {
      await box.put(_keyAccessToken, token);
    }
  }

  Future<void> clearAuthData() async {
    final box = await _getBox();
    await box.delete(_keyUserId);
    await box.delete(_keyPhoneNumber);
    await box.delete(_keyAccessToken);
    await box.put(_keyIsAuthenticated, false);
  }

  /// Registers artisan with backend `/api/v1/auth/register`
  Future<UserProfile?> registerArtisan(UserProfile profile) async {
    _syncBaseUrl();
    try {
      final payload = profile.toBackendJson();
      debugPrint('[AuthRepository] POST ${_dio.options.baseUrl}/api/v1/auth/register');
      final response = await _dio.post('/api/v1/auth/register', data: payload);
      if (response.statusCode == 201 && response.data != null) {
        return UserProfile.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
    } on DioException catch (e) {
      // 409 Conflict means phone is already registered on backend — continue
      if (e.response?.statusCode == 409) {
        debugPrint('[AuthRepository] Phone already registered on backend, proceeding to login.');
      } else {
        debugPrint('[AuthRepository] registerArtisan network error: ${e.message}');
      }
    } catch (e) {
      debugPrint('[AuthRepository] registerArtisan unexpected error: $e');
    }
    return null;
  }

  /// Requests login OTP from `/api/v1/auth/login`
  Future<Map<String, dynamic>?> requestOtp(String phoneNumber) async {
    _syncBaseUrl();
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    try {
      debugPrint('[AuthRepository] POST ${_dio.options.baseUrl}/api/v1/auth/login');
      final response = await _dio.post('/api/v1/auth/login', data: {'phone': cleanPhone});
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } on DioException catch (e) {
      debugPrint('[AuthRepository] requestOtp failed: ${e.message}');
    } catch (e) {
      debugPrint('[AuthRepository] requestOtp unexpected error: $e');
    }
    return null;
  }

  /// Verifies OTP with backend `/api/v1/auth/verify-otp`
  Future<(UserProfile?, String?)> verifyOtpWithBackend(String phoneNumber, String otp) async {
    _syncBaseUrl();
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    try {
      debugPrint('[AuthRepository] POST ${_dio.options.baseUrl}/api/v1/auth/verify-otp');
      final response = await _dio.post('/api/v1/auth/verify-otp', data: {
        'phone': cleanPhone,
        'otp': otp,
      });

      if (response.statusCode == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final token = data['access_token'] as String?;
        final artisanMap = data['artisan'] != null
            ? Map<String, dynamic>.from(data['artisan'] as Map)
            : null;

        final profile = artisanMap != null ? UserProfile.fromJson(artisanMap) : null;
        return (profile, token);
      }
    } on DioException catch (e) {
      debugPrint('[AuthRepository] verifyOtpWithBackend failed: ${e.message}');
    } catch (e) {
      debugPrint('[AuthRepository] verifyOtpWithBackend unexpected error: $e');
    }
    return (null, null);
  }
}
