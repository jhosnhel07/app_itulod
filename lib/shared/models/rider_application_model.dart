enum ApplicationStatus {
  pending,
  approved,
  rejected;

  static ApplicationStatus fromString(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return ApplicationStatus.approved;
      case 'rejected':
        return ApplicationStatus.rejected;
      case 'pending':
      default:
        return ApplicationStatus.pending;
    }
  }

  String toDbString() {
    switch (this) {
      case ApplicationStatus.approved:
        return 'approved';
      case ApplicationStatus.rejected:
        return 'rejected';
      case ApplicationStatus.pending:
        return 'pending';
    }
  }
}

class RiderApplicationModel {
  final String id;
  final String riderId;
  final String? licenseNumber;
  final String? licenseUrl;
  final String? orCrUrl;
  final String? selfieUrl;
  final String? vehicleUrl;
  final String? nbiUrl;
  final String vehicleType;
  final String? vehiclePlate;
  final String? vehicleModel;
  final ApplicationStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RiderApplicationModel({
    required this.id,
    required this.riderId,
    this.licenseNumber,
    this.licenseUrl,
    this.orCrUrl,
    this.selfieUrl,
    this.vehicleUrl,
    this.nbiUrl,
    required this.vehicleType,
    this.vehiclePlate,
    this.vehicleModel,
    this.status = ApplicationStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory RiderApplicationModel.fromJson(Map<String, dynamic> json) {
    return RiderApplicationModel(
      id: json['id'] as String? ?? '',
      riderId: json['rider_id'] as String? ?? '',
      licenseNumber: json['license_number'] as String?,
      licenseUrl: json['license_url'] as String?,
      orCrUrl: json['or_cr_url'] as String?,
      selfieUrl: json['selfie_url'] as String?,
      vehicleUrl: json['vehicle_url'] as String?,
      nbiUrl: json['nbi_url'] as String?,
      vehicleType: json['vehicle_type'] as String? ?? 'Motorcycle',
      vehiclePlate: json['vehicle_plate'] as String?,
      vehicleModel: json['vehicle_model'] as String?,
      status: ApplicationStatus.fromString(json['status'] as String?),
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null ? DateTime.tryParse(json['reviewed_at'] as String) : null,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'license_number': licenseNumber,
      'license_url': licenseUrl,
      'or_cr_url': orCrUrl,
      'selfie_url': selfieUrl,
      'vehicle_url': vehicleUrl,
      'nbi_url': nbiUrl,
      'vehicle_type': vehicleType,
      'vehicle_plate': vehiclePlate,
      'vehicle_model': vehicleModel,
      'status': status.toDbString(),
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
