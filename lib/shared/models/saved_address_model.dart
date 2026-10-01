import 'package:latlong2/latlong.dart';

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
    return SavedAddressModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      label: json['label'] as String,
      address: json['address'] as String,
      point: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'label': label,
      'address': address,
      'latitude': point.latitude,
      'longitude': point.longitude,
    };
  }
}
