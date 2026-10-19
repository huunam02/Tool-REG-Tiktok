import 'dart:math';

import 'device_memory.dart';

/// The WebGL GPU a configuration reports to pages (UNMASKED_VENDOR_WEBGL and
/// UNMASKED_RENDERER_WEBGL), as Chrome on that Android phone reports it.
/// Each phone is paired with the GPU of the chip it ships with; MediaTek
/// drivers name the core count (MC6), Tensor, Exynos and Adreno do not.
class GpuProfile {
  const GpuProfile(
    this.id,
    this.device,
    this.vendor,
    this.renderer,
    this.ramGb,
  );

  /// Stored with the configuration and exported to Excel.
  final String id;
  final String device;

  /// The GPU maker as the driver names it: `ARM` or `Qualcomm`.
  final String vendor;

  /// The GPU as the driver names it, e.g. `Adreno (TM) 610`.
  final String renderer;

  /// Chrome on Android runs WebGL through ANGLE, which wraps the driver's
  /// names, e.g. `Google Inc. (Qualcomm)`.
  String get webGlVendor => 'Google Inc. ($vendor)';

  /// e.g. `ANGLE (Qualcomm, Adreno (TM) 610, OpenGL ES 3.2)`.
  String get webGlRenderer => 'ANGLE ($vendor, $renderer, OpenGL ES 3.2)';

  /// The RAM sizes (GB) the phone was sold with.
  final List<int> ramGb;

  String get label => '$device · $renderer';

  /// The `navigator.deviceMemory` values this phone reports. Android's usable
  /// RAM is below the nominal size, so Chromium rounds 3 GB to 2, 4–6 GB to
  /// 4 and 8 GB or more to 8.
  Set<double> get deviceMemories => {
    for (final gb in ramGb)
      gb <= 3
          ? 2
          : gb <= 6
          ? 4
          : 8,
  };

  /// Whether this phone could be the one reporting [memory] GB; any phone
  /// fits when the memory is unknown.
  bool fits(double? memory) =>
      memory == null || deviceMemories.contains(memory.clamp(2, 8));

  /// The phones this device can pass for, keeping GPU and RAM consistent.
  /// When no phone matches, the closest memory tier is used.
  static List<GpuProfile> forDevice([double? memory]) {
    memory ??= deviceMemoryGb;
    if (memory == null) return all;
    final fitting = all.where((profile) => profile.fits(memory)).toList();
    if (fitting.isNotEmpty) return fitting;
    double distance(GpuProfile profile) => profile.deviceMemories
        .map((value) => (log(value) - log(memory!)).abs())
        .reduce(min);
    final closest = all.map(distance).reduce(min);
    return all.where((profile) => distance(profile) == closest).toList();
  }

  /// Shown when no configuration is selected; the app's original identity.
  static const fallback = GpuProfile(
    'pixel-9-pro-xl',
    'Google Pixel 9 Pro XL',
    'ARM',
    'Mali-G715',
    [16],
  );

