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
    await Future.delayed(const Duration(milliseconds: 500));
    await _authRepository.savePhoneNumber(phoneNumber);
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
    await Future.delayed(const Duration(milliseconds: 500));
    await _authRepository.savePhoneNumber(profile.phone);
    state = state.copyWith(isLoading: false);
  }

  Future<bool> verifyOtp(String phoneNumber, String otp, {UserProfile? profileOverride}) async {
    state = state.copyWith(isLoading: true);
    // Mock: accept any OTP in demo mode
    await Future.delayed(const Duration(milliseconds: 500));

    final effectivePhone = phoneNumber.isEmpty ? '9876543210' : phoneNumber;
    final userId = 'artisan_${DateTime.now().millisecondsSinceEpoch}';
    await _authRepository.saveAuthData(userId, effectivePhone);

    final registrationProfile = profileOverride ?? state.pendingRegistration;
    if (registrationProfile != null) {
      final finalProfile = registrationProfile.copyWith(
        id: userId,
        phone: effectivePhone,
      );
      if (Hive.isBoxOpen('user_profile_box')) {
        final box = Hive.box<UserProfile>('user_profile_box');
        await box.put('current_profile', finalProfile);
      }
    }

    state = state.copyWith(
      isAuthenticated: true,
      userId: userId,
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
