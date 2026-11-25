/// One canonical identity for backup matching. MediaStore ids are unstable,
/// so paths are decoded, slash-normalized, collapsed and lowercased.
String normalizeBackupPath(String raw) {
  var value = raw.replaceAll('\\', '/').trim();
  try {
    value = Uri.decodeFull(value);
  } catch (_) {
    // Keep the raw value when it is not a valid URI escape sequence.
  }
  while (value.contains('//')) {
    value = value.replaceAll('//', '/');
  }
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.toLowerCase();
}
