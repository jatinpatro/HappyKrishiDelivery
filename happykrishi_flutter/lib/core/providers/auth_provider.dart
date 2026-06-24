import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../api/dio_client.dart';
import '../api/endpoints.dart';
import '../models/models.dart';
import '../services/fcm_service.dart';

final dioProvider = Provider<Dio>((ref) => buildDioClient());

class AuthState {
  final AppUser? user;
  final bool isInitialized;
  final bool isLoading;
  const AuthState({
    this.user,
    this.isInitialized = false,
    this.isLoading = false,
  });
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(dioProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;
  AuthNotifier(this._dio) : super(const AuthState()) {
    _tryRestore();
  }

  Future<void> _tryRestore() async {
    final token = readTokenSync();
    if (token != null) {
      try {
        final res = await _dio.get(Endpoints.me);
        state = AuthState(user: AppUser.fromJson(res.data['user']), isInitialized: true);
        return;
      } catch (_) {
        deleteToken();
      }
    }
    state = const AuthState(isInitialized: true);
  }

  Future<void> refreshUser() async {
    try {
      final res = await _dio.get(Endpoints.me);
      final updated = AppUser.fromJson(res.data['user']);
      state = AuthState(user: updated, isInitialized: true);
    } catch (_) {}
  }

  void setUserFromToken(String token, AppUser user) {
    saveToken(token);
    state = AuthState(user: user, isInitialized: true);
    _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await getFcmToken();
      if (fcmToken != null) {
        await _dio.post(Endpoints.registerFcmToken, data: {'fcm_token': fcmToken});
      }
    } catch (_) {}
  }

  // Update user profile without changing the stored token
  void updateUser(AppUser user) {
    state = AuthState(user: user, isInitialized: true);
  }

  void logout() {
    deleteToken();
    state = const AuthState(isInitialized: true);
  }
}
