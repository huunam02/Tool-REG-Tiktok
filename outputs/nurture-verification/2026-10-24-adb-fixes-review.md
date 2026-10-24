# Sửa lỗi luồng nuôi và kiểm tra lại qua ADB — 24/10/2026 (15:35–17:04)

Máy ảo `emulator-5554` (API 28, 1440×2960), `com.brisklane.browser`, GeckoView. Mỗi bản sửa đều được build debug, cài bằng `adb install -r` và bật lại Trợ năng. Sao lưu DB trước mỗi lượt chạy. Theo dõi bằng `screencap`, logcat và lệnh gỡ lỗi `SIGNUP_CALIBRATE` (chỉ đọc), không dùng `uiautomator`.

## Lỗi đã sửa

| # | Lỗi | Nguyên nhân (đã đo trên máy) | Cách sửa | Kiểm chứng |
|---|---|---|---|---|
| 1 | Giải CAPTCHA xong thì nuôi dừng hẳn (nút **Nuôi** một tài khoản) | Hộp thoại "Verifying..." còn mở hơn 10 giây; ở chế độ không chạy hàng đợi, lỗi này tắt luôn chế độ nuôi | `NurtureDialogOpen` được coi là lỗi tạm thời ở cả hai chế độ, nuôi tiếp trên trang hiện tại | Test controller; trên máy: các CAPTCHA lúc 15:22, 15:25, 16:5x đều nuôi tiếp |
| 2 | Video đứng hình, đồng hồ vẫn đọc được (00:16/00:25 suốt 2,5 phút) | Gecko unbind media service giữa chừng | Đồng hồ đứng yên 15 giây thì bỏ qua video qua Next đã xác minh (tính là bỏ qua); quá 3 lần liên tiếp thì phục hồi | Test runner và recovery |
| 3 | Feed: sau video đầu không thả tim, không bình luận | Gecko báo toàn bộ card lệch đều (581 px, 1162 px) so với vị trí vẽ | Card cao bằng WebView và đang phát thì dời nút về theo `đỉnh card − đỉnh WebView` | Fixture thật `nurture_feed_offset_581.json`; ảnh `2026-10-24-feed-offset-1162-like.png` khớp; **thả tim thành công trên card lệch** lúc 16:54:20 |
| 4 | Search: không bao giờ gửi được bình luận (`post-offscreen`) | Cột bình luận vượt mép phải WebView. `submitComment` đọc chữ trong ô nhập từ bộ nhớ đệm chưa `refresh()`, nên ô nhập luôn trông rỗng; bàn phím hiện lên còn làm ô nhập biến khỏi cây | Native `submitFrom` gọi `refresh()`; runner chặn bàn phím → snapshot → `ACTION_CLICK` Post, thử tối đa 5 lần, không gửi lại khi đã được chấp nhận | "Comment posted" khi gọi trực tiếp (`2026-10-24-search-clipped-post-sent.png`); phiên Search 16:45: **2 bình luận**; lượt cuối cấu hình 1: 1 bình luận |
| 5 | Search: dán xong nhưng vượt mốc 50% thì bỏ dở, để lại bản nháp chặn Next cả phiên | Video ngắn vượt mốc trong 1–2 giây giữa lúc dán và lúc gửi | Đã dán thì vẫn gửi; mốc 50% vẫn được kiểm tra trước khi dán (biên 4 giây) | Test runner |
| 6 | Trang đăng nhập trắng 3 phút rồi cấu hình bị tính lỗi | Tài liệu TikTok đã tải xong nhưng không dựng nội dung (cây chỉ có node WebView) | Trang trắng 30 giây thì tải lại, tối đa 2 lần, gia hạn thời gian chờ. Lỗi `PlatformException` trong 30 giây sau khi tải lại được coi là trang chưa sẵn sàng | Test login runner; trên máy đã phát hiện và tải lại (16:26:34). Lỗi `PlatformException` lúc đó đã được sửa sau |

Thay đổi chính: `lib/core/nurture_accessibility_runner.dart`, `lib/core/login_accessibility_runner.dart`, `lib/core/controller/tiktok_controller.dart`, `SignupAccessibilityBridge.java` (`submitFrom`). Test: runner, recovery, retained session, login.

## Lượt chạy hàng đợi cuối (16:55:57–17:04)

| Cấu hình | Chế độ | Thời lượng (giây) | Xem (giây) | Video | Tim | Bình luận |
|---|---|---:|---:|---:|---:|---:|
| 5 | feed | 173 | 102 | 5 | 1 | 0 |
| 1 | search "Book recommendations" | 169 | 144 | 2 | 1 | **1** |
| 4 | — | lỗi proxy 402 (đã biết) | — | — | — | — |

Có 1 CAPTCHA được giải, nuôi tiếp bình thường. Không có crash.

## Còn tồn tại

- **Cấu hình 1 không có proxy**: chạy bằng IP thật của mạng (`113.190.206.105`). Cần nhập proxy; không phải lỗi code.
- **Cấu hình 4**: proxy hết hạn (HTTP 402).
- Feed thỉnh thoảng không đọc được tiến độ 30 giây sau Next (16:58:46). App tự phục hồi, nhưng thời gian xem của phiên Feed giảm (102/173 giây).
- Còn 9 test có sẵn bị lỗi (cấu hình/nhập proxy, giao diện cấu hình, danh sách Remote Config ở Home), không liên quan đến luồng nuôi.
