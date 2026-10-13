import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/restaurant_models.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/restaurant_finder.dart';
import '../../data/restaurant_repository.dart';
import '../providers/cart_provider.dart';
import '../providers/saved_addresses_provider.dart';
import 'map_picker_screen.dart';
import 'restaurant_menu_screen.dart';

/// "Choose a restaurant" — 200+ places across Ilocos Norte, narrowed by
/// Deliver to (nearest first, with distance + delivery fee), town,
/// category chips, and a search that also matches dishes. Mirrors the web's
/// js/restaurant-finder.js.
class BookFoodScreen extends ConsumerStatefulWidget {
  const BookFoodScreen({super.key});

  @override
  ConsumerState<BookFoodScreen> createState() => _BookFoodScreenState();
}

class _Entry {
  final RestaurantModel r;
  final String town;
  final Set<String> cats;

  _Entry(this.r) : town = restaurantTown(r), cats = restaurantCategories(r);
}

class _BookFoodScreenState extends ConsumerState<BookFoodScreen> {
  List<_Entry>? _entries;
  Map<String, List<String>> _dishes = const {};
  bool _isLoading = true;
  String _query = '';
  String _town = 'all';
  String _category = 'all';
  /// Customer chose "Anywhere" — don't auto-pick a saved address again.
  bool _anywhere = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(restaurantRepositoryProvider);
    try {
      final restaurants = await repo.getRestaurants();
      if (!mounted) return;
      setState(() {
        _entries = restaurants.map(_Entry.new).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading restaurants: $e')),
      );
      return;
    }
    try {
      final dishes = await repo.getDishIndex();
      if (mounted) setState(() => _dishes = dishes);
    } catch (_) {
      // Dish search is a bonus; name/town search still works without it.
    }
  }

  // ── Deliver to ────────────────────────────────────────────────────────

  PickedPlace? _deliverTo() {
    final chosen = ref.watch(foodDeliverToProvider);
    if (chosen != null || _anywhere) return chosen;
    // Default: the first saved address that has a map pin.
    final saved = ref.watch(savedAddressesProvider).valueOrNull ?? const [];
    for (final a in saved) {
      if (a.hasLocation) return PickedPlace(point: a.point, address: a.address);
    }
    return null;
  }

  void _setDeliverTo(PickedPlace? place) {
    setState(() => _anywhere = place == null);
    ref.read(foodDeliverToProvider.notifier).state = place;
  }

