class VehicleModel {
  final String id;
  final String name;
  final String icon;
  final int capacity;
  final double baseFare;
  final double perKmRate;
  final bool isAvailable;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VehicleModel({
    required this.id,
    required this.name,
    this.icon = 'fa-car',
    this.capacity = 1,
    this.baseFare = 0.0,
    this.perKmRate = 0.0,
    this.isAvailable = true,
    this.createdAt,
    this.updatedAt,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'fa-car',
      capacity: (json['capacity'] as num?)?.toInt() ?? 1,
      baseFare: (json['base_fare'] as num?)?.toDouble() ?? 0.0,
      perKmRate: (json['per_km_rate'] as num?)?.toDouble() ?? 0.0,
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'capacity': capacity,
      'base_fare': baseFare,
      'per_km_rate': perKmRate,
      'is_available': isAvailable,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
