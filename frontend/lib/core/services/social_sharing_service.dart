import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SocialSharingService {
  static const MethodChannel _whatsappChannel =
      MethodChannel('com.kalasetu.kalasetu/whatsapp_share');

  final Dio _dio;

  SocialSharingService({Dio? dio}) : _dio = dio ?? Dio();

  /// Resolve a network URL or existing local path to an accessible local [File] path.
  Future<String> resolveLocalImage(String imagePathOrUrl) async {
    if (imagePathOrUrl.isEmpty) {
      throw Exception('Image path or URL cannot be empty');
    }

    // Check if it's already an existing local file
    if (!imagePathOrUrl.startsWith('http://') &&
        !imagePathOrUrl.startsWith('https://')) {
      final file = File(imagePathOrUrl);
      if (file.existsSync()) {
        return file.path;
      }
    }

    // Download network image to temp cache directory
    final tempDir = await getTemporaryDirectory();
    final ext = p.extension(imagePathOrUrl).isNotEmpty
        ? p.extension(imagePathOrUrl).split('?').first
        : '.jpg';
    final fileName =
        'social_share_${DateTime.now().millisecondsSinceEpoch}$ext';
    final targetPath = p.join(tempDir.path, fileName);

    await _dio.download(imagePathOrUrl, targetPath);
    return targetPath;
  }

  /// Direct WhatsApp share with image attachment and prefilled caption.
  ///
  /// On Android: Dispatches ACTION_SEND to com.whatsapp via native MethodChannel.
  /// If WhatsApp is not installed or the native intent fails, it falls back
  /// to the universal share sheet (share_plus).
  ///
  /// On iOS: Always uses the universal share sheet (share_plus) for v1.
  Future<void> shareToWhatsApp({
    required String imagePathOrUrl,
    required String caption,
  }) async {
    final localPath = await resolveLocalImage(imagePathOrUrl);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _whatsappChannel.invokeMethod<bool>(
          'shareToWhatsApp',
          {'imagePath': localPath, 'text': caption},
        );
        if (success == true) {
          return;
        }
      } catch (e) {
        debugPrint('[SocialSharingService] Native WhatsApp share failed: $e');
      }
    }

    // Fallback to Universal Share Sheet (iOS, web, or WhatsApp not installed)
    await shareUniversal(imagePath: localPath, text: caption);
  }

  /// Triggers universal system share sheet via share_plus.
  Future<void> shareUniversal({
    required String imagePath,
    required String text,
  }) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: text,
    );
  }

  /// Downloads/writes the product photo directly to the device's gallery.
  /// Requires MediaStore insertion on Android & PhotoLibrary authorization on iOS.
  Future<void> saveImageToGallery(String imagePathOrUrl) async {
    final localPath = await resolveLocalImage(imagePathOrUrl);

    final hasAccess = await Gal.hasAccess(toAlbum: false);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: false);
      if (!granted) {
        throw Exception('Photo library access was not granted.');
      }
    }

    await Gal.putImage(localPath);
  }

  /// Convenience app launcher for Instagram, Facebook, or WhatsApp.
  Future<bool> openApp(String platform) async {
    final String scheme;
    final String fallbackUrl;

    switch (platform.toLowerCase()) {
      case 'instagram':
        scheme = 'instagram://app';
        fallbackUrl = 'https://www.instagram.com';
        break;
      case 'facebook':
        scheme = 'fb://';
        fallbackUrl = 'https://www.facebook.com';
        break;
      case 'whatsapp':
        scheme = 'whatsapp://';
        fallbackUrl = 'https://web.whatsapp.com';
        break;
      default:
        return false;
    }

    try {
      final uri = Uri.parse(scheme);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      final fallbackUri = Uri.parse(fallbackUrl);
      return await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[SocialSharingService] Could not launch app $platform: $e');
      return false;
    }
  }
}