  Future<void> _chooseDeliverTo() async {
    final saved = (ref.read(savedAddressesProvider).valueOrNull ?? const [])
        .where((a) => a.hasLocation)
        .toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('Deliver to', style: AppTypography.h3)),
            for (final a in saved)
              ListTile(
                leading: const Icon(Icons.bookmark_rounded, color: AppColors.primary),
                title: Text(a.label),
                subtitle: Text(a.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, 'saved:${a.id}'),
              ),
            ListTile(
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('Use my current location'),
              onTap: () => Navigator.pop(ctx, 'gps'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Pick on the map'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha_rounded),
              title: const Text('Anywhere (sort A–Z)'),
              onTap: () => Navigator.pop(ctx, 'none'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'none') return _setDeliverTo(null);
    if (choice.startsWith('saved:')) {
      final a = saved.firstWhere((s) => 'saved:${s.id}' == choice);
      return _setDeliverTo(PickedPlace(point: a.point, address: a.address));
    }
    if (choice == 'map') {
      final current = _deliverTo();
      final picked = await MapPickerScreen.show(
        context,
        title: 'Deliver to',
        pinColor: AppColors.danger,
        initialCenter: current?.point,
        initialAddress: current?.address,
      );
      if (picked != null) _setDeliverTo(picked);
      return;
    }
    // GPS
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(locationServiceProvider).currentPosition();
    if (!result.isSuccess) {
      messenger.showSnackBar(SnackBar(content: Text(result.message), backgroundColor: AppColors.danger));
      return;
    }
    final point = result.point!;
    final address = await ref.read(geocodingServiceProvider).reverseGeocode(point) ??
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    if (mounted) _setDeliverTo(PickedPlace(point: point, address: address));
  }

  // ── Filtering ─────────────────────────────────────────────────────────

  double? _cheapestFee(double km) {
    final vehicles = ref.watch(vehiclesListProvider).valueOrNull ?? const [];
    double? best;
    for (final v in vehicles) {
      final fee = FareEstimator.estimateFare(v, km);
      if (best == null || fee < best) best = fee;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final deliverTo = _deliverTo();
    return Scaffold(
      appBar: AppBar(title: const Text('Food Delivery')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_entries == null || _entries!.isEmpty)
              ? const Center(child: Text('No restaurants available'))
              : _body(deliverTo),
    );
  }

  Widget _body(PickedPlace? deliverTo) {
    final all = _entries!;
    final townCounts = <String, int>{};
    for (final e in all) {
      townCounts[e.town] = (townCounts[e.town] ?? 0) + 1;
    }
    final towns = townCounts.keys.toList()..sort((a, b) => townCounts[b]!.compareTo(townCounts[a]!));
    final inTown = all.where((e) => _town == 'all' || e.town == _town).toList();
    final present = foodCategories.where((c) => inTown.any((e) => e.cats.contains(c.id))).toList();
    final category = present.any((c) => c.id == _category) ? _category : 'all';

    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final rows = <({_Entry e, double? km, List<String> hits})>[];
    for (final e in inTown) {
      if (category != 'all' && !e.cats.contains(category)) continue;
      var hits = const <String>[];
      if (words.isNotEmpty) {
        final hay = '${e.r.name} ${e.r.address} ${e.r.cuisineType ?? ''}'.toLowerCase();
        hits = (_dishes[e.r.id] ?? const [])
            .where((d) => words.every(d.toLowerCase().contains))
            .toList();
        if (!words.every(hay.contains) && hits.isEmpty) continue;
      }
      final km = (deliverTo != null && e.r.hasLocation)
          ? roadKm(deliverTo.point, LatLng(e.r.lat!, e.r.lng!))
          : null;
      rows.add((e: e, km: km, hits: hits));
    }
    rows.sort((a, b) => (a.km != null && b.km != null)
        ? a.km!.compareTo(b.km!)
        : a.e.r.name.toLowerCase().compareTo(b.e.r.name.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: _chooseDeliverTo,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Deliver to',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      isDense: true,
                    ),
                    child: Text(
                      deliverTo?.address ?? 'Anywhere — tap to set',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _town,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Town', isDense: true),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All towns')),
                    for (final t in towns)
                      DropdownMenuItem(value: t, child: Text('$t (${townCounts[t]})', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _town = v ?? 'all'),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _chip('all', 'All', Icons.storefront_rounded, category),
              for (final c in present) _chip(c.id, c.label, c.icon, category),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search restaurant or dish (bagnet, milk tea…)',
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${rows.length} place${rows.length == 1 ? '' : 's'}${deliverTo != null ? ' · nearest first' : ''}',
              style: AppTypography.caption,
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text('No matches — try another town, category or dish.',
                      style: AppTypography.caption),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _card(rows[i].e, rows[i].km, rows[i].hits),
                ),
        ),
      ],
    );
  }

  Widget _chip(String id, String label, IconData icon, String selected) {
    final active = id == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: active ? Colors.white : AppColors.neutral600),
        label: Text(label),
        selected: active,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(color: active ? Colors.white : null, fontSize: 12.5),
        onSelected: (_) => setState(() => _category = id),
      ),
    );
  }

  Widget _card(_Entry e, double? km, List<String> hits) {
    final r = e.r;
    final fee = km == null ? null : _cheapestFee(km);
    final meta = [
      r.cuisineType ?? 'Restaurant',
      e.town,
      if (km != null) '~${km.toStringAsFixed(1)} km',
      if (fee != null) 'from ${Formatters.currency(fee)} delivery',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        leading: r.imageUrl != null
            ? Image.network(r.imageUrl!, width: 48, height: 48, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.storefront, size: 36))
            : const Icon(Icons.storefront, size: 36),
        title: Text(r.name, style: AppTypography.bodyBold),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta, style: AppTypography.caption),
            if (hits.isNotEmpty)
              Text('Has: ${hits.take(3).join(', ')}',
                  style: AppTypography.caption.copyWith(color: AppColors.primary)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RestaurantMenuScreen(restaurant: r)),
        ),
      ),
    );
  }
}
