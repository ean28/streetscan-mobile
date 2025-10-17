import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class CloudinaryService {
  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    'ss-img-storage',
    'pothole_upload',
    cache: false,
  );

  static const _boxName = 'uploaded_images';
  Box<String>? _uploadedBox;

  // In-memory cache to speed up repeated uploads in one session
  final Map<String, String> _uploadedCache = {};

  Future<void> _ensureBox() async {
    if (_uploadedBox == null || !_uploadedBox!.isOpen) {
      _uploadedBox = await Hive.openBox<String>(_boxName);

      _uploadedCache.clear();
      for (final key in _uploadedBox!.keys) {
        final val = _uploadedBox!.get(key);
        if (val != null) _uploadedCache[key] = val;
      }
    }
  }

  /// Upload a single image, skipping duplicates
  Future<String?> uploadImage(String imagePath, String sessionId) async {
    await _ensureBox();

    // Check in-memory cache first
    if (_uploadedCache.containsKey(imagePath)) {
      if (kDebugMode) debugPrint('✅ Skipping duplicate upload: $imagePath');
      return _uploadedCache[imagePath];
    }

    try {
      final fileName = imagePath.split('/').last;
      final publicId = 'potholes/$sessionId/$fileName';

      final cloudinaryFile = CloudinaryFile.fromFile(
        imagePath,
        folder: 'potholes/$sessionId',
        resourceType: CloudinaryResourceType.Image,
        identifier: fileName,
        publicId: publicId,
      );

      final response = await _cloudinary.uploadFile(cloudinaryFile);

      // Persist to Hive and cache
      await _uploadedBox!.put(imagePath, response.secureUrl);
      _uploadedCache[imagePath] = response.secureUrl;

      if (kDebugMode) debugPrint('⚡ Uploaded image: $imagePath');
      return response.secureUrl;
    } catch (e) {
      debugPrint('❌ Cloudinary upload failed for $imagePath: $e');
      return null;
    }
  }

  /// Upload multiple images with duplicate skipping
  Future<Map<String, String>> uploadMultipleImages(
    List<String> imagePaths,
    String sessionId,
  ) async {
    await _ensureBox();

    final Map<String, String> uploadedUrls = {};
    int skippedCount = 0;

    for (final path in imagePaths) {
      if (_uploadedCache.containsKey(path)) {
        skippedCount++;
        if (kDebugMode) debugPrint('✅ Already uploaded, skipping: $path');
        uploadedUrls[path] = _uploadedCache[path]!;
        continue;
      }

      final url = await uploadImage(path, sessionId);
      if (url != null) uploadedUrls[path] = url;
    }

    if (kDebugMode) {
      debugPrint(
        '⚡ Upload complete for session $sessionId. Skipped $skippedCount duplicate image(s).',
      );
    }

    return uploadedUrls;
  }

  // ---------FOR DELETE (NOT USED; NEED CLOUDINARY API)-----------
  // static Future<void> deleteImage(String imageUrl) async {
  //   try {
  //     final publicId = extractPublicId(imageUrl);
  //     await cloudinary.v2.api.deleteResources([publicId]);
  //   } catch (e) {
  //     print("Failed to delete Cloudinary image: $e");
  //   }
  // }

  // static String extractPublicId(String url) {
  //   final segments = Uri.parse(url).pathSegments;
  //   return segments.last.split('.').first; // crude but works if consistent
  // }
}
