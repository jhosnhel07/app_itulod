import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/screens/profile_screen.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/rider_earnings_tab.dart';
import '../widgets/rider_history_tab.dart';
import '../widgets/rider_requests_tab.dart';
import '../widgets/rider_trip_tab.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    final application = ref.watch(authNotifierProvider).riderApplication;
    final approved = application?.status == ApplicationStatus.approved;

    final tabs = [
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
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            boxShadow: AppColors.cardShadow,
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: Row(
                children: [
                  AvatarWidget(
                    name: profile?.fullName ?? 'Rider',
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
                  if (application != null)
                    StatusBadge(status: application.status.name),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!approved) _approvalBanner(),
          Expanded(child: SafeArea(top: false, child: tabs[_index])),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: 'Trip',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments_rounded),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
        ),
      ),
    );
  }

  Widget _approvalBanner() {
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
            child: const Icon(Icons.hourglass_top_rounded,
                color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your application is pending admin approval — you can browse but not accept bookings yet.',
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
      if (application.vehicleType.isNotEmpty) MapEntry('Vehicle type', application.vehicleType),
      if (application.vehiclePlate != null && application.vehiclePlate!.isNotEmpty)
        MapEntry('Plate number', application.vehiclePlate!),
      if (application.vehicleModel != null && application.vehicleModel!.isNotEmpty)
        MapEntry('Model', application.vehicleModel!),
      if (application.licenseNumber != null && application.licenseNumber!.isNotEmpty)
        MapEntry('License no.', application.licenseNumber!),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
                    Expanded(child: Text(row.value, style: AppTypography.bodyMedium.copyWith(fontSize: 13))),
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
