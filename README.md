# Tool TikTok — Android

Ứng dụng Flutter này chỉ hỗ trợ Android. Trình duyệt nhúng dùng GeckoView; project không còn iOS, Android WebView hay `flutter_inappwebview`.

## Kiến trúc trình duyệt

- `GeckoView` hiển thị website qua một `AndroidView`.
- Mỗi cấu hình dùng `GeckoSessionSettings.contextId = profile-<id>`, nên cookie, local storage và đăng nhập được lưu bền vững, tách biệt giữa các profile.
- User-Agent được gán cho từng `GeckoSession` bằng `userAgentOverride`.
- WebExtension tích hợp trong `android/app/src/main/assets/gecko_bridge/` thực thi script, chuyển sự kiện JavaScript và gọi handler Flutter.
- Flutter điều khiển native qua `MethodChannel` riêng của từng platform view. API Dart nằm tại `lib/core/gecko_browser.dart`.

### Nhận diện Firefox desktop

Nhánh này nhận diện là Firefox 158.0 trên Windows 10 x64 (`Win32`), phóng to
trên màn hình phổ biến nhất: 1920 × 1080 / 24 bit, scale 100% (DPR 1), vùng
dùng được 1920 × 1040, cửa sổ 1936 × 1056 ở −8, −8, trang 1920 × 955. Ngôn
ngữ `en-US, en` (runner cần nhãn TikTok tiếng Anh), 0 điểm cảm ứng, sự kiện bấm
báo là chuột. WebGL báo `Google Inc. (AMD)` và
`ANGLE (AMD, Radeon R9 200 Series Direct3D11 vs_5_0 ps_5_0), or similar`, cùng
thông số và extension của Firefox Windows. JavaScript và cookie (kể cả bên thứ
ba) được bật; DNT tắt. WebRTC có API nhưng ICE bị chặn hoàn toàn (không lộ IP
local hay IP thật), kiểm tra bằng `GeckoWebRtcPrivacyTest`. Múi giờ trang theo IP
proxy của cấu hình; không có proxy thì là `Asia/Bangkok` (Windows dùng múi này
cho Việt Nam).

Trang đăng ký xoay ngang và hiển thị trong khung đúng tỉ lệ cửa sổ trên; mật độ
điểm ảnh (`layout.css.devPixelsPerPx`) được tính theo bề rộng khung để trang
luôn rộng đúng 1920 CSS px.

`FirefoxDesktopIdentity.kt` đặt các preference native trước khi tải trang.
WebExtension đặt những thuộc tính chỉ có ở cửa sổ ngay tại `document_start`,
trong mọi frame, không dùng inline script nên hoạt động cả khi trang có CSP.
Các profile GPU điện thoại cũ vẫn được giữ trong dữ liệu backup, nhưng không
còn quyết định WebGL đang dùng; giao diện hiển thị GPU desktop cố định.

Đây là nhận diện được cấu hình trên GeckoView Android, không phải bản Firefox
Windows chạy trên máy tính. Kích thước vùng vẽ thực tế vẫn theo view Android;
font, canvas, codec, GPU thực và khả năng engine không trở thành Windows.
CPU báo 16 chỉ được thay trong document/frame, worker vẫn có thể đọc CPU thật.
Script múi giờ hiện dùng cầu nối bất đồng bộ, nên có thể chạy sau script đầu
tiên của trang hoặc bị CSP của trang chặn. IP, ISP, vị trí, TOR và referrer
phụ thuộc mạng/lần điều hướng, không được giả thành giá trị trong bản đọc.

Kiểm tra native trên thiết bị:

```bash
adb shell am instrument -w -r -e class com.brisklane.browser.gecko.FirefoxDesktopIdentityTest com.brisklane.browser.test/androidx.test.runner.AndroidJUnitRunner
```

Bài kiểm tra đọc giá trị từ script đầu tiên của trang và iframe có CSP,
đối chiếu User-Agent/platform của worker cùng HTTP User-Agent/Accept-Language.

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
./tool/flutter build apk --release --target-platform=android-arm64
```

APK được tạo tại `build/app/outputs/flutter-apk/app-release.apk`. Chép file này sang Galaxy S8 và mở để cài đặt.

Để build kèm báo cáo phân tích dung lượng:

```bash
./tool/flutter build apk --release --target-platform=android-arm64 --analyze-size
```

GeckoView được ghim ở `158.0.20261021001945`, với compileSdk 37.2. `hev-socks5-tunnel.aar` 2.19.1 nằm trong `android/app/libs/`.
