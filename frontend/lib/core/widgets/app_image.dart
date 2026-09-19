import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../storage/private_media_cache.dart';

class AppImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallbackWidget;
  final PrivateMediaCache? mediaCache;
  final VoidCallback? onError;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallbackWidget,
    this.mediaCache,
    this.onError,
  });

  static bool isPrivateMedia(String url) {
    if (url.startsWith('med_')) return true;
    if (url.contains('/api/v1/media/')) return true;
    return false;
  }

  static String extractMediaId(String url) {
    if (url.startsWith('med_')) {
      return url.split('.').first;
    }
    final match = RegExp(r'/api/v1/media/([^/?#]+)').firstMatch(url);
    if (match != null) {
      return match.group(1)!;
    }
    return url;
  }

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  Future<File>? _mediaFuture;
  int? _capturedSessionGen;

  @override
  void initState() {
    super.initState();
    _resolveMediaFuture();
  }

  @override
  void didUpdateWidget(AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.mediaCache != widget.mediaCache) {
      _resolveMediaFuture();
    }
  }

  void _resolveMediaFuture() {
    String resolvedUrl = widget.imageUrl;
    if (resolvedUrl.startsWith('/uploads/')) {
      resolvedUrl = '${ApiConfig.baseUrl}$resolvedUrl';
    }

    if (!kIsWeb && AppImage.isPrivateMedia(resolvedUrl)) {
      final mediaId = AppImage.extractMediaId(resolvedUrl);
      final cache = widget.mediaCache ?? PrivateMediaCache.instance;
      _capturedSessionGen = cache.sessionGeneration;
      final downloadUrl = resolvedUrl.startsWith('http')
          ? resolvedUrl
          : '${ApiConfig.baseUrl}/api/v1/media/$mediaId';
      _mediaFuture = cache.downloadAndCacheMedia(
        mediaId: mediaId,
        downloadUrl: downloadUrl,
      );
    } else {
      _mediaFuture = null;
      _capturedSessionGen = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback =
        widget.fallbackWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: AppColors.surfaceVariant,
          child: const Center(
            child: Icon(Icons.palette_outlined, size: 40, color: AppColors.oak),
          ),
        );

    if (widget.imageUrl.isEmpty) {
      return fallback;
    }

    String resolvedUrl = widget.imageUrl;
    if (resolvedUrl.startsWith('/uploads/')) {
      resolvedUrl = '${ApiConfig.baseUrl}$resolvedUrl';
    }

    // Private media asset caching
    if (_mediaFuture != null) {
      return FutureBuilder<File>(
        future: _mediaFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: widget.width,
              height: widget.height,
              color: AppColors.surfaceVariant,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.terracotta,
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            debugPrint('[AppImage] Future error: ${snapshot.error} ${snapshot.stackTrace}');
            widget.onError?.call();
            return fallback;
          }
          if (snapshot.hasData && snapshot.data != null) {
            final cache = widget.mediaCache ?? PrivateMediaCache.instance;
            if (_capturedSessionGen != null && cache.sessionGeneration != _capturedSessionGen) {
              debugPrint('[AppImage] Session changed while awaiting media; invalidating pending widget result.');
              widget.onError?.call();
              return fallback;
            }
            return Image.file(
              snapshot.data!,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: (context, error, stackTrace) {
                widget.onError?.call();
                return fallback;
              },
            );
          }
          widget.onError?.call();
          return fallback;
        },
      );
    }

    final isNetwork =
        resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://');
    final isBlobOrLocalhost =
        resolvedUrl.startsWith('blob:') ||
        resolvedUrl.startsWith('http://localhost') ||
        resolvedUrl.startsWith('http://127.0.0.1') ||
        resolvedUrl.startsWith('http://10.0.2.2') ||
        resolvedUrl.startsWith('http://192.168.');

    // Local file from camera/gallery capture
    if (!kIsWeb && !isNetwork && !isBlobOrLocalhost) {
      final file = File(resolvedUrl);
      if (file.existsSync() && file.lengthSync() > 0) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) {
            widget.onError?.call();
            return fallback;
          },
        );
      }
      return fallback;
    }

    if (isBlobOrLocalhost) {
      return Image.network(
        resolvedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: widget.width,
            height: widget.height,
            color: AppColors.parchmentDeep,
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.terracotta,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint(
            'AppImage failed to load network image: $resolvedUrl ($error)',
          );
          widget.onError?.call();
          return fallback;
        },
      );
    }

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (context, url) => Container(
          width: widget.width,
          height: widget.height,
          color: AppColors.surfaceVariant,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) {
          widget.onError?.call();
          return fallback;
        },
      );
    }

    final fallbackFile = File(resolvedUrl);
    if (!kIsWeb && fallbackFile.existsSync() && fallbackFile.lengthSync() > 0) {
      return Image.file(
        fallbackFile,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          widget.onError?.call();
          return fallback;
        },
      );
    }
    return fallback;
  }
}
