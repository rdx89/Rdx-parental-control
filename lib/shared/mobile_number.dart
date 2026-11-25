/// Accepts Indian mobile numbers and explicitly prefixed international numbers.
String? normalizeMobileNumber(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^0?[6-9]\d{9}$').hasMatch(compact)) {
    return '+91${compact.substring(compact.length - 10)}';
  }
  if (RegExp(r'^91[6-9]\d{9}$').hasMatch(compact)) {
    return '+$compact';
  }
  final international = compact.startsWith('00')
      ? '+${compact.substring(2)}'
      : compact;
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(international)
      ? international
      : null;
}
