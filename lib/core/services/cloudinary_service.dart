import 'package:cloudinary_public/cloudinary_public.dart';

class CloudinaryService {
  // Initialize Cloudinary with your account details
  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    'ss-img-storage',       // Cloud name from dashboard
    'pothole_upload',       // Upload preset (Unsigned)
    cache: false,
  );

  Future<String?> uploadImage(String imagePath, String sessionId) async {
    try {
      final cloudinaryFile = CloudinaryFile.fromFile(
        imagePath,
        folder: 'potholes/$sessionId', // organize by session
        resourceType: CloudinaryResourceType.Image,
      );

      final response = await _cloudinary.uploadFile(cloudinaryFile);

      return response.secureUrl; // Returns the URL of the uploaded image
    } catch (e) {
      print('❌ Cloudinary upload failed for $imagePath: $e');
      return null;
    }
  }

  /// Upload multiple images
  Future<Map<String, String>> uploadMultipleImages(
      List<String> imagePaths, String sessionId) async {
    final Map<String, String> uploadedUrls = {};

    for (final path in imagePaths) {
      final url = await uploadImage(path, sessionId);
      if (url != null) {
        uploadedUrls[path] = url;
      }
    }

    return uploadedUrls;
  }
  // ---------FOR DELETE(NOT USED; NEED API)-----------
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
