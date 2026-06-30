import 'dart:async';
import 'package:dio/dio.dart';
import '../api/endpoints.dart';

/// Uploads image bytes to Firebase Storage via a backend-generated signed URL.
/// Works on both web and mobile — no Firebase SDK needed on client side.
/// [dio] must be the authenticated Dio instance (admin JWT injected).
Future<String?> uploadImageViaSignedUrl({
  required Dio dio,
  required List<int> bytes,
  required String filename,
  required String contentType,
}) async {
  // Step 1: Get signed URL from backend
  final res = await dio.post(Endpoints.adminStorageUploadUrl, data: {
    'filename': filename,
    'contentType': contentType,
  });
  final signedUrl = res.data['signedUrl'] as String;
  final downloadUrl = res.data['downloadUrl'] as String;

  // Step 2: PUT bytes directly to Firebase signed URL (no auth header needed)
  final uploadDio = Dio(); // plain Dio, no auth headers
  await uploadDio.put(
    signedUrl,
    data: Stream.fromIterable(bytes.map((b) => [b])),
    options: Options(
      headers: {
        'Content-Type': contentType,
        'Content-Length': bytes.length,
      },
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  return downloadUrl;
}
