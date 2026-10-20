import 'proxy_store.dart';

/// Configured proxies belong to one account; an unset proxy uses the device
/// network. Cookie isolation is always based on configuration ID.
void validateSignupProxy(
  ProxyProfile profile,
  List<SavedProxy> configurations,
) {
  final proxy = profile.proxy;
  if (proxy == null) return;
  for (final other in configurations) {
    if (other.id == profile.configurationId || other.account == null) continue;
    final allocated = other.proxy;
    if (allocated != null &&
        allocated.uri == proxy.uri &&
        allocated.username == proxy.username) {
      throw FormatException(
        'Proxy của tài khoản này đang được dùng trong cấu hình ${other.name}. Hãy chọn proxy riêng trước khi đăng ký.',
      );
    }
  }
}
