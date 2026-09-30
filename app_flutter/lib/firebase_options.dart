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
    apiKey: 'AIzaSyA2fvOwEKwkeS9AlDNDCELvtyCx07dE6xM',
    appId: '1:476583007511:web:e374fbbef8fcd541ce1352',
    messagingSenderId: '476583007511',
    projectId: 'chamcongtram',
    authDomain: 'chamcongtram.firebaseapp.com',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'chamcongtram.firebasestorage.app',
    measurementId: 'G-QHWJJWMZR3',
  );

  // Cấu hình Android
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA_1a4BIdre7YzzWYFv-njolhltMDyeitE',
    appId: '1:476583007511:android:1e6061907be9bb65ce1352',
    messagingSenderId: '476583007511',
    projectId: 'chamcongtram',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'chamcongtram.firebasestorage.app',
  );

  // Cấu hình iOS / macOS
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDYayXy1_hUz04C3iJo9-lX2ruAsDMqm50',
    appId: '1:476583007511:ios:53970f3be146a349ce1352',
    messagingSenderId: '476583007511',
    projectId: 'chamcongtram',
    databaseURL: 'https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'chamcongtram.firebasestorage.app',
    iosBundleId: 'com.tram.fnb',
  );
}
