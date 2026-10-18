import 'package:flutter/material.dart';
import '../../../../shared/widgets/theme_toggle_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/supabase/realtime_refresh.dart';
import '../../../../shared/screens/profile_screen.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/customer_bookings_tab.dart';
import '../widgets/customer_home_tab.dart';
import '../widgets/notifications_tab.dart';

class CustomerDashboardScreen extends ConsumerStatefulWidget {
  const CustomerDashboardScreen({super.key});

  @override
  ConsumerState<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState
    extends ConsumerState<CustomerDashboardScreen>
    with RealtimeRefreshMixin {
  int _index = 0;

  static const _titles = ['Home', 'My Bookings', 'Notifications', 'Profile'];

  @override
  void initState() {
    super.initState();
    startRealtime(
      channelName: 'customer-dashboard',
      tables: const [
        'transport_bookings',
        'food_deliveries',
        'parcel_deliveries',
        'hauling_bookings',
        'notifications',
      ],
      onChange: () {
        ref.invalidate(customerHomeSummaryProvider);
        ref.invalidate(customerHistoryProvider);
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadNotificationsProvider);
      },
    );
    // Automatic booking expiration: catches anything the 15-minute grace
    // period has already caught up with the instant this dashboard opens,
    // then keeps re-checking every minute while it's open.
    startExpirySweep(
      onChange: () {
        ref.invalidate(customerHomeSummaryProvider);
        ref.invalidate(customerHistoryProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    final unreadAsync = ref.watch(unreadNotificationsProvider);

    final tabs = [
      const CustomerHomeTab(),
      const CustomerBookingsTab(),
      const NotificationsTab(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            boxShadow: AppColors.cardShadow,
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  AvatarWidget(
                    name: profile?.fullName ?? 'Customer',
                    url: profile?.avatarUrl,
                    radius: 18,
                    ring: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _index == 0
                              ? 'Hi, ${(profile?.fullName ?? 'there').split(' ').first} 👋'
                              : _titles[_index],
                          style: AppTypography.bodyBold
                              .copyWith(color: Colors.white, fontSize: 15.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'iTULOD Customer',
                          style: AppTypography.caption
                              .copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const ThemeToggleButton(color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(top: false, child: tabs[_index]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            if (i == 2) ref.invalidate(unreadNotificationsProvider);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: (unreadAsync.value ?? 0) > 0,
                label: Text('${unreadAsync.value ?? 0}'),
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: const Icon(Icons.notifications_rounded),
              label: 'Notifications',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
