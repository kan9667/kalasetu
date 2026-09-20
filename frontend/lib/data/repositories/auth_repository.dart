import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../core/config/api_config.dart';
import '../../core/storage/secure_token_storage.dart';
import '../models/user_profile.dart';

/// Repository for authentication operations with Hive persistence and live backend integration
class AuthRepository {
  static const String _boxName = 'auth_box';
  static const String _keyUserId = 'user_id';
  static const String _keyPhoneNumber = 'phone_number';
  static const String _keyIsAuthenticated = 'is_authenticated';
  static const String _keyAccessToken = 'access_token';
  static const String _keyIsNgoSimulation = 'is_ngo_simulation';
  static const String _keyNgoUserId = 'ngo_user_id';

  final Dio _dio;
  final String? _explicitBaseUrl;
  final SecureTokenStorage _tokenStorage;

  AuthRepository({String? baseUrl, Dio? dio, SecureTokenStorage? tokenStorage})
      : _explicitBaseUrl = baseUrl,
        _tokenStorage = tokenStorage ?? SecureTokenStorage(),
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

  Future<bool> isNgoSimulation() async {
    final box = await _getBox();
    return box.get(_keyIsNgoSimulation, defaultValue: false) as bool;
  }

  Future<String?> getNgoUserId() async {
    final box = await _getBox();
    return box.get(_keyNgoUserId) as String?;
  }

  Future<void> saveNgoSimulationData(String userId) async {
    final box = await _getBox();
    await box.put(_keyIsNgoSimulation, true);
    await box.put(_keyNgoUserId, userId);
  }

  Future<void> clearNgoSimulationData() async {
    final box = await _getBox();
    await box.delete(_keyIsNgoSimulation);
    await box.delete(_keyNgoUserId);
  }

  Future<bool> isAuthenticated() async {
    final box = await _getBox();
    final isSim = box.get(_keyIsNgoSimulation, defaultValue: false) as bool;
    if (isSim) return false;
    final isAuth = box.get(_keyIsAuthenticated, defaultValue: false) as bool;
    final token = await getAccessToken();
    // Persisted local authentication flags alone must not establish a new verified session.
    return isAuth && (token != null && token.isNotEmpty);
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
    final secureToken = await _tokenStorage.getToken();
    if (secureToken != null && secureToken.isNotEmpty) {
      return secureToken;
    }
    final box = await _getBox();
    return box.get(_keyAccessToken) as String?;
  }

  Future<void> savePhoneNumber(String phoneNumber) async {
    final box = await _getBox();
    await box.put(_keyPhoneNumber, phoneNumber);
  }

  Future<void> saveAuthData(String userId, String phoneNumber, {String? token}) async {
    final box = await _getBox();
    await box.delete(_keyIsNgoSimulation);
    await box.delete(_keyNgoUserId);
    await box.put(_keyUserId, userId);
    await box.put(_keyPhoneNumber, phoneNumber);
    await box.put(_keyIsAuthenticated, true);
    if (token != null && token.isNotEmpty) {
      await _tokenStorage.saveToken(token);
      await box.delete(_keyAccessToken);
    }
  }

  Future<void> clearAuthData() async {
    final box = await _getBox();
    await box.delete(_keyUserId);
    await box.delete(_keyPhoneNumber);
    await box.delete(_keyAccessToken);
    await _tokenStorage.clearToken();
    await box.put(_keyIsAuthenticated, false);
    await box.delete(_keyIsNgoSimulation);
    await box.delete(_keyNgoUserId);
  }

