// Stub for non-web platforms
Future<Map<String, dynamic>> uploadImageToFirebaseViaJs(List<int> bytes, String filename, String contentType) async {
  return {'success': false, 'message': 'JS interop not available on this platform'};
}
