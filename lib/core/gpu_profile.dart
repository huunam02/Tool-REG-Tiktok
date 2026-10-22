import 'dart:math';

import 'device_memory.dart';

/// The WebGL GPU a configuration reports to pages (UNMASKED_VENDOR_WEBGL and
/// UNMASKED_RENDERER_WEBGL), as Firefox (GeckoView) on that Android phone
/// reports it. Only Snapdragon phones, each paired with its chip's Adreno.
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

  /// The GPU maker as the driver names it: `Qualcomm`.
  final String vendor;

  /// The GPU as the driver names it, e.g. `Adreno (TM) 610`.
  final String renderer;

  /// Firefox on Android passes the driver's vendor through, e.g. `Qualcomm`
  /// (checked on a real phone).
  String get webGlVendor => vendor;

  /// Firefox buckets the renderer to limit fingerprinting: every Adreno
  /// 6xx/7xx reads `Adreno (TM) 650, or similar`, as on a real phone.
  String get webGlRenderer => '${firefoxRendererBucket(renderer)}, or similar';

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
    'galaxy-s24-ultra',
    'Samsung Galaxy S24 Ultra',
    'Qualcomm',
    'Adreno (TM) 750',
    [12],
  );

  /// Snapdragon phones only (Qualcomm Adreno).
  static const all = [
    fallback,
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
      'galaxy-s22',
      'Samsung Galaxy S22',
      'Qualcomm',
      'Adreno (TM) 730',
      [8],
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
      'galaxy-s20-fe',
      'Samsung Galaxy S20 FE 5G',
      'Qualcomm',
      'Adreno (TM) 650',
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
    GpuProfile(
      'galaxy-a52s',
      'Samsung Galaxy A52s',
      'Qualcomm',
      'Adreno (TM) 642L',
      [6, 8],
    ),
    GpuProfile(
      'galaxy-m23',
      'Samsung Galaxy M23 5G',
      'Qualcomm',
      'Adreno (TM) 619',
      [4, 6, 8],
    ),
    GpuProfile(
      'galaxy-a23',
      'Samsung Galaxy A23',
      'Qualcomm',
      'Adreno (TM) 610',
      [4, 6, 8],
    ),
    GpuProfile('pixel-5', 'Google Pixel 5', 'Qualcomm', 'Adreno (TM) 620', [8]),
    GpuProfile('pixel-4a', 'Google Pixel 4a', 'Qualcomm', 'Adreno (TM) 618', [
      6,
    ]),
    GpuProfile('pixel-4', 'Google Pixel 4', 'Qualcomm', 'Adreno (TM) 640', [6]),
    GpuProfile('pixel-3', 'Google Pixel 3', 'Qualcomm', 'Adreno (TM) 630', [4]),
    GpuProfile('xiaomi-14', 'Xiaomi 14', 'Qualcomm', 'Adreno (TM) 750', [
      8,
      12,
      16,
    ]),
    GpuProfile('xiaomi-13', 'Xiaomi 13', 'Qualcomm', 'Adreno (TM) 740', [
      8,
      12,
    ]),
    GpuProfile('xiaomi-12', 'Xiaomi 12', 'Qualcomm', 'Adreno (TM) 730', [
      8,
      12,
    ]),
    GpuProfile(
      'xiaomi-11t-pro',
      'Xiaomi 11T Pro',
      'Qualcomm',
      'Adreno (TM) 660',
      [8, 12],
    ),
    GpuProfile(
      'redmi-note-13-pro',
      'Xiaomi Redmi Note 13 Pro 5G',
      'Qualcomm',
      'Adreno (TM) 710',
      [8, 12],
    ),
    GpuProfile(
      'redmi-note-13',
      'Xiaomi Redmi Note 13',
      'Qualcomm',
      'Adreno (TM) 610',
      [6, 8],
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
    GpuProfile(
      'redmi-note-10',
      'Xiaomi Redmi Note 10',
      'Qualcomm',
      'Adreno (TM) 612',
      [4, 6],
    ),
    GpuProfile(
      'redmi-12-5g',
      'Xiaomi Redmi 12 5G',
      'Qualcomm',
      'Adreno (TM) 613',
      [4, 6, 8],
    ),
    GpuProfile('redmi-10c', 'Xiaomi Redmi 10C', 'Qualcomm', 'Adreno (TM) 610', [
      4,
      6,
    ]),
    GpuProfile('poco-f5', 'Xiaomi POCO F5', 'Qualcomm', 'Adreno (TM) 725', [
      8,
      12,
    ]),
    GpuProfile('poco-x5', 'Xiaomi POCO X5 5G', 'Qualcomm', 'Adreno (TM) 619', [
      6,
      8,
    ]),
    GpuProfile('oneplus-12', 'OnePlus 12', 'Qualcomm', 'Adreno (TM) 750', [
      12,
      16,
    ]),
    GpuProfile('oneplus-11', 'OnePlus 11', 'Qualcomm', 'Adreno (TM) 740', [
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
    GpuProfile('vivo-y36', 'vivo Y36', 'Qualcomm', 'Adreno (TM) 610', [8]),
    GpuProfile(
      'realme-9-pro',
      'realme 9 Pro 5G',
      'Qualcomm',
      'Adreno (TM) 619',
      [6, 8],
    ),
    GpuProfile('honor-x8', 'HONOR X8', 'Qualcomm', 'Adreno (TM) 610', [6, 8]),
    GpuProfile(
      'moto-edge-30',
      'Motorola Edge 30',
      'Qualcomm',
      'Adreno (TM) 642L',
      [6, 8],
    ),
    GpuProfile(
      'moto-g84',
      'Motorola moto g84 5G',
      'Qualcomm',
      'Adreno (TM) 619',
      [8, 12],
    ),
    GpuProfile(
      'moto-g62',
      'Motorola moto g62 5G',
      'Qualcomm',
      'Adreno (TM) 619',
      [4, 6],
    ),
    GpuProfile(
      'moto-g-stylus-5g-2023',
      'Motorola moto g stylus 5G (2023)',
      'Qualcomm',
      'Adreno (TM) 710',
      [4, 6],
    ),
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

/// Firefox's representative GPU for an Adreno [renderer], ported from
/// dom/canvas/SanitizeRenderer.cpp.
String firefoxRendererBucket(String renderer) {
  final adreno = RegExp(r'Adreno.*?([A-Z]?[0-9]-?[0-9]+)').firstMatch(renderer);
  if (adreno == null) {
    throw ArgumentError.value(renderer, 'renderer', 'Not an Adreno GPU');
  }
  final model = adreno[1]!;
  if (model.startsWith('A')) return 'Adreno (TM) A11';
  if (model.startsWith('X')) return 'Adreno (TM) X1-45';
  final number = int.parse(model);
  return number >= 600
      ? 'Adreno (TM) 650'
      : number >= 500
      ? 'Adreno (TM) 540'
      : number >= 400
      ? 'Adreno (TM) 430'
      : number >= 300
      ? 'Adreno (TM) 330'
      : 'Adreno (TM) 225';
}
