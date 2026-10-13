import 'package:latlong2/latlong.dart';
import '../../core/constants/map_config.dart';

class SavedAddressModel {
  final String id;
  final String userId;
  final String label;
  final String address;
  final LatLng point;

  const SavedAddressModel({
    required this.id,
    required this.userId,
    required this.label,
    required this.address,
    required this.point,
  });

  factory SavedAddressModel.fromJson(Map<String, dynamic> json) {
    final lat = _parseDouble(json['lat']);
    final lng = _parseDouble(json['lng']);
    return SavedAddressModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['customer_id'] ?? json['user_id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      point: LatLng(
        lat ?? MapConfig.defaultCenter.latitude,
        lng ?? MapConfig.defaultCenter.longitude,
      ),
    );
  }

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'customer_id': userId,
      'label': label,
      'address': address,
      'lat': point.latitude,
      'lng': point.longitude,
    };
  }

  SavedAddressModel copyWith({
    String? id,
    String? userId,
    String? label,
    String? address,
    LatLng? point,
  }) {
    return SavedAddressModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      address: address ?? this.address,
      point: point ?? this.point,
    );
  }
}
