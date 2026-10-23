# Tool TikTok — Android

Ứng dụng Flutter này chỉ hỗ trợ Android. Trình duyệt nhúng dùng GeckoView; project không còn iOS, Android WebView hay `flutter_inappwebview`.

## Kiến trúc trình duyệt

- `GeckoView` hiển thị website qua một `AndroidView`.
- Mỗi cấu hình dùng `GeckoSessionSettings.contextId = profile-<id>`, nên cookie, local storage và đăng nhập được lưu bền vững, tách biệt giữa các profile.
- User-Agent được gán cho từng `GeckoSession` bằng `userAgentOverride`.
- WebExtension tích hợp trong `android/app/src/main/assets/gecko_bridge/` thực thi script, chuyển sự kiện JavaScript và gọi handler Flutter.
- Flutter điều khiển native qua `MethodChannel` riêng của từng platform view. API Dart nằm tại `lib/core/gecko_browser.dart`.

## Proxy HTTP, HTTPS và SOCKS5

Proxy được áp dụng bằng Android `VpnService` trước khi mở GeckoSession. VPN chỉ route traffic của ứng dụng, bao gồm GeckoView và yêu cầu tra IP/múi giờ. Địa chỉ máy chủ proxy bị loại khỏi route VPN để tránh vòng lặp. Khi đổi cấu hình, tunnel và các kết nối của cấu hình cũ được đóng.

**HTTP là mặc định** khi tạo cấu hình hoặc import dữ liệu không ghi giao thức. Chọn giao thức trong form theo thông tin nhà cung cấp. HTTP/HTTPS dùng CONNECT và hỗ trợ tên đăng nhập, mật khẩu Basic. Với HTTPS proxy, kết nối tới máy chủ proxy dùng TLS và xác minh chứng chỉ. HTTP CONNECT chỉ chuyển tiếp TCP; máy chủ cần cho phép CONNECT tới cổng đích.

SOCKS5 dùng `hev-socks5-tunnel` trực tiếp. HTTP/HTTPS dùng cầu nối SOCKS5 cục bộ có thông tin xác thực ngẫu nhiên riêng cho mỗi tunnel; cầu nối chuyển từng kết nối TCP sang HTTP CONNECT.

Định dạng được hỗ trợ:

```text
socks5://host:port
http://host:port
https://host:port
```

Nhập tên đăng nhập và mật khẩu vào các ô riêng. Form import `host:port:username:password` mặc định dùng HTTP. Có thể ghi rõ `http://host:port:username:password` hoặc `socks5://host:port:username:password`. Cấu hình đã lưu với giao thức rõ ràng tiếp tục dùng đúng giao thức đó.

Lần đầu bật proxy, Android hiển thị hộp thoại cấp quyền VPN. Android 13 trở lên có thể hỏi thêm quyền thông báo cho foreground service. Project đặt tối thiểu Android 9/API 28 và có manifest override cho AAR tunnel.

## Build

```bash
./tool/flutterw pub get
./tool/flutterw analyze
./tool/flutterw build apk --debug
```

APK debug được tạo tại `build/app/outputs/flutter-apk/app-debug.apk`.

### Release cho Samsung Galaxy S8 (ARM64)

Galaxy S8 cần chạy Android 9/API 28 trở lên theo cấu hình hiện tại của project. Chạy lệnh sau từ thư mục gốc để build APK release chỉ chứa ARM64, giúp giảm dung lượng so với APK gộp nhiều kiến trúc CPU:

```bash
./tool/flutterw build apk --release --target-platform=android-arm64
```

APK được tạo tại `build/app/outputs/flutter-apk/app-release.apk`. Chép file này sang Galaxy S8 và mở để cài đặt.

Để build kèm báo cáo phân tích dung lượng:

```bash
./tool/flutterw build apk --release --target-platform=android-arm64 --analyze-size
```

GeckoView được ghim ở `158.0.20261021001945`, với compileSdk 37.2. `hev-socks5-tunnel.aar` 2.19.1 nằm trong `android/app/libs/`.
