import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

// Returns null for Android/iOS — they use google-services.json / GoogleService-Info.plist automatically
// Only web needs explicit options
FirebaseOptions? get firebaseOptions {
  if (kIsWeb) return _webOptions;
  // Android and iOS: return null so Firebase uses the bundled config files
  return null;
}

const _webOptions = FirebaseOptions(
  apiKey: 'AIzaSyChINmqQI3L0POKI3nyRYyzi6wRVomVWAo',
  authDomain: 'happykrishidelivery.firebaseapp.com',
  projectId: 'happykrishidelivery',
  storageBucket: 'happykrishidelivery.firebasestorage.app',
  messagingSenderId: '231883058856',
  appId: '1:231883058856:web:2a7337d7545a74c53f5c9d',
  measurementId: 'G-YRW9GCFFXR',
);
