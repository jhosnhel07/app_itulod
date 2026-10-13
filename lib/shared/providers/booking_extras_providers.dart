import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/customer/data/customer_repository.dart';
import '../models/booking_models.dart';

/// Stops on a multi-stop ride, in order. Keyed by booking id.
final rideStopsProvider =
    FutureProvider.autoDispose.family<List<RideStop>, String>((ref, bookingId) {
  return ref.watch(customerRepositoryProvider).fetchRideStops(bookingId);
});

/// Line items of a cart-based food order. Keyed by food delivery id.
final foodOrderItemsProvider =
    FutureProvider.autoDispose.family<List<FoodOrderItem>, String>((ref, bookingId) {
  return ref.watch(customerRepositoryProvider).fetchFoodOrderItems(bookingId);
});
