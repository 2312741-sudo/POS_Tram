// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS: return ios;
      default: throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDjsags-PVvGmO8YXC1UMYfnqOa7jAieCg',
    appId: '1:727118636553:web:placeholder',
    messagingSenderId: '727118636553',
    projectId: 'ungdungdidong-94edd',
    databaseURL: 'https://ungdungdidong-94edd-default-rtdb.firebaseio.com',
    storageBucket: 'ungdungdidong-94edd.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDjsags-PVvGmO8YXC1UMYfnqOa7jAieCg',
    appId: '1:727118636553:android:e764015b52caffffee7ad8',
    messagingSenderId: '727118636553',
    projectId: 'ungdungdidong-94edd',
    databaseURL: 'https://ungdungdidong-94edd-default-rtdb.firebaseio.com',
    storageBucket: 'ungdungdidong-94edd.firebasestorage.app',
  );

  // TODO: Add iOS config after downloading GoogleService-Info.plist from Firebase Console
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDjsags-PVvGmO8YXC1UMYfnqOa7jAieCg',
    appId: '1:727118636553:ios:placeholder_replace_with_real',
    messagingSenderId: '727118636553',
    projectId: 'ungdungdidong-94edd',
    databaseURL: 'https://ungdungdidong-94edd-default-rtdb.firebaseio.com',
    storageBucket: 'ungdungdidong-94edd.firebasestorage.app',
    iosBundleId: 'com.tramapp.tramFlutter',
  );
}