  /// Registers artisan with backend `/api/v1/auth/register`
  Future<RegisterArtisanResult> registerArtisan(UserProfile profile) async {
    _syncBaseUrl();
    try {
      final payload = profile.toBackendJson();
      debugPrint('[AuthRepository] POST ${_dio.options.baseUrl}/api/v1/auth/register');
      final response = await _dio.post('/api/v1/auth/register', data: payload);
      if (response.statusCode == 201 && response.data != null) {
        final registered = UserProfile.fromJson(Map<String, dynamic>.from(response.data as Map));
        return RegisterArtisanSuccess(registered);
      }
      return RegisterArtisanFailure(
        message: 'Unexpected response (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final detail = e.response?.data is Map
          ? (e.response?.data as Map)['detail']?.toString()
          : null;
      final isConflict = statusCode == 409;
      debugPrint('[AuthRepository] registerArtisan failed ($statusCode): ${detail ?? e.message}');
      return RegisterArtisanFailure(
        message: detail ?? e.message ?? 'Registration failed',
        statusCode: statusCode,
        isConflict: isConflict,
      );
    } catch (e) {
      debugPrint('[AuthRepository] registerArtisan unexpected error: $e');
      return RegisterArtisanFailure(
        message: e.toString(),
        statusCode: null,
      );
    }
  }

  /// Requests login OTP from `/api/v1/auth/login`
  Future<RequestOtpResult> requestOtp(String phoneNumber) async {
    _syncBaseUrl();
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    try {
      debugPrint('[AuthRepository] POST ${_dio.options.baseUrl}/api/v1/auth/login');
      final response = await _dio.post('/api/v1/auth/login', data: {'phone': cleanPhone});
      if (response.statusCode == 200 && response.data != null) {
        final data = Map<String, dynamic>.from(response.data as Map);
        return RequestOtpSuccess(
          message: data['message'] as String? ?? 'OTP challenge issued successfully.',
          expiresInSeconds: (data['expires_in_seconds'] as num?)?.toInt() ?? 300,
          demoOtp: data['demo_otp'] as String?,
        );
      }
      return RequestOtpFailure(
        message: 'Unexpected response (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final detail = e.response?.data is Map
          ? (e.response?.data as Map)['detail']?.toString()
          : null;
      debugPrint('[AuthRepository] requestOtp failed ($statusCode): ${detail ?? e.message}');
      return RequestOtpFailure(
        message: detail ?? e.message ?? 'Failed to request OTP',
        statusCode: statusCode,
        isRateLimited: statusCode == 429,
        notFound: statusCode == 404,
      );
    } catch (e) {
      debugPrint('[AuthRepository] requestOtp unexpected error: $e');
      return RequestOtpFailure(
        message: e.toString(),
        statusCode: null,
      );
    }
  }

  /// Verifies OTP with backend `/api/v1/auth/verify-otp`
  Future<VerifyOtpResult> verifyOtpWithBackend(String phoneNumber, String otp) async {
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

        if (token == null || token.isEmpty || artisanMap == null) {
          return const VerifyOtpFailure(
            message: 'Server returned incomplete session data.',
            statusCode: 500,
          );
        }

        final profile = UserProfile.fromJson(artisanMap);
        await _tokenStorage.saveToken(token);
        return VerifyOtpSuccess(profile: profile, token: token);
      }
      return VerifyOtpFailure(
        message: 'Unexpected server response (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final detail = e.response?.data is Map
          ? (e.response?.data as Map)['detail']?.toString()
          : null;
      debugPrint('[AuthRepository] verifyOtpWithBackend failed ($statusCode): ${detail ?? e.message}');
      return VerifyOtpFailure(
        message: detail ?? e.message ?? 'Verification failed',
        statusCode: statusCode,
        isRateLimited: statusCode == 429,
      );
    } catch (e) {
      debugPrint('[AuthRepository] verifyOtpWithBackend unexpected error: $e');
      return VerifyOtpFailure(
        message: e.toString(),
        statusCode: null,
      );
    }
  }
}

// ── Typed Auth Operation Results ───────────────────────────────────────────

sealed class VerifyOtpResult {
  const VerifyOtpResult();
}

class VerifyOtpSuccess extends VerifyOtpResult {
  final UserProfile profile;
  final String token;
  const VerifyOtpSuccess({required this.profile, required this.token});
}

class VerifyOtpFailure extends VerifyOtpResult {
  final String message;
  final int? statusCode;
  final bool isRateLimited;
  const VerifyOtpFailure({required this.message, this.statusCode, this.isRateLimited = false});
}

sealed class RequestOtpResult {
  const RequestOtpResult();
}

class RequestOtpSuccess extends RequestOtpResult {
  final String message;
  final int expiresInSeconds;
  final String? demoOtp;
  const RequestOtpSuccess({required this.message, required this.expiresInSeconds, this.demoOtp});
}

class RequestOtpFailure extends RequestOtpResult {
  final String message;
  final int? statusCode;
  final bool isRateLimited;
  final bool notFound;
  const RequestOtpFailure({
    required this.message,
    this.statusCode,
    this.isRateLimited = false,
    this.notFound = false,
  });
}

sealed class RegisterArtisanResult {
  const RegisterArtisanResult();
}

class RegisterArtisanSuccess extends RegisterArtisanResult {
  final UserProfile profile;
  const RegisterArtisanSuccess(this.profile);
}

class RegisterArtisanFailure extends RegisterArtisanResult {
  final String message;
  final int? statusCode;
  final bool isConflict;
  const RegisterArtisanFailure({required this.message, this.statusCode, this.isConflict = false});
}
