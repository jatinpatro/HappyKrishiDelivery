import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';

/// Gets the FCM token. Returns null on web or if Firebase is not available.
Future<String?> getFcmToken() async {
  if (kIsWeb) return null;
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    return await messaging.getToken();
  } catch (_) {
    return null;
  }
}
