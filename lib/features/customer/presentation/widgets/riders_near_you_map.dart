import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/map_config.dart';

final onlineRidersProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final supabase = Supabase.instance.client;
  return supabase.from('online_riders').stream(primaryKey: ['rider_id']).map((rows) {
    return rows.map((r) => LatLng(r['lat'] as double, r['lng'] as double)).toList();
  });
});

class RidersNearYouMap extends ConsumerWidget {
  const RidersNearYouMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridersAsync = ref.watch(onlineRidersProvider);

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
            options: MapOptions(
              // Center on a default location, e.g. Manila, or use a Geolocator plugin if available
              initialCenter: const LatLng(14.5995, 120.9842), 
              initialZoom: 13,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: MapConfig.tileUrl,
                userAgentPackageName: MapConfig.userAgentPackageName,
              ),
              if (ridersAsync.hasValue)
                MarkerLayer(
                  markers: ridersAsync.value!.map((loc) {
                    return Marker(
                      point: loc,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.two_wheeler_rounded, size: 18, color: Colors.blue),
                      ),
                    );
                  }).toList(),
                ),
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
                  const Icon(Icons.radar_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    '${ridersAsync.valueOrNull?.length ?? 0} riders nearby',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
