import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;
import '../../../../core/supabase/supabase_client.dart';
import '../../../../shared/widgets/liquid_glass_nav_bar.dart';
import '../../../../shared/widgets/account_menu_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/supabase/realtime_refresh.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/screens/profile_screen.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/rider_earnings_tab.dart';
import '../widgets/rider_history_tab.dart';
import '../widgets/rider_home_tab.dart';
import '../widgets/rider_requests_tab.dart';
import '../widgets/rider_trip_tab.dart';
import '../../../../shared/models/booking_models.dart';
import '../../data/rider_location_broadcaster.dart';
import '../../data/rider_repository.dart';
import '../../../customer/presentation/widgets/notifications_tab.dart';
import '../../../../core/services/app_alerts.dart';
import '../../../../core/services/push_service.dart';

final riderOnlineStatusProvider = StateNotifierProvider<RiderOnlineNotifier, AsyncValue<bool>>((ref) {
  // Only the id matters — profile edits (synced live) must not rebuild this.
  final riderId = ref.watch(authNotifierProvider.select((s) => s.profile?.id));
  if (riderId == null) return RiderOnlineNotifier(null, null, null);
  return RiderOnlineNotifier(
    ref.read(riderRepositoryProvider),
    ref.read(riderLocationBroadcasterProvider),
    riderId,
  );
});

/// "Go online" = start sharing GPS so customers see this rider in "riders
/// near you" (the row needs real coordinates — `is_online` alone does
/// nothing). Mirrors the web's wireOnlineToggle()/initOnlineStatus().
class RiderOnlineNotifier extends StateNotifier<AsyncValue<bool>> {
  final RiderRepository? _repo;
  final RiderLocationBroadcaster? _broadcaster;
  final String? _riderId;

