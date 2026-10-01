class RestaurantModel {
  final String id;
  final String name;
  final String address;
  final String? imageUrl;
  final double rating;
  final DateTime createdAt;

  RestaurantModel({
    required this.id,
    required this.name,
    required this.address,
    this.imageUrl,
    this.rating = 0.0,
    required this.createdAt,
  });

  factory RestaurantModel.fromJson(Map<String, dynamic> json) {
    return RestaurantModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      imageUrl: json['image_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'image_url': imageUrl,
        'rating': rating,
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
