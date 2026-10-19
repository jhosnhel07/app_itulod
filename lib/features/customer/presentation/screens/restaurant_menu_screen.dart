import 'package:flutter/material.dart';
import '../../../../shared/widgets/rise_in.dart';
import '../../../../shared/widgets/sample_photo_tag.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../../../shared/widgets/app_confirm_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/restaurant_models.dart';
import '../../data/restaurant_finder.dart';
import '../../data/restaurant_repository.dart';
import '../providers/cart_provider.dart';
import 'book_food_screen.dart' show RestaurantLogoTile;
import 'food_cart_screen.dart';

class RestaurantMenuScreen extends ConsumerStatefulWidget {
  final RestaurantModel restaurant;

  const RestaurantMenuScreen({super.key, required this.restaurant});

  @override
  ConsumerState<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  List<MenuItemModel>? _menuItems;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    try {
      final repo = ref.read(restaurantRepositoryProvider);
      final items = await repo.getMenuItems(widget.restaurant.id);
      if (mounted) {
        setState(() {
          _menuItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading menu: $e')),
        );
      }
    }
  }

  /// A cart holds one restaurant's order. Adding from a different one clears
  /// it — confirm first, like the web's selectRestaurantForMenu().
  Future<void> _addToCart(MenuItemModel item) async {
    final cart = ref.read(cartProvider);
    final other = cart.restaurant;
    if (other != null && other.id != widget.restaurant.id && cart.items.isNotEmpty) {
      final ok = await showAppConfirm(
        context,
        title: 'Switch restaurants?',
        message: 'Your current order from ${other.name} will be cleared.',
        confirmText: 'Switch',
        cancelText: 'Keep my order',
        icon: Icons.storefront_rounded,
      );
      if (!ok) return;
    }
    ref.read(cartProvider.notifier).addItem(widget.restaurant, item);
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final r = widget.restaurant;
    final town = restaurantTown(r);
    final cats = restaurantCategories(r);
    final visual = restaurantVisual(cats);
    final deliverTo = ref.watch(foodDeliverToProvider);
    final km = (deliverTo != null && r.hasLocation)
        ? roadKm(deliverTo.point, LatLng(r.lat!, r.lng!))
        : null;
    final items = _menuItems ?? const <MenuItemModel>[];
    final hasTypical = items.any((m) => (m.description ?? '').endsWith(typicalItemNote));
    final cartIsHere = cartState.restaurant?.id == r.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Menu')),
      body: _isLoading
          ? const SkeletonList(count: 5)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // ── Category banner (sample photo) ──────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 140,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          restaurantCoverUrl(cats),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: AppColors.primary50),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0x47000000)],
                            ),
                          ),
                        ),
                        const Positioned(top: 10, right: 10, child: SamplePhotoTag()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Restaurant header ───────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.surface, AppColors.primary50],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      RestaurantLogoTile(
                          imageUrl: r.imageUrl,
                          bg: visual.bg,
                          fg: visual.fg,
                          icon: visual.icon,
                          size: 64,
                          initials: restaurantInitials(r.name)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(restaurantDisplayName(r, town), style: AppTypography.h3),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _pill(r.cuisineType ?? 'Restaurant'),
                                _iconText(Icons.location_on_rounded, town),
                                if (km != null) _iconText(Icons.route_rounded, '${km.toStringAsFixed(1)} km'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(r.address, style: AppTypography.caption.copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasTypical) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.blush,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Items marked TYPICAL are what this kind of place usually serves — '
                            'your rider confirms availability and the final price at pickup.',
                            style: AppTypography.caption.copyWith(fontSize: 12, color: AppColors.warmInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No menu items available', style: AppTypography.caption)),
                  )
                else
                  for (final (i, item) in items.indexed) ...[
                    RiseIn(
                      index: i < 8 ? i : 0,
                      child: _itemCard(item, cartIsHere ? (cartState.items[item.id]?.quantity ?? 0) : 0),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
      bottomNavigationBar: cartState.totalItems > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FoodCartScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${cartState.totalItems}',
                                  style: AppTypography.bodyBold.copyWith(color: Colors.white, fontSize: 13)),
                            ),
                            const SizedBox(width: 12),
                            Text('View cart',
                                style: AppTypography.bodyBold.copyWith(color: Colors.white, fontSize: 15)),
                            const Spacer(),
                            Text(Formatters.currency(cartState.totalPrice),
                                style: AppTypography.bodyBold.copyWith(color: Colors.white, fontSize: 15)),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _itemCard(MenuItemModel item, int qty) {
    final raw = item.description?.trim() ?? '';
    final typical = raw.endsWith(typicalItemNote.trim()) || raw.endsWith(typicalItemNote);
    final description = typical ? raw.substring(0, raw.length - typicalItemNote.length).trim() : raw;
    final selected = qty > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? AppColors.primary100 : AppColors.cardBorder, width: selected ? 1.5 : 1),
      ),
      child: Row(
        children: [
          if (item.imageUrl != null && item.imageUrl!.startsWith('http')) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.imageUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                if (isSamplePhoto(item.imageUrl))
                  const Positioned(right: 3, bottom: 3, child: SamplePhotoTag(small: true)),
              ],
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item.name, style: AppTypography.bodyBold.copyWith(fontSize: 14.5)),
                    if (typical)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.secondary100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('TYPICAL',
                            style: AppTypography.caption.copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.secondaryDark,
                            )),
                      ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(description, style: AppTypography.caption.copyWith(fontSize: 12.5)),
                ],
                const SizedBox(height: 6),
                Text(Formatters.currency(item.price),
                    style: AppTypography.bodyBold.copyWith(color: AppColors.primaryDark, fontSize: 14.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : AppColors.neutral50,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepButton(Icons.remove_rounded, qty > 0
                    ? () => ref.read(cartProvider.notifier).removeItem(item.id)
                    : null),
                SizedBox(
                  width: 24,
                  child: Text('$qty',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                ),
                _stepButton(Icons.add_rounded, () => _addToCart(item)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: onTap == null ? AppColors.neutral300 : AppColors.primary),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primary50, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: AppTypography.caption.copyWith(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
    );
  }

  Widget _iconText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.secondary),
        const SizedBox(width: 3),
        Text(text, style: AppTypography.caption.copyWith(fontSize: 12)),
      ],
    );
  }
}
