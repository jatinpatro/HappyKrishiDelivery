import 'dart:async';

/// Stub - uploadImageToFirebaseViaJs not used in signed URL flow
/// Kept for API compatibility
Future<Map<String, dynamic>> uploadImageToFirebaseViaJs(
  List<int> bytes,
  String filename,
  String contentType,
) async {
  return {'success': false, 'message': 'Use signed URL flow instead'};
}
