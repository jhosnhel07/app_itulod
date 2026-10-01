import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/restaurant_models.dart';
import '../../../core/utils/app_log.dart';

final restaurantRepositoryProvider = Provider<RestaurantRepository>((ref) {
  return RestaurantRepository(SupabaseConfig.client);
});

class RestaurantRepository {
  final SupabaseClient _client;

  RestaurantRepository(this._client);

  Future<List<RestaurantModel>> getRestaurants() async {
    try {
      final response = await _client
          .from('restaurants')
          .select()
          .order('name');
      return (response as List)
          .map((json) => RestaurantModel.fromJson(json))
          .toList();
    } catch (e, st) {
      AppLog.warn('Error fetching restaurants', e, st);
      rethrow;
    }
  }

  Future<List<MenuItemModel>> getMenuItems(String restaurantId) async {
    try {
      final response = await _client
          .from('menu_items')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('name');
      return (response as List)
          .map((json) => MenuItemModel.fromJson(json))
          .toList();
    } catch (e, st) {
      AppLog.warn('Error fetching menu items', e, st);
      rethrow;
    }
  }
}
