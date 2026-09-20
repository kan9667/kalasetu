import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/private_media_cache.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/auth_repository.dart';

/// Auth state model
class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final String? phoneNumber;
  final bool isLoading;
  final UserProfile? pendingRegistration;
  final String? authError;
  final String? demoOtp;
  final bool isNgoSimulation;

  const AuthState({
    this.isAuthenticated = false,
    this.userId,
    this.phoneNumber,
    this.isLoading = false,
    this.pendingRegistration,
    this.authError,
    this.demoOtp,
    this.isNgoSimulation = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    String? phoneNumber,
    bool? isLoading,
    UserProfile? Function()? pendingRegistration,
    String? authError,
    bool clearAuthError = false,
    String? demoOtp,
    bool clearDemoOtp = false,
    bool? isNgoSimulation,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isLoading: isLoading ?? this.isLoading,
      pendingRegistration: pendingRegistration != null ? pendingRegistration() : this.pendingRegistration,
      authError: clearAuthError ? null : (authError ?? this.authError),
      demoOtp: clearDemoOtp ? null : (demoOtp ?? this.demoOtp),
      isNgoSimulation: isNgoSimulation ?? this.isNgoSimulation,
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
    final isNgoSim = await _authRepository.isNgoSimulation();
    if (isNgoSim) {
      final simUserId = await _authRepository.getNgoUserId();
      if (!mounted) return;
      if (simUserId != null && simUserId.isNotEmpty) {
        PrivateMediaCache.instance.updateSession(accountId: simUserId);
      }
      state = state.copyWith(
        isAuthenticated: false,
        isNgoSimulation: true,
        userId: simUserId,
        phoneNumber: '',
      );
      return;
    }

    final isAuthenticated = await _authRepository.isAuthenticated();
    final userId = await _authRepository.getUserId();
    final phoneNumber = await _authRepository.getPhoneNumber();

    if (!mounted) return;

    if (isAuthenticated && userId != null && userId.isNotEmpty) {
      PrivateMediaCache.instance.updateSession(accountId: userId);
    }

    if (!mounted) return;

    state = state.copyWith(
      isAuthenticated: isAuthenticated,
      isNgoSimulation: false,
      userId: userId,
      phoneNumber: phoneNumber,
    );
  }

  Future<RequestOtpResult> signInWithPhone(String phoneNumber) async {
    state = state.copyWith(
      isLoading: true,
      authError: null,
      clearAuthError: true,
      pendingRegistration: () => null,
    );
    await _authRepository.savePhoneNumber(phoneNumber);
    final result = await _authRepository.requestOtp(phoneNumber);
    if (result is RequestOtpSuccess) {
      state = state.copyWith(
        phoneNumber: phoneNumber,
        isLoading: false,
        demoOtp: result.demoOtp,
      );
    } else if (result is RequestOtpFailure) {
      state = state.copyWith(
        isLoading: false,
        authError: result.message,
      );
    }
    return result;
  }

  Future<RequestOtpResult> registerWithDetails(UserProfile profile) async {
    state = state.copyWith(
      isLoading: true,
      authError: null,
      clearAuthError: true,
      pendingRegistration: () => profile,
      phoneNumber: profile.phone,
    );
    await _authRepository.savePhoneNumber(profile.phone);
    final regResult = await _authRepository.registerArtisan(profile);
    if (regResult is RegisterArtisanSuccess) {
      state = state.copyWith(pendingRegistration: () => regResult.profile);
    } else if (regResult is RegisterArtisanFailure) {
      if (!regResult.isConflict) {
        state = state.copyWith(
          isLoading: false,
          authError: regResult.message,
        );
        return RequestOtpFailure(
          message: regResult.message,
          statusCode: regResult.statusCode,
        );
      }
    }

    // Await registration, then request an OTP challenge before verification
    final otpResult = await _authRepository.requestOtp(profile.phone);
    if (otpResult is RequestOtpSuccess) {
      state = state.copyWith(
        isLoading: false,
        demoOtp: otpResult.demoOtp,
      );
    } else if (otpResult is RequestOtpFailure) {
      state = state.copyWith(
        isLoading: false,
        authError: otpResult.message,
      );
    }
    return otpResult;
  }

  Future<RequestOtpResult> resendOtp(String phoneNumber) async {
    state = state.copyWith(
      isLoading: true,
      authError: null,
      clearAuthError: true,
    );
    final result = await _authRepository.requestOtp(phoneNumber);
    if (result is RequestOtpSuccess) {
      state = state.copyWith(
        isLoading: false,
        demoOtp: result.demoOtp,
      );
    } else if (result is RequestOtpFailure) {
      state = state.copyWith(
        isLoading: false,
        authError: result.message,
      );
    }
    return result;
  }

  Future<bool> verifyOtp(String phoneNumber, String otp, {UserProfile? profileOverride}) async {
    state = state.copyWith(
      isLoading: true,
      authError: null,
      clearAuthError: true,
    );

    final effectivePhone = phoneNumber.trim();
    final cleanOtp = otp.trim();

    if (effectivePhone.isEmpty || cleanOtp.length != 6) {
      state = state.copyWith(
        isLoading: false,
        authError: 'Please enter a valid phone number and 6-digit verification code.',
      );
      return false;
    }

    final result = await _authRepository.verifyOtpWithBackend(effectivePhone, cleanOtp);

    if (result is VerifyOtpSuccess) {
      final profile = result.profile;
      final token = result.token;

      // Save to auth repository
      await _authRepository.saveAuthData(
        profile.id,
        effectivePhone,
        token: token,
      );

      // Persist to user_profile_box
      if (Hive.isBoxOpen('user_profile_box')) {
        final box = Hive.box<UserProfile>('user_profile_box');
        await box.put('current_profile', profile);
      }

      PrivateMediaCache.instance.updateSession(accountId: profile.id);

      state = state.copyWith(
        isAuthenticated: true,
        userId: profile.id,
        phoneNumber: effectivePhone,
        isLoading: false,
        pendingRegistration: () => null,
        clearAuthError: true,
        clearDemoOtp: true,
      );
      return true;
    }

    if (result is VerifyOtpFailure) {
      // INVARIANT: Never create fallback authenticated profiles on failure!
      state = state.copyWith(
        isLoading: false,
        authError: result.message,
      );
      return false;
    }

    state = state.copyWith(
      isLoading: false,
      authError: 'Unknown verification outcome',
    );
    return false;
  }

  Future<void> signInWithCoordinator(String coordinatorId) async {
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(seconds: 1));

    // NGO / coordinator simulation is explicitly flagged and separated from real bearer auth
    final userId = coordinatorId.isNotEmpty
        ? coordinatorId
        : 'ngo_sim_${DateTime.now().millisecondsSinceEpoch}';
    await _authRepository.saveNgoSimulationData(userId);
    PrivateMediaCache.instance.updateSession(accountId: userId);
    state = state.copyWith(
      isAuthenticated: false,
      userId: userId,
      phoneNumber: '',
      isLoading: false,
      pendingRegistration: () => null,
      isNgoSimulation: true,
    );
  }

  void expireSession() {
    PrivateMediaCache.instance.deactivateAccount();
    // INVARIANT: Preserve existing offline drafts when login fails or session expires!
    state = state.copyWith(
      isAuthenticated: false,
      isNgoSimulation: false,
      authError: 'Session expired. Please log in again.',
    );
  }

  Future<void> signOut() async {
    PrivateMediaCache.instance.deactivateAccount();
    if (state.isNgoSimulation) {
      await _authRepository.clearNgoSimulationData();
    } else {
      await _authRepository.clearAuthData();
    }
    // INVARIANT: Preserves draft_box offline drafts
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
