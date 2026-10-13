import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/map_config.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/widgets/map_widgets.dart';
import '../../data/customer_repository.dart';

/// Online, approved, idle riders from `get_nearby_riders()` (sql/017),
/// refreshed every 20 s — the same cadence as the web's
/// startNearbyRidersWatch(). Positions are coarse (~110 m) by design.
final nearbyRidersProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final controller = StreamController<List<LatLng>>();

  Future<void> poll() async {
    try {
      controller.add(await repo.fetchNearbyRiders());
    } catch (e, s) {
      AppLog.warn('get_nearby_riders failed', e, s);
    }
  }

  poll();
  final timer = Timer.periodic(const Duration(seconds: 20), (_) => poll());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

class RidersNearYouMap extends ConsumerWidget {
  const RidersNearYouMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riders = ref.watch(nearbyRidersProvider).valueOrNull ?? const <LatLng>[];
    final center = riders.isNotEmpty ? riders.first : MapConfig.defaultCenter;
    final label = riders.isEmpty
        ? 'No riders online right now'
        : '${riders.length} rider${riders.length == 1 ? '' : 's'} nearby';

    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          FlutterMap(
            // Re-centre once the first riders arrive.
            key: ValueKey(riders.isEmpty),
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              minZoom: MapConfig.minZoom,
              maxZoom: MapConfig.maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              const OsmTileLayer(),
              MarkerLayer(
                markers: [
                  for (final loc in riders)
                    Marker(
                      point: loc,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: const Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const OsmAttribution(),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
