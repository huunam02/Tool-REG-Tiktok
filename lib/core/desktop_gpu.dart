import 'dart:math';

/// A Windows PC's GPU as Firefox 158 reports it over WebGL, measured on a
/// real machine (outputs/firefox-desktop). Each configuration keeps one for
/// life so an account never changes "machine". Keep the ids in step with
/// FirefoxDesktopIdentity.Gpu and desktop_identity.js.
enum DesktopGpu {
  /// The customer's PC (khach-firefox-v2-2026-10-27.json).
  amdR9200('amd-r9-200', 'Windows 10 · AMD Radeon R9 200 Series'),

  /// gpu-intel-hd400-firefox158-2026-10-28.json: remeasured on Firefox 158;
  /// its WebGL limits and extensions confirm the existing profile.
  intelHd400('intel-hd-400', 'Windows 10 · Intel HD Graphics 400'),

  /// gpu-intel-hd-2026-10-28.json, measured on Firefox 158. This renderer
  /// differs from HD Graphics 400; keep both measured groups distinct.
  intelHd('intel-hd', 'Windows 10 · Intel HD Graphics');

  const DesktopGpu(this.id, this.label);
  final String id;
  final String label;

  /// Configurations saved before GPUs were assigned keep the AMD one.
  static const fallback = amdR9200;

  static DesktopGpu byId(String id) =>
      values.firstWhere((gpu) => gpu.id == id, orElse: () => fallback);

  static DesktopGpu random([Random? random]) =>
      values[(random ?? Random()).nextInt(values.length)];
}
