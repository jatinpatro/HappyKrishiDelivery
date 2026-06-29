import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;

// JS function declarations
@JS('firebaseSendPhoneOtp')
external JSPromise<JSString> _jsSendPhoneOtp(String phoneNumber);

@JS('firebaseVerifyPhoneOtp')
external JSPromise<JSString> _jsVerifyPhoneOtp(String code);

/// Result from Firebase web JS bridge
class FirebaseWebResult {
  final bool success;
  final String? token;
  final String? code;
  final String? message;

  FirebaseWebResult({
    required this.success,
    this.token,
    this.code,
    this.message,
  });

  factory FirebaseWebResult.fromJson(Map<String, dynamic> j) => FirebaseWebResult(
        success: j['success'] == true,
        token: j['token'] as String?,
        code: j['code'] as String?,
        message: j['message'] as String?,
      );
}

/// Send OTP to phone number via Firebase JS SDK (web only)
/// Returns FirebaseWebResult with success/error info
Future<FirebaseWebResult> firebaseWebSendOtp(String phone) async {
  assert(kIsWeb, 'firebaseWebSendOtp only works on web');
  try {
    final resultStr = await _jsSendPhoneOtp('+91$phone').toDart;
    final json = _parseJson(resultStr.toDart);
    return FirebaseWebResult.fromJson(json);
  } catch (e) {
    return FirebaseWebResult(
      success: false,
      code: 'js-error',
      message: e.toString(),
    );
  }
}

/// Verify OTP code via Firebase JS SDK (web only)
/// Returns FirebaseWebResult with Firebase token on success
Future<FirebaseWebResult> firebaseWebVerifyOtp(String code) async {
  assert(kIsWeb, 'firebaseWebVerifyOtp only works on web');
  try {
    final resultStr = await _jsVerifyPhoneOtp(code).toDart;
    final json = _parseJson(resultStr.toDart);
    return FirebaseWebResult.fromJson(json);
  } catch (e) {
    return FirebaseWebResult(
      success: false,
      code: 'js-error',
      message: e.toString(),
    );
  }
}

Map<String, dynamic> _parseJson(String s) {
  // Simple JSON parser for our specific response format
  final result = <String, dynamic>{};
  final clean = s.replaceAll('{', '').replaceAll('}', '').trim();
  for (final part in clean.split(',')) {
    final kv = part.trim().split(':');
    if (kv.length >= 2) {
      final key = kv[0].trim().replaceAll('"', '');
      final val = kv.sublist(1).join(':').trim().replaceAll('"', '');
      if (val == 'true') result[key] = true;
      else if (val == 'false') result[key] = false;
      else result[key] = val;
    }
  }
  return result;
}
