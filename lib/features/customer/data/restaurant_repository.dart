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
          .eq('is_active', true)
          .order('name');
      return (response as List)
          .map((json) => RestaurantModel.fromJson(json))
          .toList();
    } catch (e, st) {
      AppLog.warn('Error fetching restaurants', e, st);
      rethrow;
    }
  }

  /// Every available dish name keyed by restaurant id, for "search by dish".
  /// Paged because PostgREST caps a response at 1000 rows.
  Future<Map<String, List<String>>> getDishIndex() async {
    final index = <String, List<String>>{};
    for (var from = 0;; from += 1000) {
      final rows = await _client
          .from('menu_items')
          .select('restaurant_id, name')
          .eq('is_available', true)
          .range(from, from + 999);
      for (final row in rows) {
        (index[row['restaurant_id'] as String] ??= []).add(row['name'] as String);
      }
      if (rows.length < 1000) break;
    }
    return index;
  }

  Future<List<MenuItemModel>> getMenuItems(String restaurantId) async {
    try {
      final response = await _client
          .from('menu_items')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('is_available', true)
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
