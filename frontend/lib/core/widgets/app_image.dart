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
    final fallback =
        fallbackWidget ??
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

    String resolvedUrl = imageUrl;
    if (resolvedUrl.startsWith('/uploads/')) {
      const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
      final baseUrl = configuredBaseUrl.isNotEmpty
          ? configuredBaseUrl
          : (Platform.isAndroid
                ? 'http://10.0.2.2:8000'
                : 'http://127.0.0.1:8000');
      resolvedUrl = '$baseUrl$resolvedUrl';
    }

    final isNetwork =
        resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://');
    final isBlobOrLocalhost =
        resolvedUrl.startsWith('blob:') ||
        resolvedUrl.startsWith('http://localhost') ||
        resolvedUrl.startsWith('http://127.0.0.1') ||
        resolvedUrl.startsWith('http://10.0.2.2');

    // Local file from camera/gallery capture
    if (!kIsWeb && !isNetwork && !isBlobOrLocalhost) {
      final file = File(resolvedUrl);
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
        resolvedUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          debugPrint(
            'AppImage failed to load network image: $resolvedUrl ($error)',
          );
          return fallback;
        },
      );
    }

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: resolvedUrl,
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

    return Image.file(
      File(resolvedUrl),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