  RiderOnlineNotifier(this._repo, this._broadcaster, this._riderId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  /// Online status is shared with the web (rider_locations.is_online). Only
  /// the device where the rider tapped Online sends GPS; this remembers
  /// whether that was this phone, so a restart resumes sending only here and
  /// the web's location isn't fought by a second one (web: onlineHere()).
  static const _onlineHereKey = 'itulod-online-here';
  RealtimeChannel? _channel;

  Future<bool> _isOnlineHere(String riderId) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_onlineHereKey) == riderId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setOnlineHere(String riderId, bool here) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (here) {
        await prefs.setString(_onlineHereKey, riderId);
      } else {
        await prefs.remove(_onlineHereKey);
      }
    } catch (_) {/* best effort */}
  }

  Future<void> _load() async {
    final repo = _repo, broadcaster = _broadcaster, riderId = _riderId;
    if (repo == null || broadcaster == null || riderId == null) {
      state = const AsyncValue.data(false);
      return;
    }
    _watch(riderId);
    final wasOnline = await repo.fetchOnlineStatus(riderId);
    if (!wasOnline) {
      await _setOnlineHere(riderId, false);
      if (mounted) state = const AsyncValue.data(false);
      return;
    }
    if (!await _isOnlineHere(riderId)) {
      // Online from the web: show it, but let that device keep sending GPS.
      if (mounted) state = const AsyncValue.data(true);
      return;
    }
    // Resume broadcasting after an app restart, like the web on reload.
    final problem = await broadcaster.goOnline(riderId);
    if (problem != null) {
      await broadcaster.goOffline(riderId);
      await _setOnlineHere(riderId, false);
    }
    if (mounted) state = AsyncValue.data(problem == null);
  }

  /// Follow online/offline changes made on the web (or another phone) live.
  void _watch(String riderId) {
    if (_channel != null) return;
    _channel = SupabaseConfig.client
        .channel('rider-online-$riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rider_locations',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'rider_id', value: riderId),
          callback: (payload) async {
            final bool online;
            if (payload.eventType == PostgresChangeEvent.delete) {
              online = await _repo?.fetchOnlineStatus(riderId) ?? false;
            } else {
              online = payload.newRecord['is_online'] == true;
            }
            if (!mounted || state.valueOrNull == online) return;
            if (!online) {
              // Went offline elsewhere: stop sending from here without writing.
              _broadcaster?.stopPresenceLocally();
              await _setOnlineHere(riderId, false);
            }
            if (mounted) state = AsyncValue.data(online);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    _channel = null;
    if (channel != null) SupabaseConfig.client.removeChannel(channel);
    super.dispose();
  }

  /// Returns a user-facing error when going online failed.
  Future<String?> setOnline(bool isOnline) async {
    final broadcaster = _broadcaster, riderId = _riderId;
    if (broadcaster == null || riderId == null) return null;
    if (!isOnline) {
      state = const AsyncValue.data(false);
      await _setOnlineHere(riderId, false);
      await broadcaster.goOffline(riderId);
      return null;
    }
    state = const AsyncValue.data(true);
    await _setOnlineHere(riderId, true);
    final problem = await broadcaster.goOnline(riderId);
    if (problem != null) {
      await _setOnlineHere(riderId, false);
      if (mounted) state = const AsyncValue.data(false);
    }
    return problem;
  }
}

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() =>
      _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen>
    with RealtimeRefreshMixin {
  int _index = 0;
  /// Bottom bar shrinks while the page scrolls down.
  bool _navCompact = false;

  static const _requestsTab = 1;
  static const _tripTab = 2;

  static const _historyTab = 4;

  /// The same Notifications screen as the customer's (web: the rider
  /// dashboard's Notifications tab): tap one to read it, unread until opened.
  void _openNotifications(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Notifications')),
        body: NotificationsTab(
          onOpenBookings: () {
            navigator.pop();
            if (mounted) setState(() => _index = _historyTab);
          },
        ),
      ),
    )).then((_) {
      if (mounted) ref.invalidate(unreadNotificationsProvider);
    });
  }

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
    // Phone notifications: booking updates and new job requests (sent to
    // Online riders with the matching vehicle — web sql/037). Firebase push
    // when available (works with the app closed), else AppAlerts while the
    // app runs in the background.
    final alerts = ref.read(appAlertsProvider);
    _alerts = alerts;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authNotifierProvider).profile?.id;
      if (mounted && userId != null) {
        alerts.start(userId: userId);
        ref.read(pushServiceProvider).register().then((ok) => alerts.pushActive = ok);
      }
    });
    // Live GPS to the customer while a job is accepted/ongoing — the web's
    // startLocationBroadcast() in loadAccepted().
    ref.listenManual<AsyncValue<List<BookingBase>>>(
      riderActiveBookingsProvider,
      (_, next) {
        final riderId = ref.read(authNotifierProvider).profile?.id;
        if (riderId == null || !next.hasValue) return;
        final active = next.value!;
        final primary = active.isEmpty
            ? null
            : active.firstWhere((b) => b.status == 'ongoing', orElse: () => active.first);
        ref.read(riderLocationBroadcasterProvider).setActiveJob(riderId, primary);
      },
      fireImmediately: true,
    );
    startRealtime(
      channelName: 'rider-dashboard',
      tables: const [
        'transport_bookings',
        'food_deliveries',
        'parcel_deliveries',
        'hauling_bookings',
        'payments',
        'notifications',
      ],
      onChange: () {
        ref.invalidate(riderHomeSnapshotProvider);
        ref.invalidate(riderRequestsProvider);
        ref.invalidate(riderActiveBookingsProvider);
        ref.invalidate(riderEarningsProvider);
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadNotificationsProvider);
      },
    );
    // Automatic booking expiration: catches anything the 15-minute grace
    // period has already caught up with the instant this dashboard opens,
    // then keeps re-checking every minute while it's open.
    startExpirySweep(
      onChange: () {
        ref.invalidate(riderHomeSnapshotProvider);
        ref.invalidate(riderRequestsProvider);
        ref.invalidate(riderActiveBookingsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    final application = ref.watch(authNotifierProvider).riderApplication;
    final approved = application?.status == ApplicationStatus.approved;
    final onlineAsync = ref.watch(riderOnlineStatusProvider);
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    final tabs = [
      RiderHomeTab(
        onGoToTab: (i) => setState(() => _index = i),
        requestsTabIndex: _requestsTab,
        tripTabIndex: _tripTab,
      ),
      const RiderRequestsTab(),
      const RiderTripTab(),
      const RiderEarningsTab(),
      const RiderHistoryTab(),
      Column(
        children: [
          if (application != null) _VehicleInfoCard(application: application),
          const Expanded(child: ProfileScreen()),
        ],
      ),
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
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.fullName ?? 'Rider Partner',
                          style: AppTypography.bodyBold
                              .copyWith(color: Colors.white, fontSize: 15.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('iTULOD Rider',
                            style: AppTypography.caption
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: unread > 0 ? 'Notifications ($unread unread)' : 'Notifications',
                    onPressed: () => _openNotifications(context),
                    icon: Badge.count(
                      count: unread,
                      isLabelVisible: unread > 0,
                      child: const Icon(Icons.notifications_rounded, color: Colors.white),
                    ),
                  ),
                  // Profile picture → My profile, Dark mode, Log out.
                  AccountMenuButton(onOpenProfile: () => setState(() => _index = 5)),
                  if (approved) ...[
                    Text(
                      onlineAsync.valueOrNull == true ? 'Online' : 'Offline',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: onlineAsync.valueOrNull == true ? AppColors.success : Colors.white70,
                      ),
                    ),
                    Switch(
                      value: onlineAsync.valueOrNull ?? false,
                      onChanged: (val) async {
                        final messenger = ScaffoldMessenger.of(context);
                        final problem = await ref
                            .read(riderOnlineStatusProvider.notifier)
                            .setOnline(val);
                        if (problem != null) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(problem),
                            backgroundColor: AppColors.danger,
                          ));
                        }
                      },
                      activeThumbColor: AppColors.success,
                      activeTrackColor: Colors.white24,
                      inactiveTrackColor: Colors.white12,
                    ),
                  ] else if (application != null) ...[
                    StatusBadge(status: application.status.name),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!approved) _approvalBanner(application?.status),
          Expanded(
            child: LiquidNavScrollWatcher(
              onCompactChanged: (v) {
                if (v != _navCompact) setState(() => _navCompact = v);
              },
              child: SafeArea(top: false, child: tabs[_index]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        currentIndex: _index,
        compact: _navCompact,
        labelsOnlyWhenSelected: true,
        onTap: (i) => setState(() {
          _index = i;
          _navCompact = false;
        }),
        items: const [
          LiquidNavItem(icon: AppIcons.home, activeIcon: AppIcons.homeActive, label: 'Home'),
          LiquidNavItem(icon: AppIcons.requests, activeIcon: AppIcons.requests, label: 'Requests'),
          LiquidNavItem(icon: AppIcons.trip, activeIcon: AppIcons.trip, label: 'Trip'),
          LiquidNavItem(icon: AppIcons.earnings, activeIcon: AppIcons.earnings, label: 'Earnings'),
          LiquidNavItem(icon: AppIcons.history, activeIcon: AppIcons.history, label: 'History'),
          LiquidNavItem(icon: AppIcons.profile, activeIcon: AppIcons.profileActive, label: 'Profile'),
        ],
      ),
    );
  }

  Widget _approvalBanner(ApplicationStatus? status) {
    final rejected = status == ApplicationStatus.rejected;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(rejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded,
                color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rejected
                  ? 'Your application was rejected. Contact support if you think this was a mistake.'
                  : 'Your application is pending admin approval — you can browse but not accept bookings yet.',
              style: AppTypography.captionDark.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoCard extends StatelessWidget {
  final RiderApplicationModel application;

  const _VehicleInfoCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Status', application.status.name),
      if (application.vehicleType.isNotEmpty)
        MapEntry('Vehicle type', application.vehicleType),
      if (application.vehiclePlate != null &&
          application.vehiclePlate!.isNotEmpty)
        MapEntry('Plate number', application.vehiclePlate!),
      if (application.vehicleModel != null &&
          application.vehicleModel!.isNotEmpty)
        MapEntry('Model', application.vehicleModel!),
      if (application.licenseNumber != null &&
          application.licenseNumber!.isNotEmpty)
        MapEntry('License no.', application.licenseNumber!),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.two_wheeler_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('My Vehicle', style: AppTypography.bodyBold),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(row.key, style: AppTypography.captionDark),
                    ),
                    Expanded(
                        child: Text(row.value,
                            style: AppTypography.bodyMedium
                                .copyWith(fontSize: 13))),
                  ],
                ),
              )),
          if (application.notes != null && application.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Admin note: ${application.notes}',
                  style: AppTypography.captionDark.copyWith(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
