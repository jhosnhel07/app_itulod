class VehicleModel {
  /// Hauling-only vehicle (Pickup / Multicab, L300, trucks).
  bool get isHauling => services.length == 1 && services.first == 'hauling';

  /// Can this vehicle be booked for [service] — 'ride', 'food', 'parcel'
  /// or 'hauling'? (vehicles.services, web sql/040; web: vehicleAllows)
  bool allows(String service) => services.contains(service);

  final String id;
  final String name;
  final String icon;
  final int capacity;
  final double baseFare;
  final double perKmRate;
  final bool isAvailable;
  /// 'standard' (rides, food, parcel) or 'hauling' (big / heavy loads).
  final String service;
  /// What it can be booked for: any of ride, food, parcel, hauling.
  final List<String> services;
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
    this.service = 'standard',
    this.services = const ['ride', 'food', 'parcel'],
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
      service: json['service'] as String? ?? 'standard',
      services: _servicesFrom(json),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  /// Rows from before sql/040 only have the old standard / hauling split.
  static List<String> _servicesFrom(Map<String, dynamic> json) {
    final raw = json['services'];
    if (raw is List && raw.isNotEmpty) return raw.map((e) => e.toString()).toList();
    return json['service'] == 'hauling' ? const ['hauling'] : const ['ride', 'food', 'parcel'];
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
      'service': service,
      'services': services,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
