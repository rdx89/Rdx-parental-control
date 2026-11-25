import 'package:cloud_functions/cloud_functions.dart';

Future<Map<String, dynamic>> callBackend(
  String name, [
  Map<String, dynamic> data = const {},
]) async {
  final result = await FirebaseFunctions.instance.httpsCallable(name).call(data);
  return Map<String, dynamic>.from(result.data as Map);
}

String backendError(Object error) {
  if (error is FirebaseFunctionsException && error.message != null) {
    return error.message!;
  }
  return 'The request could not be completed. Check the connection and try again.';
}
