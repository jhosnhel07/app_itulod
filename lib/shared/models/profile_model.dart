enum UserRole {
  customer,
  rider,
  admin;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'rider':
        return UserRole.rider;
      case 'customer':
      default:
        return UserRole.customer;
    }
  }

  String toDbString() {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.rider:
        return 'rider';
      case UserRole.customer:
        return 'customer';
    }
  }
}

class ProfileModel {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final UserRole role;
  final String? avatarUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int loyaltyPoints;
  final String? referralCode;
  final String? referredBy;
  final double floatAmount;

  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.role = UserRole.customer,
    this.avatarUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.loyaltyPoints = 0,
    this.referralCode,
    this.referredBy,
    this.floatAmount = 0.0,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: UserRole.fromString(json['role'] as String?),
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      loyaltyPoints: json['loyalty_points'] as int? ?? 0,
      referralCode: json['referral_code'] as String?,
      referredBy: json['referred_by'] as String?,
      floatAmount: (json['float_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'role': role.toDbString(),
      'avatar_url': avatarUrl,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ProfileModel copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    UserRole? role,
    String? avatarUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? loyaltyPoints,
    String? referralCode,
    double? floatAmount,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      referralCode: referralCode ?? this.referralCode,
      referredBy: referredBy ?? this.referredBy,
      floatAmount: floatAmount ?? this.floatAmount,
    );
  }
}
