# Kiểm tra ba bộ GPU trên máy ảo — 28/10/2026

Cả ba bộ được chọn đúng trong GeckoView và trong bảng kỹ thuật của
[WhatIsMyBrowser](https://www.whatismybrowser.com/). Dữ liệu đo sâu vẫn có
sai khác với mẫu Firefox Windows: độ chính xác shader và WebGPU.

Thiết bị: `emulator-5554`, Android 9 / API 28, ARM64. Đã build và cài bản debug
hiện tại. Bài kiểm tra dùng `GeckoPlatformView` của app trong Activity kiểm tra
có hiển thị, truyền lần lượt ba mã GPU và dùng context tạm riêng. Không thay
đổi các cấu hình/tài khoản đã lưu trong database và không thử đăng nhập TikTok.

| Bộ GPU | WhatIsMyBrowser nhận diện | Vendor/renderer trong bảng kỹ thuật | MAX_SAMPLES WebGL2 | Tham số và danh sách extension WebGL1/2 so với mẫu |
| --- | --- | --- | --- | --- |
| `amd-r9-200` | Firefox 158 on Windows 10 | Đúng AMD Radeon R9 200 Series | 8 — đúng | Khớp |
| `intel-hd-400` | Firefox 158 on Windows 10 | Đúng Intel HD Graphics 400 | 16 — đúng | Khớp |
| `intel-hd` | Firefox 158 on Windows 10 | Đúng Intel HD Graphics | 16 — đúng | Khớp |

Màn hình được báo là 1920×1080, DPR 1, `maxTouchPoints = 0`, ngôn ngữ `en-US, en`.
Số luồng CPU trong window và worker đều là 4, theo CPU native của máy ảo.
WhatIsMyBrowser có cảnh báo phiên bản Firefox 158 đã cũ; app vẫn giữ bản 158
theo lựa chọn của người dùng.

Hai bài instrumentation đã đạt:

- `DesktopGpuWebCheckTest`: mở trang dò v2 và website trực tiếp cho cả ba bộ;
  kiểm tra tên trình duyệt, vendor/renderer, màn hình, cảm ứng và MAX_SAMPLES.
- `FirefoxDesktopIdentityTest`: kiểm tra thông tin ngay từ script đầu tiên,
  iframe, worker và HTTP request headers.

Các bài này xác nhận những mục được kiểm tra, không xác nhận toàn bộ dữ liệu
giống máy Windows thật. Bảng so sánh đầy đủ được lưu trong
[comparison.json](comparison.json), với `fullReferenceMatch = false` cho cả ba bộ.

## Sai khác quan sát được

- Cả WebGL1 và WebGL2 trên cả ba bộ: `VERTEX_SHADER.MEDIUM_FLOAT`,
  `VERTEX_SHADER.LOW_FLOAT`, `FRAGMENT_SHADER.MEDIUM_FLOAT` và
  `FRAGMENT_SHADER.LOW_FLOAT` trả `[15,15,10]`; mẫu Windows là `[127,127,23]`.
  Các trường độ chính xác shader còn lại trong trang dò khớp mẫu.
- `navigator.gpu` tồn tại nhưng `requestAdapter()` trả `null` trên máy ảo;
  trang dò ghi chuỗi `"null"`. Mẫu AMD và Intel HD trên Windows trả adapter
  có 13 feature và `maxTex = 16384`. Bản đo HD400 chính bị hết giờ; bản HD400
  có cảm ứng đo thành công trước đó cũng trả adapter như các mẫu Windows kia.
- Dữ liệu canvas giống nhau giữa cả ba bộ trên máy ảo. Việc chọn GPU không
  thay đổi phần cứng vẽ thực tế.
- Activity kiểm tra dùng khung trình duyệt dọc, viewport đo được là 1920×3264.
  Đây không phải phép kiểm tra khung đăng ký 1920×955 của luồng tự động.
- Mục extension ở bảng trên chỉ xác nhận danh sách từ
  `getSupportedExtensions()`, chưa kiểm tra từng extension có hoạt động đầy đủ.

Không sửa thông số runtime trong lần kiểm tra này. Đã thêm bài kiểm tra web
có thể chạy lại khi cần. Đây là bài opt-in, bật bằng `-e gpuWebCheck true`,
với trang dò được phục vụ ở localhost cổng 8878 và `adb reverse` tương ứng.

## Bằng chứng theo từng bộ

- AMD: [JSON trang dò](amd-r9-200-probe.json),
  [JSON website](amd-r9-200-whatismybrowser.json),
  [ảnh website](amd-r9-200-whatismybrowser.png).
- Intel HD400: [JSON trang dò](intel-hd-400-probe.json),
  [JSON website](intel-hd-400-whatismybrowser.json),
  [ảnh website](intel-hd-400-whatismybrowser.png).
- Intel HD: [JSON trang dò](intel-hd-probe.json),
  [JSON website](intel-hd-whatismybrowser.json),
  [ảnh website](intel-hd-whatismybrowser.png).
- [Kết quả AndroidJUnitRunner của lần chạy web cuối](instrumentation.txt).
