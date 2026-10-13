import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/restaurant_models.dart';
import '../../data/restaurant_repository.dart';
import '../providers/cart_provider.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
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
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new order?'),
          content: Text('Switching restaurants clears your current order from ${other.name}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref.read(cartProvider.notifier).addItem(widget.restaurant, item);
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.restaurant.name)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _menuItems == null || _menuItems!.isEmpty
              ? const Center(child: Text('No menu items available'))
              : ListView.builder(
                  itemCount: _menuItems!.length,
                  itemBuilder: (context, index) {
                    final item = _menuItems![index];
                    final cartItem = cartState.items[item.id];
                    
                    final description = item.description?.trim() ?? '';
                    return ListTile(
                      title: Text(item.name, style: AppTypography.bodyBold),
                      subtitle: Text(description.isEmpty
                          ? Formatters.currency(item.price)
                          : '${Formatters.currency(item.price)}\n$description'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cartItem != null && cartItem.quantity > 0) ...[
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                ref.read(cartProvider.notifier).removeItem(item.id);
                              },
                            ),
                            Text('${cartItem.quantity}'),
                          ],
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _addToCart(item),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: cartState.totalItems > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FoodCartScreen()),
                    );
                  },
                  child: Text('View Cart (${cartState.totalItems}) - ${Formatters.currency(cartState.totalPrice)}'),
                ),
              ),
            )
          : null,
    );
  }
}
