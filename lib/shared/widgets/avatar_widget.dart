import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AvatarWidget extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  final VoidCallback? onTap;

  /// Draw a white ring around the avatar — reads well on coloured app bars.
  final bool ring;

  const AvatarWidget({
    super.key,
    this.url,
    required this.name,
    this.radius = 24,
    this.onTap,
    this.ring = false,
  });

  String get _initials {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      _initials,
      style: TextStyle(
        fontSize: radius * 0.72,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryDark,
      ),
    );

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary100,
      child: (url != null && url!.isNotEmpty)
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: url!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(strokeWidth: 2),
                errorWidget: (context, url, error) => fallback,
              ),
            )
          : fallback,
    );

    if (ring) {
      avatar = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.25),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }
}
