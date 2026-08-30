import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/auth_repository.dart';

/// Auth state model
class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final String? phoneNumber;
  final bool isLoading;

  const AuthState({
    this.isAuthenticated = false,
    this.userId,
    this.phoneNumber,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    String? phoneNumber,
    bool? isLoading,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isLoading: isLoading ?? this.isLoading,
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
    state = state.copyWith(isLoading: true);
    // Mock: in real implementation, this would call the auth service
    await Future.delayed(const Duration(seconds: 1));
    await _authRepository.savePhoneNumber(phoneNumber);
    state = state.copyWith(isLoading: false);
  }

  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    state = state.copyWith(isLoading: true);
    // Mock: accept any OTP in demo mode
    await Future.delayed(const Duration(milliseconds: 500));

    final effectivePhone = phoneNumber.isEmpty ? '9876543210' : phoneNumber;
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await _authRepository.saveAuthData(userId, effectivePhone);
    state = state.copyWith(
      isAuthenticated: true,
      userId: userId,
      phoneNumber: effectivePhone,
      isLoading: false,
    );
    return true;
  }

  Future<void> signInWithCoordinator(String coordinatorId) async {
    state = state.copyWith(isLoading: true);
    // Mock: a real implementation would validate coordinatorId against an
    // NGO-coordinator backend and link the artisan's account through them.
    await Future.delayed(const Duration(seconds: 1));

    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await _authRepository.saveAuthData(userId, ''); // no phone captured in assisted flow
    state = state.copyWith(
      isAuthenticated: true,
      userId: userId,
      phoneNumber: '',
      isLoading: false,
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
