import 'package:dio/dio.dart';

/// Converts any exception into a user-friendly message.
/// Never exposes raw technical details.
String friendlyError(dynamic error) {
  if (error is DioException) {
    // Use structured backend message if available
    final serverMsg = error.response?.data is Map
        ? error.response?.data['error'] as String?
        : null;

    switch (error.response?.statusCode) {
      case 400:
        return serverMsg ?? 'Invalid request. Please check your input.';
      case 401:
        return 'Session expired. Please log in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'The requested information could not be found.';
      case 409:
        return serverMsg ?? 'A conflict occurred. Please try again.';
      case 422:
        return serverMsg ?? 'Invalid data submitted.';
      case 429:
        return 'Too many requests. Please wait a moment.';
      case 500:
      case 502:
      case 503:
        return 'Server error. Please try again shortly.';
      default:
        if (serverMsg != null) return serverMsg;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Could not connect to the server. Check your internet.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        return 'Network error. Please try again.';
    }
  }

  return 'Something went wrong. Please try again.';
}

/// Logs the error to console (for server-side or debug tracing).
void logError(String context, dynamic error, [StackTrace? stack]) {
  // ignore: avoid_print
  print('[$context] ${error.runtimeType}: $error');
  if (stack != null) {
    // ignore: avoid_print
    print(stack);
  }
}
