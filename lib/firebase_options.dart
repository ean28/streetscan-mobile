import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
  show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'core/utils/app_env.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyWeb,
        appId: AppEnv.firebaseAppIdWeb,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        authDomain: AppEnv.firebaseAuthDomain,
        storageBucket: AppEnv.firebaseStorageBucket,
        measurementId: AppEnv.firebaseMeasurementId,
      );

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyAndroid,
        appId: AppEnv.firebaseAppIdAndroid,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyIos,
        appId: AppEnv.firebaseAppIdIos,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
        iosBundleId: AppEnv.firebaseIosBundleId,
      );

  static FirebaseOptions get macos => FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyMacos,
        appId: AppEnv.firebaseAppIdMacos,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        storageBucket: AppEnv.firebaseStorageBucket,
        iosBundleId: AppEnv.firebaseMacosBundleId,
      );

  static FirebaseOptions get windows => FirebaseOptions(
        apiKey: AppEnv.firebaseApiKeyWindows,
        appId: AppEnv.firebaseAppIdWindows,
        messagingSenderId: AppEnv.firebaseMessagingSenderId,
        projectId: AppEnv.firebaseProjectId,
        authDomain: AppEnv.firebaseAuthDomainWindows,
        storageBucket: AppEnv.firebaseStorageBucket,
        measurementId: AppEnv.firebaseMeasurementIdWindows,
      );
}
