import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

/// Utility to compress and scale product images client-side before network upload.
/// Crucial for artisans operating in low-bandwidth (2G/3G) rural environments.
class ImageCompressor {
  static const int maxDimension = 1600;

  /// Resizes and optimizes [file] to reduce upload size while preserving clarity.
  /// If compression is not possible (e.g. non-image data or headless tests), returns original [file].
  static Future<File> compressForUpload(File file) async {
    if (!await file.exists()) {
      return file;
    }

    try {
      final bytes = await file.readAsBytes();
      // Skip if file is already lightweight (< 350 KB)
      if (bytes.lengthInBytes <= 350 * 1024) {
        return file;
      }

      // Decode and constrain dimension
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxDimension,
      );
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return file;
      }

      final tempDir = await getTemporaryDirectory();
      final compressedPath =
          '${tempDir.path}/comp_${DateTime.now().microsecondsSinceEpoch}.png';
      final compressedFile = File(compressedPath);
      await compressedFile.writeAsBytes(byteData.buffer.asUint8List());

      return compressedFile;
    } catch (_) {
      // Graceful fallback for test runners and headless engines
      return file;
    }
  }
}