  static const all = [
    fallback,
    GpuProfile('pixel-9', 'Google Pixel 9', 'ARM', 'Mali-G715', [12]),
    GpuProfile('pixel-8-pro', 'Google Pixel 8 Pro', 'ARM', 'Mali-G715', [12]),
    GpuProfile('pixel-8', 'Google Pixel 8', 'ARM', 'Mali-G715', [8]),
    GpuProfile('pixel-8a', 'Google Pixel 8a', 'ARM', 'Mali-G715', [8]),
    GpuProfile('pixel-7-pro', 'Google Pixel 7 Pro', 'ARM', 'Mali-G710', [12]),
    GpuProfile('pixel-7', 'Google Pixel 7', 'ARM', 'Mali-G710', [8]),
    GpuProfile('pixel-7a', 'Google Pixel 7a', 'ARM', 'Mali-G710', [8]),
    GpuProfile('pixel-6-pro', 'Google Pixel 6 Pro', 'ARM', 'Mali-G78', [12]),
    GpuProfile('pixel-6', 'Google Pixel 6', 'ARM', 'Mali-G78', [8]),
    GpuProfile('pixel-6a', 'Google Pixel 6a', 'ARM', 'Mali-G78', [6]),
    GpuProfile('pixel-5', 'Google Pixel 5', 'Qualcomm', 'Adreno (TM) 620', [8]),
    GpuProfile('pixel-4a', 'Google Pixel 4a', 'Qualcomm', 'Adreno (TM) 618', [
      6,
    ]),
    GpuProfile(
      'galaxy-s24-ultra',
      'Samsung Galaxy S24 Ultra',
      'Qualcomm',
      'Adreno (TM) 750',
      [12],
    ),
    GpuProfile(
      'galaxy-s23-ultra',
      'Samsung Galaxy S23 Ultra',
      'Qualcomm',
      'Adreno (TM) 740',
      [8, 12],
    ),
    GpuProfile(
      'galaxy-s23',
      'Samsung Galaxy S23',
      'Qualcomm',
      'Adreno (TM) 740',
      [8],
    ),
    GpuProfile(
      'galaxy-s22-ultra',
      'Samsung Galaxy S22 Ultra',
      'Qualcomm',
      'Adreno (TM) 730',
      [8, 12],
    ),
    GpuProfile(
      'galaxy-s21',
      'Samsung Galaxy S21',
      'Qualcomm',
      'Adreno (TM) 660',
      [8],
    ),
    GpuProfile(
      'galaxy-s21-fe',
      'Samsung Galaxy S21 FE',
      'Qualcomm',
      'Adreno (TM) 660',
      [6, 8],
    ),
    GpuProfile(
      'galaxy-z-flip5',
      'Samsung Galaxy Z Flip5',
      'Qualcomm',
      'Adreno (TM) 740',
      [8],
    ),
    GpuProfile(
      'galaxy-z-fold5',
      'Samsung Galaxy Z Fold5',
      'Qualcomm',
      'Adreno (TM) 740',
      [12],
    ),
    GpuProfile('galaxy-a54', 'Samsung Galaxy A54', 'ARM', 'Mali-G68', [6, 8]),
    GpuProfile('galaxy-a53', 'Samsung Galaxy A53', 'ARM', 'Mali-G68', [
      4,
      6,
      8,
    ]),
    GpuProfile('galaxy-a34', 'Samsung Galaxy A34', 'ARM', 'Mali-G68 MC4', [
      6,
      8,
    ]),
    GpuProfile(
      'galaxy-a52s',
      'Samsung Galaxy A52s',
      'Qualcomm',
      'Adreno (TM) 642L',
      [6, 8],
    ),
    GpuProfile('galaxy-a15', 'Samsung Galaxy A15', 'ARM', 'Mali-G57 MC2', [
      4,
      6,
      8,
    ]),
    GpuProfile('galaxy-a14', 'Samsung Galaxy A14', 'ARM', 'Mali-G52', [
      4,
      6,
      8,
    ]),
    GpuProfile('xiaomi-14', 'Xiaomi 14', 'Qualcomm', 'Adreno (TM) 750', [
      8,
      12,
      16,
    ]),
    GpuProfile('xiaomi-13', 'Xiaomi 13', 'Qualcomm', 'Adreno (TM) 740', [
      8,
      12,
    ]),
    GpuProfile('xiaomi-13t', 'Xiaomi 13T', 'ARM', 'Mali-G610 MC6', [8, 12]),
    GpuProfile('xiaomi-12', 'Xiaomi 12', 'Qualcomm', 'Adreno (TM) 730', [
      8,
      12,
    ]),
    GpuProfile(
      'redmi-note-13-pro',
      'Xiaomi Redmi Note 13 Pro 5G',
      'Qualcomm',
      'Adreno (TM) 710',
      [8, 12],
    ),
    GpuProfile(
      'redmi-note-12',
      'Xiaomi Redmi Note 12',
      'Qualcomm',
      'Adreno (TM) 610',
      [4, 6, 8],
    ),
    GpuProfile(
      'redmi-note-11',
      'Xiaomi Redmi Note 11',
      'Qualcomm',
      'Adreno (TM) 610',
      [4, 6],
    ),
    GpuProfile('redmi-12', 'Xiaomi Redmi 12', 'ARM', 'Mali-G52 MC2', [4, 6, 8]),
    GpuProfile('poco-f5', 'Xiaomi POCO F5', 'Qualcomm', 'Adreno (TM) 725', [
      8,
      12,
    ]),
    GpuProfile('poco-x6-pro', 'Xiaomi POCO X6 Pro', 'ARM', 'Mali-G615 MC6', [
      8,
      12,
    ]),
    GpuProfile('oneplus-12', 'OnePlus 12', 'Qualcomm', 'Adreno (TM) 750', [
      12,
      16,
    ]),
    GpuProfile('oneplus-11', 'OnePlus 11', 'Qualcomm', 'Adreno (TM) 740', [
      8,
      16,
    ]),
    GpuProfile('oneplus-nord-3', 'OnePlus Nord 3', 'ARM', 'Mali-G710 MC10', [
      8,
      16,
    ]),
    GpuProfile(
      'oneplus-nord-ce3-lite',
      'OnePlus Nord CE 3 Lite',
      'Qualcomm',
      'Adreno (TM) 619',
      [8],
    ),
    GpuProfile(
      'oppo-find-x6-pro',
      'OPPO Find X6 Pro',
      'Qualcomm',
      'Adreno (TM) 740',
      [12, 16],
    ),
    GpuProfile('oppo-reno-8-pro', 'OPPO Reno8 Pro', 'ARM', 'Mali-G610 MC6', [
      8,
      12,
    ]),
    GpuProfile('oppo-reno-8', 'OPPO Reno8', 'ARM', 'Mali-G77 MC9', [8]),
    GpuProfile('oppo-a78', 'OPPO A78 5G', 'ARM', 'Mali-G57 MC2', [4, 8]),
    GpuProfile('vivo-v27', 'vivo V27', 'ARM', 'Mali-G610 MC4', [8, 12]),
    GpuProfile('vivo-y36', 'vivo Y36', 'Qualcomm', 'Adreno (TM) 610', [8]),
    GpuProfile('realme-11-pro', 'realme 11 Pro', 'ARM', 'Mali-G68 MC4', [
      8,
      12,
    ]),
    GpuProfile('realme-c55', 'realme C55', 'ARM', 'Mali-G52 MC2', [4, 6, 8]),
    GpuProfile('moto-edge-40', 'Motorola Edge 40', 'ARM', 'Mali-G77 MC9', [8]),
    GpuProfile('xperia-1-v', 'Sony Xperia 1 V', 'Qualcomm', 'Adreno (TM) 740', [
      12,
    ]),
    GpuProfile(
      'xperia-10-v',
      'Sony Xperia 10 V',
      'Qualcomm',
      'Adreno (TM) 619',
      [6],
    ),
    GpuProfile(
      'nothing-phone-2',
      'Nothing Phone (2)',
      'Qualcomm',
      'Adreno (TM) 730',
      [8, 12],
    ),
    GpuProfile('zenfone-10', 'ASUS Zenfone 10', 'Qualcomm', 'Adreno (TM) 740', [
      8,
      16,
    ]),
  ];

  /// Unknown or empty ids fall back to [fallback].
  static GpuProfile byId(String id) =>
      all.where((profile) => profile.id == id.trim()).firstOrNull ?? fallback;

  /// Matches an id or a device name (case-insensitive), as in a backup.
  static GpuProfile? find(String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return null;
    return all
        .where(
          (profile) => profile.id == key || profile.device.toLowerCase() == key,
        )
        .firstOrNull;
  }

  static bool isKnown(String id) =>
      all.any((profile) => profile.id == id.trim());

  /// A random phone that fits this device's RAM.
  static GpuProfile random([Random? generator, double? memory]) {
    final choices = forDevice(memory);
    return choices[(generator ?? Random()).nextInt(choices.length)];
  }

  /// A random phone other than [current] that fits this device's RAM.
  static GpuProfile other(String current, [Random? generator, double? memory]) {
    var choices = forDevice(
      memory,
    ).where((profile) => profile.id != current).toList();
    if (choices.isEmpty) {
      choices = all.where((profile) => profile.id != current).toList();
    }
    return choices[(generator ?? Random()).nextInt(choices.length)];
  }
}
