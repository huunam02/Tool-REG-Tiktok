String normalizeProxyTimeZone(String? value) {
  final zone = value?.trim() ?? '';
  if (zone.isNotEmpty &&
      (zone.length > 100 ||
          !RegExp(
            r'^[A-Za-z][A-Za-z0-9_+\-]*(?:/[A-Za-z0-9_+\-]+)*$',
          ).hasMatch(zone))) {
    throw const FormatException(
      'Nhập mã múi giờ IANA, ví dụ America/New_York.',
    );
  }
  return zone;
}
