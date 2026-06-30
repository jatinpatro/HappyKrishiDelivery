import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'endpoints.dart';

// Single cached instance — set once at app startup from main.dart
SharedPreferences? _prefs;

// Called by authStateProvider after init so Dio can trigger logout on 401
VoidCallback? _onForceLogout;
void setForceLogoutCallback(VoidCallback cb) => _onForceLogout = cb;

void initDioClient(SharedPreferences prefs) {
  _prefs = prefs;
}

Dio buildDioClient() {
  final dio = Dio(BaseOptions(
    baseUrl: Endpoints.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = _prefs?.getString('jwt_token');
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    },
    onError: (error, handler) {
      if (error.response?.statusCode == 401) {
        _prefs?.remove('jwt_token');
        _onForceLogout?.call();
      }
      handler.next(error);
    },
  ));

  return dio;
}

void saveToken(String token) {
  _prefs?.setString('jwt_token', token);
}

String? readTokenSync() {
  return _prefs?.getString('jwt_token');
}

void deleteToken() {
  _prefs?.remove('jwt_token');
}

// Keep async versions for compatibility but they resolve instantly now
Future<void> saveTokenAsync(String token) async => saveToken(token);
Future<String?> readToken() async => readTokenSync();
Future<void> deleteTokenAsync() async => deleteToken();
