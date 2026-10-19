import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import '../../../../shared/widgets/rise_in.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Order Food')),
      body: _isLoading
          ? const SkeletonList(count: 5)
          : (_entries == null || _entries!.isEmpty)
              ? const Center(child: Text('No restaurants available'))
              : _body(deliverTo),
    );
  }

  Future<void> _chooseTown(List<String> towns, Map<String, int> counts) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text('Town', style: AppTypography.h3)),
              _townTile(ctx, 'all', 'All of Ilocos Norte', counts.values.fold(0, (a, b) => a + b)),
              for (final t in towns) _townTile(ctx, t, t, counts[t]!),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _town = picked);
  }

  Widget _townTile(BuildContext ctx, String value, String label, int count) {
    final selected = _town == value;
    return ListTile(
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? AppColors.primary : AppColors.neutral400),
      title: Text(label, style: selected ? AppTypography.bodyBold : AppTypography.body),
      trailing: _CountPill(count: count, active: false),
      onTap: () => Navigator.pop(ctx, value),
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
    final present = [
      for (final c in foodCategories)
        if (inTown.any((e) => e.cats.contains(c.id)))
          (cat: c, count: inTown.where((e) => e.cats.contains(c.id)).length),
    ];
    final category = present.any((p) => p.cat.id == _category) ? _category : 'all';

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
        // ── Filter panel ──────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.iconMuted),
                  hintText: 'Search a restaurant or dish',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SelectTile(
                      icon: Icons.location_on_rounded,
                      label: 'DELIVER TO',
                      value: deliverTo?.address ?? 'Anywhere — tap to set',
                      onTap: _chooseDeliverTo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _SelectTile(
                      icon: Icons.map_rounded,
                      label: 'TOWN',
                      value: _town == 'all' ? 'All towns' : _town,
                      onTap: () => _chooseTown(towns, townCounts),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ChipScroller(
                children: [
                  _chip('all', 'All', Icons.storefront_rounded, inTown.length, category),
                  for (final p in present) _chip(p.cat.id, p.cat.label, p.cat.icon, p.count, category),
                ],
              ),
            ],
          ),
        ),
        // ── Summary ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Text('${rows.length} place${rows.length == 1 ? '' : 's'}',
                  style: AppTypography.bodyBold.copyWith(fontSize: 13.5)),
              const Spacer(),
              Icon(deliverTo != null ? Icons.near_me_rounded : Icons.sort_by_alpha_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(deliverTo != null ? 'Nearest first' : 'Sorted A–Z', style: AppTypography.caption),
            ],
          ),
        ),
        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 44, color: AppColors.primary100),
                      const SizedBox(height: 8),
                      Text('No matches', style: AppTypography.bodyBold),
                      const SizedBox(height: 2),
                      Text('Try another town, category or dish.', style: AppTypography.caption),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => RiseIn(
                    index: i < 8 ? i : 0,
                    child: _card(rows[i].e, rows[i].km, rows[i].hits),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(String id, String label, IconData icon, int count, String selected) {
    final active = id == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.primary : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: active ? AppColors.primary : AppColors.cardBorder),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _category = id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 15, color: active ? Colors.white : AppColors.primary),
                const SizedBox(width: 6),
                Text(label,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppColors.neutral700,
                    )),
                const SizedBox(width: 6),
                _CountPill(count: count, active: active),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_Entry e, double? km, List<String> hits) {
    final r = e.r;
    final fee = km == null ? null : _cheapestFee(km);
    final visual = restaurantVisual(e.cats);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RestaurantMenuScreen(restaurant: r)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              RestaurantLogoTile(
                  imageUrl: r.imageUrl,
                  bg: visual.bg,
                  fg: visual.fg,
                  icon: visual.icon,
                  initials: restaurantInitials(r.name)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(restaurantDisplayName(r, e.town),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyBold.copyWith(fontSize: 15)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Tag(text: r.cuisineType ?? 'Restaurant'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 13, color: AppColors.secondary),
                            const SizedBox(width: 2),
                            Text(e.town, style: AppTypography.caption.copyWith(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    if (hits.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('🍴 ${hits.take(3).join(' · ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: AppColors.primary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (km != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${km < 10 ? km.toStringAsFixed(1) : km.round()} km',
                        style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                    if (fee != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${Formatters.currency(fee)} delivery',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF157A4D),
                            )),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The restaurant's own logo when one is uploaded; otherwise a name badge —
/// its initials on the category colour with the category icon (web:
/// restaurantLogoTile).
class RestaurantLogoTile extends StatelessWidget {
  final String? imageUrl;
  final Color bg;
  final Color fg;
  final IconData icon;
  final double size;
  final String? initials;

  const RestaurantLogoTile({
    super.key,
    this.imageUrl,
    required this.bg,
    required this.fg,
    required this.icon,
    this.size = 52,
    this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final badge = size * 0.4;
    final fallback = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.6),
                radius: 1.1,
                colors: [Color.lerp(bg, Colors.white, 0.45)!, bg],
              ),
            ),
            child: initials == null
                ? Icon(icon, color: fg, size: size * 0.46)
                : Text(initials!,
                    style: AppTypography.h3.copyWith(
                        color: fg, fontSize: size * 0.34, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ),
          if (initials != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 2),
                ),
                child: Icon(icon, size: badge * 0.55, color: fg),
              ),
            ),
        ],
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(imageUrl!, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class _SelectTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SelectTile({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.caption.copyWith(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyBold.copyWith(fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: AppColors.iconMuted),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryDark,
          )),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  final bool active;

  const _CountPill({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.22) : AppColors.neutral100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count',
          style: AppTypography.caption.copyWith(
            fontSize: 10.5,
            color: active ? Colors.white : AppColors.neutral500,
          )),
    );
  }
}

/// Horizontally scrolling category row with a visible scrollbar, ‹ › arrow
/// buttons that appear only when there's more to see, and drag-to-scroll
/// for mouse and trackpad too (Flutter only drags with touch by default,
/// which left desktop/web users unable to reach the hidden categories).
class _ChipScroller extends StatefulWidget {
  final List<Widget> children;

  const _ChipScroller({required this.children});

  @override
  State<_ChipScroller> createState() => _ChipScrollerState();
}

class _ChipScrollerState extends State<_ChipScroller> {
  final _controller = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant _ChipScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    final left = p.pixels > 2;
    final right = p.pixels < p.maxScrollExtent - 2;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    _controller.animateTo(
      (p.pixels + delta).clamp(0, p.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: PointerDeviceKind.values.toSet(),
            ),
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              thickness: 3,
              radius: const Radius.circular(3),
              child: ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                children: widget.children,
              ),
            ),
          ),
          if (_canLeft) _arrow(left: true),
          if (_canRight) _arrow(left: false),
        ],
      ),
    );
  }

  Widget _arrow({required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 8,
      child: Container(
        width: 48,
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [AppColors.surface, AppColors.surface.withValues(alpha: 0)],
            stops: const [0.45, 1],
          ),
        ),
        child: Material(
          color: AppColors.surface,
          shape: CircleBorder(side: BorderSide(color: AppColors.cardBorder)),
          elevation: 1.5,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _scrollBy(left ? -180 : 180),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  size: 18, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}
