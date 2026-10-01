import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/restaurant_models.dart';
import '../../data/restaurant_repository.dart';
import 'restaurant_menu_screen.dart';

class BookFoodScreen extends ConsumerStatefulWidget {
  const BookFoodScreen({super.key});

  @override
  ConsumerState<BookFoodScreen> createState() => _BookFoodScreenState();
}

class _BookFoodScreenState extends ConsumerState<BookFoodScreen> {
  List<RestaurantModel>? _restaurants;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    try {
      final repo = ref.read(restaurantRepositoryProvider);
      final restaurants = await repo.getRestaurants();
      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading restaurants: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Delivery')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants == null || _restaurants!.isEmpty
              ? const Center(child: Text('No restaurants available'))
              : ListView.builder(
                  itemCount: _restaurants!.length,
                  itemBuilder: (context, index) {
                    final restaurant = _restaurants![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: restaurant.imageUrl != null
                            ? Image.network(restaurant.imageUrl!,
                                width: 50, height: 50, fit: BoxFit.cover)
                            : const Icon(Icons.storefront, size: 50),
                        title: Text(restaurant.name,
                            style: AppTypography.bodyBold),
                        subtitle: Text(restaurant.address,
                            style: AppTypography.caption),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(restaurant.rating.toStringAsFixed(1)),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RestaurantMenuScreen(
                                  restaurant: restaurant),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
