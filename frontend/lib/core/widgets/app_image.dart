import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';

class AppImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallbackWidget;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackWidget ??
        Container(
          width: width,
          height: height,
          color: AppColors.surfaceVariant,
          child: const Center(
            child: Icon(Icons.palette_outlined, size: 40, color: AppColors.oak),
          ),
        );

    if (imageUrl.isEmpty) {
      return fallback;
    }

    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final isBlobOrLocalhost = imageUrl.startsWith('blob:') ||
        imageUrl.startsWith('http://localhost') ||
        imageUrl.startsWith('http://127.0.0.1');

    // Local file from camera/gallery capture — the common case for
    // ProductListing.photoPath / aiEnhancedPhotoPath.
    if (!kIsWeb && !isNetwork && !isBlobOrLocalhost) {
      final file = File(imageUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      }
      return fallback;
    }

    if (isBlobOrLocalhost) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => Container(
          width: width,
          height: height,
          color: AppColors.surfaceVariant,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => fallback,
      );
    }

    return fallback;
  }
}