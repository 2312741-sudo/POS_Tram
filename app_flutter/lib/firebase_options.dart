// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with the shared Trạm Ecosystem project: chamcongtram
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return android;
    }
  }

  // Cấu hình Web (Next.js Dashboard hoặc Flutter Web)

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBWSS2o1ERO1HBnAyVZwAbzOSWNkkWa7GY',
    appId: '1:866082811261:web:5021e5e77a7a6cf50ef014',
    messagingSenderId: '866082811261',
    projectId: 'tramapp-36f53',
    authDomain: 'tramapp-36f53.firebaseapp.com',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tramapp-36f53.firebasestorage.app',
    measurementId: 'G-SSEBJMPH77',
  );
  // Cấu hình Android

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyClGB5QKIA1ux-Q0D8FD1woFT4iE524xo0',
    appId: '1:866082811261:android:75d1b3154331c8ba0ef014',
    messagingSenderId: '866082811261',
    projectId: 'tramapp-36f53',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tramapp-36f53.firebasestorage.app',
  );
  // Cấu hình iOS / macOS
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAwrAw9XiRdTLqd31aEzy-wvc9OVyngY3w',
    appId: '1:866082811261:ios:8fd6c7615b32ed6e0ef014',
    messagingSenderId: '866082811261',
    projectId: 'tramapp-36f53',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'tramapp-36f53.firebasestorage.app',
    iosBundleId: 'com.tramapp.tramFlutter',
  );
}
