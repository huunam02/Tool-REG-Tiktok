# Tool TikTok — Android

Ứng dụng Flutter này chỉ hỗ trợ Android. Trình duyệt nhúng dùng GeckoView; project không còn iOS, Android WebView hay `flutter_inappwebview`.

## Kiến trúc trình duyệt

- `GeckoView` hiển thị website qua một `AndroidView`.
- Mỗi cấu hình dùng `GeckoSessionSettings.contextId = profile-<id>`, nên cookie, local storage và đăng nhập được lưu bền vững, tách biệt giữa các profile.
- User-Agent được gán cho từng `GeckoSession` bằng `userAgentOverride`.
- WebExtension tích hợp trong `android/app/src/main/assets/gecko_bridge/` thực thi script, chuyển sự kiện JavaScript và gọi handler Flutter.
- Flutter điều khiển native qua `MethodChannel` riêng của từng platform view. API Dart nằm tại `lib/core/gecko_browser.dart`.

## Proxy SOCKS5

Proxy được áp dụng bằng Android `VpnService` và AAR chính thức `hev-socks5-tunnel` trước khi mở GeckoSession. Khi đổi profile, service dừng tunnel cũ và tạo tunnel mới. VPN chỉ route traffic của ứng dụng; địa chỉ máy chủ SOCKS5 bị loại khỏi route VPN để tránh vòng lặp.

Định dạng được hỗ trợ:

```text
socks5://host:port
socks5://username:password@host:port
```

Form import `host:port:username:password` mặc định được hiểu là SOCKS5. Dữ liệu HTTP/HTTPS cũ vẫn đọc được để người dùng sửa, nhưng không thể khởi động tunnel cho tới khi thay bằng endpoint SOCKS5.

Lần đầu bật proxy, Android hiển thị hộp thoại cấp quyền VPN. Android 13 trở lên có thể hỏi thêm quyền thông báo cho foreground service. AAR hiện tại yêu cầu Android 10/API 29 trở lên.

## Build

```bash
./tool/flutterw pub get
./tool/flutterw analyze
./tool/flutterw build apk --debug
```

APK debug được tạo tại `build/app/outputs/flutter-apk/app-debug.apk`.

GeckoView được ghim ở `141.0.20250806102122`, là dòng tương thích với compileSdk 36 của project. `hev-socks5-tunnel.aar` 2.19.1 nằm trong `android/app/libs/`.
