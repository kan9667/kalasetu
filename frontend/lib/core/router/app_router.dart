import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_route_constants.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/language_screen.dart';
import '../../features/auth/screens/sign_in_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/ngo_auth_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/home/screens/home_shell.dart';
import '../../features/catalogue/screens/catalogue_screen.dart';
import '../../features/catalogue/screens/product_detail_screen.dart';
import '../../features/add_product/screens/add_product_flow_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/language_settings_screen.dart';
import '../../features/profile/screens/my_stats_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../providers/app_providers.dart';

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authStateProvider,
      (previous, next) {
        final justLoggedIn = previous?.isAuthenticated != true && next.isAuthenticated;
        if (justLoggedIn) {
          _ref.read(homeTabIndexProvider.notifier).state = 1;
        }
        notifyListeners();
      },
    );
    _ref.listen<bool>(
      hasSelectedLanguageProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isAuthenticated = authState.isAuthenticated;
      final hasLanguage = ref.read(hasSelectedLanguageProvider);

      final isOnSplash = state.matchedLocation == '/splash';
      final isOnLanguage = state.matchedLocation == '/language';
      final isOnAuth = state.matchedLocation == '/sign-in' ||
                        state.matchedLocation == '/register' ||
                        state.matchedLocation == '/otp' ||
                        state.matchedLocation == '/ngo-auth';

      if (isOnSplash) return null;

      // Step 1: language must be selected before anything else. While it's
      // missing, the ONLY valid place to be is /language — this must be
      // resolved before we even look at auth state, otherwise the auth
      // check below will bounce us straight back off of /language.
      if (!hasLanguage) {
        return isOnLanguage ? null : '/language';
      }

      // Step 2: language is selected — don't let the user linger on the
      // language screen.
      if (isOnLanguage) {
        return isAuthenticated ? '/home' : '/sign-in';
      }

      // Step 3: must be authenticated for everything except the auth screens.
      if (!isAuthenticated) {
        return isOnAuth ? null : '/sign-in';
      }

      // Step 4: authenticated users shouldn't sit on auth screens.
      if (isOnAuth) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: AppRouteConstants.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/language',
        name: AppRouteConstants.language,
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        name: AppRouteConstants.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/register',
        name: AppRouteConstants.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/ngo-auth',
        name: AppRouteConstants.ngoAuth,
        builder: (context, state) => const NgoAuthScreen(),
      ),
      GoRoute(
        path: '/otp',
        name: AppRouteConstants.otp,
        builder: (context, state) {
          final phoneNumber = state.uri.queryParameters['phone'] ?? '';
          return OtpScreen(phoneNumber: phoneNumber);
        },
      ),
      GoRoute(
        path: '/home',
        name: AppRouteConstants.home,
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/catalogue',
        name: AppRouteConstants.catalogue,
        builder: (context, state) => const CatalogueScreen(),
      ),
      GoRoute(
        path: '/add-product',
        name: AppRouteConstants.addProduct,
        builder: (context, state) => const AddProductFlowScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: AppRouteConstants.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        name: AppRouteConstants.productDetail,
        builder: (context, state) {
          final productId = state.pathParameters['id'] ?? '';
          return ProductDetailScreen(productId: productId);
        },
      ),
      GoRoute(
        path: '/language-settings',
        name: AppRouteConstants.languageSettings,
        builder: (context, state) => const LanguageSettingsScreen(),
      ),
      GoRoute(
        path: '/my-stats',
        name: AppRouteConstants.myStats,
        builder: (context, state) => const MyStatsScreen(),
      ),
    ],
  );
});