import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/auth_repository.dart';

/// Auth state model
class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final String? phoneNumber;
  final bool isLoading;
  final UserProfile? pendingRegistration;

  const AuthState({
    this.isAuthenticated = false,
    this.userId,
    this.phoneNumber,
    this.isLoading = false,
    this.pendingRegistration,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    String? phoneNumber,
    bool? isLoading,
    UserProfile? Function()? pendingRegistration,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isLoading: isLoading ?? this.isLoading,
      pendingRegistration: pendingRegistration != null ? pendingRegistration() : this.pendingRegistration,
    );
  }
}

/// Auth state notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;

  AuthNotifier(this._authRepository) : super(const AuthState()) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final isAuthenticated = await _authRepository.isAuthenticated();
    final userId = await _authRepository.getUserId();
    final phoneNumber = await _authRepository.getPhoneNumber();

    state = state.copyWith(
      isAuthenticated: isAuthenticated,
      userId: userId,
      phoneNumber: phoneNumber,
    );
  }

  Future<void> signInWithPhone(String phoneNumber) async {
    state = state.copyWith(
      isLoading: true,
      pendingRegistration: () => null,
    );
    await _authRepository.savePhoneNumber(phoneNumber);
    // Request OTP from backend (if server is reachable)
    await _authRepository.requestOtp(phoneNumber);
    state = state.copyWith(
      phoneNumber: phoneNumber,
      isLoading: false,
    );
  }

  Future<void> registerWithDetails(UserProfile profile) async {
    state = state.copyWith(
      isLoading: true,
      pendingRegistration: () => profile,
      phoneNumber: profile.phone,
    );
    await _authRepository.savePhoneNumber(profile.phone);
    // Attempt registration on backend
    final backendProfile = await _authRepository.registerArtisan(profile);
    if (backendProfile != null) {
      state = state.copyWith(pendingRegistration: () => backendProfile);
    }
    state = state.copyWith(isLoading: false);
  }

  Future<bool> verifyOtp(String phoneNumber, String otp, {UserProfile? profileOverride}) async {
    state = state.copyWith(isLoading: true);

    final effectivePhone = phoneNumber.isEmpty ? '9876543210' : phoneNumber;
    final registrationProfile = profileOverride ?? state.pendingRegistration;

    // 1. If registering and not yet assigned a backend ID, attempt registration
    if (registrationProfile != null && registrationProfile.id.isEmpty) {
      final regResult = await _authRepository.registerArtisan(registrationProfile);
      if (regResult != null) {
        state = state.copyWith(pendingRegistration: () => regResult);
      }
    }

    // 2. Call backend /api/v1/auth/verify-otp
    final (backendProfile, token) = await _authRepository.verifyOtpWithBackend(effectivePhone, otp);

    // 3. Resolve profile: backend response > pending registration > local fallback
    final resolvedProfile = backendProfile ??
        (registrationProfile != null
            ? registrationProfile.copyWith(
                id: registrationProfile.id.isNotEmpty
                    ? registrationProfile.id
                    : 'artisan_${DateTime.now().millisecondsSinceEpoch}',
                phone: effectivePhone,
              )
            : UserProfile(
                id: 'artisan_${DateTime.now().millisecondsSinceEpoch}',
                name: 'Artisan',
                phone: effectivePhone,
                craftType: 'Handicraft',
                locationCluster: 'Rural Cluster',
                preferredLanguage: 'en',
              ));

    // 4. Save to auth repository
    await _authRepository.saveAuthData(
      resolvedProfile.id,
      effectivePhone,
      token: token,
    );

    // 5. Persist to Hive user_profile_box as active profile
    if (Hive.isBoxOpen('user_profile_box')) {
      final box = Hive.box<UserProfile>('user_profile_box');
      await box.put('current_profile', resolvedProfile);
    }

    state = state.copyWith(
      isAuthenticated: true,
      userId: resolvedProfile.id,
      phoneNumber: effectivePhone,
      isLoading: false,
      pendingRegistration: () => null,
    );
    return true;
  }

  Future<void> signInWithCoordinator(String coordinatorId) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));

    final userId = 'artisan_ngo_${DateTime.now().millisecondsSinceEpoch}';
    await _authRepository.saveAuthData(userId, '');
    state = state.copyWith(
      isAuthenticated: true,
      userId: userId,
      phoneNumber: '',
      isLoading: false,
      pendingRegistration: () => null,
    );
  }

  Future<void> signOut() async {
    await _authRepository.clearAuthData();
    state = const AuthState();
  }
}

/// Provider for auth repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Provider for auth state
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
