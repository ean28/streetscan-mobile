import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static String get mapTilerApiKey => _require('MAPTILER_API_KEY');
  static String get mapTilerMapId =>
      dotenv.maybeGet('MAPTILER_MAP_ID') ?? 'streets';

  static String get cloudinaryCloudName =>
      _require('CLOUDINARY_CLOUD_NAME');
  static String get cloudinaryUploadPreset =>
      _require('CLOUDINARY_UPLOAD_PRESET');

  // Firebase shared
  static String get firebaseMessagingSenderId =>
      _require('FIREBASE_MESSAGING_SENDER_ID');
  static String get firebaseProjectId => _require('FIREBASE_PROJECT_ID');
  static String get firebaseStorageBucket => _require('FIREBASE_STORAGE_BUCKET');

  // Firebase Web
  static String get firebaseApiKeyWeb => _require('FIREBASE_API_KEY_WEB');
  static String get firebaseAppIdWeb => _require('FIREBASE_APP_ID_WEB');
  static String get firebaseAuthDomain => _require('FIREBASE_AUTH_DOMAIN');
  static String? get firebaseMeasurementId =>
      dotenv.maybeGet('FIREBASE_MEASUREMENT_ID');

  // Firebase Android
  static String get firebaseApiKeyAndroid =>
      _require('FIREBASE_API_KEY_ANDROID');
  static String get firebaseAppIdAndroid => _require('FIREBASE_APP_ID_ANDROID');

  // Firebase iOS
  static String get firebaseApiKeyIos => _require('FIREBASE_API_KEY_IOS');
  static String get firebaseAppIdIos => _require('FIREBASE_APP_ID_IOS');
  static String get firebaseIosBundleId => _require('FIREBASE_IOS_BUNDLE_ID');

  // Firebase macOS
  static String get firebaseApiKeyMacos => _require('FIREBASE_API_KEY_MACOS');
  static String get firebaseAppIdMacos => _require('FIREBASE_APP_ID_MACOS');
  static String get firebaseMacosBundleId => _require('FIREBASE_MACOS_BUNDLE_ID');

  // Firebase Windows
  static String get firebaseApiKeyWindows =>
      _require('FIREBASE_API_KEY_WINDOWS');
  static String get firebaseAppIdWindows => _require('FIREBASE_APP_ID_WINDOWS');
  static String get firebaseAuthDomainWindows =>
      _require('FIREBASE_AUTH_DOMAIN_WINDOWS');
  static String? get firebaseMeasurementIdWindows =>
      dotenv.maybeGet('FIREBASE_MEASUREMENT_ID_WINDOWS');

  static String _require(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.trim().isEmpty) {
      throw StateError('Missing required env var: $key');
    }
    return value;
  }
}
