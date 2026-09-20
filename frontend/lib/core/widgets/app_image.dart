import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../storage/private_media_cache.dart';

typedef ImageRenderCallback = void Function({
  required String assetIdentity,
  required String sha256Checksum,
  int? sessionGeneration,
});

class AppImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallbackWidget;
  final PrivateMediaCache? mediaCache;
  final VoidCallback? onError;
  final ImageRenderCallback? onRenderSuccess;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallbackWidget,
    this.mediaCache,
    this.onError,
    this.onRenderSuccess,
  });

  static String extractMediaId(String url) {
    if (url.startsWith('med_')) return url;
    if (url.startsWith('/uploads/')) {
      final segments = url.split('/');
      return segments.isNotEmpty ? segments.last : '';
    }
    final match = RegExp(r'/api/v1/media/([^/?#]+)').firstMatch(url);
    if (match != null) {
      return match.group(1)!;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return '';
  }

  static bool isPrivateMedia(String url) {
    if (url.startsWith('med_')) return true;
    final uri = Uri.tryParse(url);
    final path = uri != null ? uri.path : url;
    return path.startsWith('/api/v1/media/') || path.startsWith('/uploads/');
  }

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  Future<File>? _mediaFuture;
  int? _capturedSessionGen;
  String? _lastReportedAsset;

  @override
  void initState() {
    super.initState();
    _resolveMediaFuture();
  }

  @override
  void didUpdateWidget(AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _lastReportedAsset = null;
      _resolveMediaFuture();
    }
  }

  void _notifyRenderSuccess({
    required String assetIdentity,
    required String sha256Checksum,
    int? sessionGeneration,
  }) {
    if (sha256Checksum.isEmpty) return;
    if (_lastReportedAsset == assetIdentity) return;
    _lastReportedAsset = assetIdentity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onRenderSuccess?.call(
          assetIdentity: assetIdentity,
          sha256Checksum: sha256Checksum,
          sessionGeneration: sessionGeneration,
        );
      }
    });
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
              _lastReportedAsset = null;
              widget.onError?.call();
              return fallback;
            }
            Uint8List? mediaBytes;
            String fileSha256 = '';
            try {
              if (snapshot.data!.existsSync()) {
                mediaBytes = snapshot.data!.readAsBytesSync();
                if (mediaBytes.isNotEmpty) {
                  fileSha256 = sha256.convert(mediaBytes).toString();
                }
              }
            } catch (_) {
              mediaBytes = null;
            }
            if (mediaBytes == null || mediaBytes.isEmpty || fileSha256.isEmpty) {
              _lastReportedAsset = null;
              widget.onError?.call();
              return fallback;
            }
            final decoded = img.decodeImage(mediaBytes);
            if (decoded == null) {
              _lastReportedAsset = null;
              widget.onError?.call();
              return fallback;
            }
            _notifyRenderSuccess(
              assetIdentity: resolvedUrl,
              sha256Checksum: fileSha256,
              sessionGeneration: _capturedSessionGen,
            );
            return Image.memory(
              mediaBytes,
              key: ValueKey('${resolvedUrl}_$fileSha256'),
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null || wasSynchronouslyLoaded) {
                  _notifyRenderSuccess(
                    assetIdentity: resolvedUrl,
                    sha256Checksum: fileSha256,
                    sessionGeneration: _capturedSessionGen,
                  );
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                _lastReportedAsset = null;
                widget.onError?.call();
                return fallback;
              },
            );
          }
          _lastReportedAsset = null;
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
        Uint8List? fileBytes;
        String fileSha256 = '';
        try {
          fileBytes = file.readAsBytesSync();
          if (fileBytes.isNotEmpty) {
            fileSha256 = sha256.convert(fileBytes).toString();
          }
        } catch (_) {
          fileBytes = null;
        }
        if (fileBytes == null || fileBytes.isEmpty || fileSha256.isEmpty) {
          _lastReportedAsset = null;
          widget.onError?.call();
          return fallback;
        }
        final decoded = img.decodeImage(fileBytes);
        if (decoded == null) {
          _lastReportedAsset = null;
          widget.onError?.call();
          return fallback;
        }
        _notifyRenderSuccess(
          assetIdentity: resolvedUrl,
          sha256Checksum: fileSha256,
          sessionGeneration: null,
        );

        return Image.memory(
          fileBytes,
          key: ValueKey('${resolvedUrl}_$fileSha256'),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              _notifyRenderSuccess(
                assetIdentity: resolvedUrl,
                sha256Checksum: fileSha256,
                sessionGeneration: null,
              );
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _lastReportedAsset = null;
            widget.onError?.call();
            return fallback;
          },
        );
      }
      _lastReportedAsset = null;
      widget.onError?.call();
      return fallback;
    }

    if (isBlobOrLocalhost) {
      return Image.network(
        resolvedUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            _notifyRenderSuccess(
              assetIdentity: resolvedUrl,
              sha256Checksum: '',
              sessionGeneration: null,
            );
          }
          return child;
        },
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
        imageBuilder: (context, imageProvider) {
          _notifyRenderSuccess(
            assetIdentity: resolvedUrl,
            sha256Checksum: '',
            sessionGeneration: null,
          );
          return Image(
            image: imageProvider,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
          );
        },
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
      Uint8List? fileBytes;
      String fileSha256 = '';
      try {
        fileBytes = fallbackFile.readAsBytesSync();
        if (fileBytes.isNotEmpty) {
          fileSha256 = sha256.convert(fileBytes).toString();
        }
      } catch (_) {
        fileBytes = null;
      }
      if (fileBytes == null || fileBytes.isEmpty || fileSha256.isEmpty) {
        _lastReportedAsset = null;
        widget.onError?.call();
        return fallback;
      }
      final decoded = img.decodeImage(fileBytes);
      if (decoded == null) {
        _lastReportedAsset = null;
        widget.onError?.call();
        return fallback;
      }
      _notifyRenderSuccess(
        assetIdentity: resolvedUrl,
        sha256Checksum: fileSha256,
        sessionGeneration: null,
      );
      return Image.memory(
        fileBytes,
        key: ValueKey('${resolvedUrl}_$fileSha256'),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            _notifyRenderSuccess(
              assetIdentity: resolvedUrl,
              sha256Checksum: fileSha256,
              sessionGeneration: null,
            );
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          _lastReportedAsset = null;
          widget.onError?.call();
          return fallback;
        },
      );
    }
    return fallback;
  }
}
