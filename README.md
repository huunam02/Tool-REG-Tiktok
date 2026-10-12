

## OTP API

Trong tab **Thiết lập chung**, nút **Xóa phiên và đổi User-Agent** xóa cookie,
dữ liệu WebView và cache, rồi chọn User-Agent mới cho lần mở TikTok tiếp theo.

Khi chạy đăng ký, app tự tạo ngày sinh ngẫu nhiên trong khoảng 1960–2004,
bao gồm ngày hợp lệ theo số ngày của từng tháng và năm nhuận.

App luôn lấy OTP qua API cho **Đăng nhập** và **Đăng ký**. Cấu hình URL và token
trong `lib/config.dart` qua `otpApiUrl` và `otpApiToken`, dùng chung cho hai luồng.
Trong từng tab, nhập mật khẩu hộp thư của email tương ứng.
Mật khẩu hộp thư là trường riêng với mật khẩu TikTok. App tự lấy mã OTP từ API.

App dùng thư viện `http` để gọi `POST /api/code` sau khi TikTok yêu cầu OTP, với JSON
`{"email":"email|mật khẩu hộp thư","wait":180}` và headers
`X-Reader-Token`, `ngrok-skip-browser-warning: 1`. Khi API trả
`{"ok":true,"code":"012345"}`, app dán mã bằng clipboard native rồi xác nhận.
Trong thời gian chờ, app vẫn theo dõi CAPTCHA, lỗi biểu mẫu và nút Dừng.

Trong bản debug, mở **Debug Console** và lọc `[OTP API]` để xem request,
HTTP status, thời gian chờ và response data (bao gồm trường `code`). Token và
mật khẩu hộp thư được che trong log. Bản release không in các log này.

Token được nhập trong màn Cấu hình. Chạy hoặc build từ terminal:

```sh
/Users/huunam/development/flutter_new/flutter/bin/flutter run
/Users/huunam/development/flutter_new/flutter/bin/flutter build apk --debug
```

## Getting Started

Using Flutter 3.41.8. VS Code uses the SDK configured in
`.vscode/settings.json`.

Flutter 3.27.x has an iOS platform-view hot-restart bug that can throw
`PlatformException(recreating_view)` ([Flutter fix](https://github.com/flutter/flutter/pull/164456)).
After changing SDKs, stop the running app and reload the VS Code window before
launching again. For terminal commands on this machine, use
`/Users/huunam/development/flutter_new/flutter/bin/flutter`.
A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
