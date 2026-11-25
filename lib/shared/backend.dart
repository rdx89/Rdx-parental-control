import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

const _endpoint = String.fromEnvironment('SAFEGUARD_API_URL');
final _http = HttpClient()..connectionTimeout = const Duration(seconds: 12);

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;
}

Future<Map<String, dynamic>> callBackend(
  String operation, [
  Map<String, dynamic> data = const {},
]) async {
  final base = Uri.tryParse(_endpoint);
  if (base == null || base.scheme != 'https' || base.host.isEmpty) {
    throw const BackendException('This build needs a SafeGuard server address.');
  }
  final authorization = operation == 'signup' || operation == 'login'
      ? null
      : await FirebaseAuth.instance.currentUser?.getIdToken();
  final target = base.replace(path: '/api/$operation');
  final request = await _http.postUrl(target);
  request.headers.contentType = ContentType.json;
  if (authorization != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authorization');
  }
  request.write(jsonEncode(data));
  final response = await request.close().timeout(const Duration(seconds: 15));
  final content = await response.transform(utf8.decoder).join()
      .timeout(const Duration(seconds: 15));
  final result = Map<String, dynamic>.from(jsonDecode(content) as Map);
  if (response.statusCode != 200) {
    throw BackendException((result['error'] as String?) ?? 'The server rejected the request.');
  }
  return result;
}

String backendError(Object error) {
  if (error is BackendException) return error.message;
  if (error is FirebaseAuthException &&
      (error.code == 'invalid-credential' || error.code == 'wrong-password')) {
    return 'Mobile number or password is incorrect.';
  }
  return 'The request could not be completed. Check the connection and try again.';
}
