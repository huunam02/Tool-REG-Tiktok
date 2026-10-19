import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// This phone's `navigator.deviceMemory` in GB, as Chrome reports it; null
/// until [loadDeviceMemory] succeeds (tests, iOS, unsupported devices).
double? deviceMemoryGb;

const _channel = MethodChannel('test_tiktok/device');

/// Reads the physical RAM once, so each configuration's phone GPU can be one
/// sold with this much RAM.
Future<void> loadDeviceMemory() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final bytes = await _channel.invokeMethod<int>('totalMemory');
    if (bytes != null && bytes > 0) {
      deviceMemoryGb = approximatedDeviceMemoryGb(bytes ~/ (1024 * 1024));
    }
  } catch (_) {
    // Without it every phone GPU stays eligible.
  }
}

/// Chromium's ApproximatedDeviceMemory: the nearest power of two of the
/// physical memory, between 0.25 and 8 GB.
double approximatedDeviceMemoryGb(int physicalMb) {
  if (physicalMb <= 0) return 0.25;
  final lower = 1 << (physicalMb.bitLength - 1);
  final upper = lower * 2;
  final nearest = physicalMb - lower <= upper - physicalMb ? lower : upper;
  return (nearest / 1024).clamp(0.25, 8).toDouble();
}
