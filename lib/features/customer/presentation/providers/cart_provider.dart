import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/restaurant_models.dart';

class CartItem {
  final MenuItemModel menuItem;
  final int quantity;

  CartItem({required this.menuItem, this.quantity = 1});
  
  double get totalPrice => menuItem.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(menuItem: menuItem, quantity: quantity ?? this.quantity);
  }
}

class CartState {
  final RestaurantModel? restaurant;
  final Map<String, CartItem> items; // key: menuItemId

  CartState({this.restaurant, this.items = const {}});

  double get totalPrice => items.values.fold(0, (sum, item) => sum + item.totalPrice);
  int get totalItems => items.values.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({RestaurantModel? restaurant, Map<String, CartItem>? items}) {
    return CartState(
      restaurant: restaurant ?? this.restaurant,
      items: items ?? this.items,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState());

  void addItem(RestaurantModel restaurant, MenuItemModel menuItem) {
    if (state.restaurant != null && state.restaurant!.id != restaurant.id) {
      state = CartState(restaurant: restaurant, items: {
        menuItem.id: CartItem(menuItem: menuItem, quantity: 1)
      });
      return;
    }

    final currentItems = Map<String, CartItem>.from(state.items);
    if (currentItems.containsKey(menuItem.id)) {
      currentItems[menuItem.id] = currentItems[menuItem.id]!.copyWith(
        quantity: currentItems[menuItem.id]!.quantity + 1,
      );
    } else {
      currentItems[menuItem.id] = CartItem(menuItem: menuItem, quantity: 1);
    }

    state = state.copyWith(restaurant: restaurant, items: currentItems);
  }

  void removeItem(String menuItemId) {
    final currentItems = Map<String, CartItem>.from(state.items);
    if (currentItems.containsKey(menuItemId)) {
      final newQuantity = currentItems[menuItemId]!.quantity - 1;
      if (newQuantity <= 0) {
        currentItems.remove(menuItemId);
      } else {
        currentItems[menuItemId] = currentItems[menuItemId]!.copyWith(quantity: newQuantity);
      }
    }
    
    if (currentItems.isEmpty) {
      state = CartState();
    } else {
      state = state.copyWith(items: currentItems);
    }
  }

  void clearCart() {
    state = CartState();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
