import 'dart:convert';
import 'dart:js_interop';

@JS('uploadToFirebaseStorage')
external JSPromise<JSString> _jsUploadToStorage(String base64Data, String filename, String contentType);

Future<Map<String, dynamic>> uploadImageToFirebaseViaJs(List<int> bytes, String filename, String contentType) async {
  final base64Data = base64Encode(bytes);
  final resultStr = await _jsUploadToStorage(base64Data, filename, contentType).toDart;
  return (jsonDecode(resultStr.toDart) as Map<String, dynamic>);
}
