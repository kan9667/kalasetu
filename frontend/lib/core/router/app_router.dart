import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_route_constants.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/sign_in_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/home/screens/home_shell.dart';
import '../../features/catalogue/screens/catalogue_screen.dart';
import '../../features/catalogue/screens/product_detail_screen.dart';
import '../../features/add_product/screens/add_product_flow_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/language_settings_screen.dart';
import '../../features/profile/screens/my_stats_screen.dart';
import '../../features/auth/providers/auth_provider.dart';

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authStateProvider,
      (_, _) => notifyListeners(),
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
      final isOnSplash = state.matchedLocation == '/splash';
      final isOnAuth = state.matchedLocation == '/sign-in' ||
                       state.matchedLocation == '/otp';

      // Splash screen is always accessible initially
      if (isOnSplash) return null;

      // If not authenticated and not on auth screens, redirect to sign in
      if (!isAuthenticated && !isOnAuth) {
        return '/sign-in';
      }

      // If authenticated and on auth screens, redirect to home
      if (isAuthenticated && isOnAuth) {
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
        path: '/sign-in',
        name: AppRouteConstants.signIn,
        builder: (context, state) => const SignInScreen(),
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
