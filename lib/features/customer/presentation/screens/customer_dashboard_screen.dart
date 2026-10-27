import 'package:flutter/material.dart';
import '../../../../shared/widgets/liquid_glass_nav_bar.dart';
import '../../../../shared/widgets/account_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/app_alerts.dart';
import '../../../../core/services/last_place.dart';
import '../../../../core/services/push_service.dart';
import '../../../../core/supabase/realtime_refresh.dart';
import '../../../../shared/screens/profile_screen.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/customer_bookings_tab.dart';
import '../widgets/customer_home_tab.dart';
import '../widgets/notifications_tab.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../chat/presentation/screens/chat_screen.dart';
import '../../../chat/presentation/screens/messages_screen.dart';
import 'book_food_screen.dart';
import 'book_hauling_screen.dart';
import 'book_parcel_screen.dart';
import 'book_ride_screen.dart';

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
  /// Last tab written to LastPlace.
  int _savedIndex = 0;
  /// Bottom bar shrinks while the page scrolls down.
  bool _navCompact = false;

  static const _messagesTab = 2, _notificationsTab = 3, _profileTab = 4;
  static const _titles = ['Home', 'My Bookings', 'Messages', 'Notifications', 'Profile'];

  /// Stopped when the dashboard goes (log out) — ref can't be used in dispose.
  AppAlerts? _alerts;

  @override
  void dispose() {
    _alerts?.stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Phone notifications for booking updates while the app is in the background.
    _alerts = ref.read(appAlertsProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authNotifierProvider).profile?.id;
      if (mounted && userId != null) {
        _alerts?.start(userId: userId);
        _restorePlace(userId);
        // Push to this phone, even with the app closed (Firebase).
        ref.read(pushServiceProvider).register().then((ok) {
          _alerts?.pushActive = ok;
          // a tapped chat notification opens that chat (notifications.link)
          ref.read(pushServiceProvider).listenForTaps(_openLink);
        });
      }
    });
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
        ref.invalidate(unpaidFeesProvider);
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

  /// Android closed the app in the background: open the tab — and the
  /// booking screen — you were on (LastPlace; web: the #section in the address).
  Future<void> _restorePlace(String userId) async {
    final tab = await LastPlace.tab('customer', userId);
    if (!mounted) return;
    if (tab != null && tab > 0 && tab < _titles.length) setState(() => _index = _savedIndex = tab);
    final Widget? screen = switch (await LastPlace.openForm(userId)) {
      'ride' => const BookRideScreen(),
      'food' => const BookFoodScreen(),
      'parcel' => const BookParcelScreen(),
      'hauling' => const BookHaulingScreen(),
      _ => null,
    };
    if (screen != null && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }
  }

  void _openLink(String link) {
    final route = ChatScreen.forLink(link);
    if (route == null || !mounted) return;
    setState(() => _index = _messagesTab);
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    if (_index != _savedIndex && profile != null) {
      _savedIndex = _index;
      LastPlace.saveTab('customer', profile.id, _index);
    }
    final unreadAsync = ref.watch(unreadNotificationsProvider);

    final tabs = [
      const CustomerHomeTab(),
      const CustomerBookingsTab(),
      const MessagesView(),
      NotificationsTab(onOpenBookings: () => setState(() => _index = 1)),
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
                  // Profile picture → My profile, Dark mode, Log out.
                  AccountMenuButton(
                    onOpenProfile: () => setState(() => _index = _profileTab),
                    onOpenNotifications: () {
                      setState(() => _index = _notificationsTab);
                      ref.invalidate(unreadNotificationsProvider);
                    },
                    unread: unreadAsync.value ?? 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: LiquidNavScrollWatcher(
        onCompactChanged: (v) {
          if (v != _navCompact) setState(() => _navCompact = v);
        },
        child: SafeArea(top: false, child: tabs[_index]),
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        currentIndex: _index,
        compact: _navCompact,
        onTap: (i) {
          setState(() {
            _index = i;
            _navCompact = false;
          });
        },
        items: [
          const LiquidNavItem(icon: AppIcons.home, activeIcon: AppIcons.homeActive, label: 'Home'),
          // in progress, to pay, or to rate (web: the Booking history count)
          LiquidNavItem(
            icon: AppIcons.history,
            activeIcon: AppIcons.history,
            label: 'Bookings',
            badge: ref.watch(customerHomeSummaryProvider).valueOrNull?.needYouTotal ?? 0,
          ),
          LiquidNavItem(
            icon: AppIcons.messages,
            activeIcon: AppIcons.messagesActive,
            label: 'Messages',
            badge: ref.watch(unreadMessagesProvider),
          ),
          // Notifications and Profile open from the profile picture at the top
        ],
      ),
    );
  }
}
