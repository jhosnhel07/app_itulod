class RestaurantModel {
  final String id;
  final String name;
  final String address;
  final String? cuisineType;
  final double? lat;
  final double? lng;
  final String? imageUrl;
  final DateTime createdAt;

  RestaurantModel({
    required this.id,
    required this.name,
    required this.address,
    this.cuisineType,
    this.lat,
    this.lng,
    this.imageUrl,
    required this.createdAt,
  });

  bool get hasLocation => lat != null && lng != null;

  factory RestaurantModel.fromJson(Map<String, dynamic> json) {
    return RestaurantModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      cuisineType: json['cuisine_type'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'cuisine_type': cuisineType,
        'lat': lat,
        'lng': lng,
        'image_url': imageUrl,
        'created_at': createdAt.toIso8601String(),
      };
}

class MenuItemModel {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final DateTime createdAt;

  MenuItemModel({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.createdAt,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'restaurant_id': restaurantId,
        'name': name,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        'created_at': createdAt.toIso8601String(),
      };
}
