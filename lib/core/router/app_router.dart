import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/rider_under_review_screen.dart';
import '../../features/customer/presentation/screens/customer_dashboard_screen.dart';
import '../../features/customer/presentation/screens/saved_addresses_screen.dart';
import '../../features/customer/presentation/screens/wallet_screen.dart';
import '../../features/promos/presentation/screens/referrals_screen.dart';
import '../../features/rider/presentation/screens/rider_dashboard_screen.dart';
import '../../shared/models/profile_model.dart';
import '../../shared/models/rider_application_model.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authListenable = _AuthStateListenable(ref);
  ref.onDispose(authListenable.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authListenable,
    redirect: (context, state) {
      // Read, never watch: watching would rebuild this provider on every auth
      // change, handing MaterialApp.router a brand new GoRouter and resetting
      // the navigation stack to initialLocation. refreshListenable already
      // re-runs this redirect when auth state changes.
      final authState = ref.read(authNotifierProvider);
      final isAuth = authState.isAuthenticated;
      final profile = authState.profile;
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';

      // 0. The register wizard owns its own exit. Signing up a rider creates a
      // real session while the documents upload, and signing up a customer
      // flips auth state twice — redirecting on either would drop the user out
      // of the form before the success panel shows. The wizard sends the user
      // to /login itself when it is done.
      if (isRegistering) {
        return null;
      }

      // 1. Not Authenticated
      if (!isAuth) {
        if (isLoggingIn) {
          return null;
        }
        return '/login';
      }

      // 2. Authenticated - Check role and route guards
      final role = profile?.role ?? UserRole.customer;

      if (role == UserRole.admin) {
        if (isLoggingIn || !state.matchedLocation.startsWith('/admin')) {
          return '/admin/dashboard';
        }
        return null;
      }

      if (role == UserRole.rider) {
        final application = authState.riderApplication;
        final isApproved = application?.status == ApplicationStatus.approved;

        if (!isApproved) {
          if (state.matchedLocation != '/rider/application-status') {
            return '/rider/application-status';
          }
          return null;
        }

        if (isLoggingIn || state.matchedLocation == '/rider/application-status' || !state.matchedLocation.startsWith('/rider')) {
          return '/rider/home';
        }
        return null;
      }

      // Customer
      if (role == UserRole.customer) {
        if (isLoggingIn || !state.matchedLocation.startsWith('/customer')) {
          return '/customer/home';
        }
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/customer/home',
        builder: (context, state) => const CustomerDashboardScreen(),
      ),
      GoRoute(
        path: '/rider/home',
        builder: (context, state) => const RiderDashboardScreen(),
      ),
      GoRoute(
        path: '/rider/application-status',
        builder: (context, state) => const RiderUnderReviewScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/customer/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/customer/saved-addresses',
        builder: (context, state) => const SavedAddressesScreen(),
      ),
      GoRoute(
        path: '/customer/referrals',
        builder: (context, state) => const ReferralsScreen(),
      ),
    ],
  );
});

class _AuthStateListenable extends ChangeNotifier {
  bool _disposed = false;

  _AuthStateListenable(Ref ref) {
    ref.listen<AppAuthState>(
      authNotifierProvider,
      (_, __) {
        if (!_disposed) notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
