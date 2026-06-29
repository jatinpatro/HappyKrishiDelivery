// Stub for non-web platforms — Firebase web bridge not available
import 'dart:async';

class FirebaseWebResult {
  final bool success;
  final String? token;
  final String? code;
  final String? message;
  FirebaseWebResult({required this.success, this.token, this.code, this.message});
}

Future<FirebaseWebResult> firebaseWebSendOtp(String phone) async =>
    FirebaseWebResult(success: false, code: 'not-web', message: 'Not on web platform');

Future<FirebaseWebResult> firebaseWebVerifyOtp(String code) async =>
    FirebaseWebResult(success: false, code: 'not-web', message: 'Not on web platform');
