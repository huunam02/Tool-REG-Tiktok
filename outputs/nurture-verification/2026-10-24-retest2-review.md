# Kiểm tra lại luồng nuôi lần lượt — 24/10/2026 (10:30–11:37)

Máy ảo `emulator-5554` (Galaxy_S8_API_28, 1440×2960), `com.brisklane.browser`, GeckoView. Theo dõi chỉ bằng ADB: `screencap` mỗi 5 giây, `logcat flutter`, snapshot Trợ năng của app (debug bridge `SIGNUP_CALIBRATE snapshot`, tự chụp khi log báo lỗi). Không dùng `uiautomator`.

Sáu lượt: 5 lượt "Chạy nuôi lần lượt" và 2 phiên riêng cấu hình 5 (lượt cuối nâng tạm bình luận 5 lên 100%, đã trả về 20%). Sao lưu DB trước mỗi lần chỉnh; kiểm tra `integrity_check` = ok.

## Số liệu (SQLite) — `2026-10-24-retest2-sessions.txt`

Trước khi sửa, các phiên chỉ xem được 29–100 giây trên 120–180 giây vì kẹt 30 giây rồi mới phục hồi. Lượt 5 (đủ bản sửa) đạt 120/120 giây cho cả hai cấu hình, không có lỗi phục hồi. Cấu hình 5 lần đầu bình luận thành công lúc 11:21:20 (Feed).

## Lỗi tìm thấy và cách xử lý

| # | Lỗi | Bằng chứng | Nguyên nhân | Xử lý |
|---|---|---|---|---|
| 1 | Cấu hình 4 "Proxy không kết nối được" (mọi lượt) | `retest2-proxy-402.png`; `curl` qua proxy: `CONNECT tunnel failed, response 402` | Gói proxy hết hạn hoặc chưa thanh toán | Gia hạn hoặc đổi proxy. Không sửa code |
| 2 | Search luôn bỏ qua bình luận `post-unavailable` | `retest2-search-post-offscreen.png` | `findPost` native lấy description rỗng thay cho text "Post" | **Đã sửa** (`SignupAccessibilityBridge.findPost`). Lỗi nay chuyển thành #7 |
| 3 | Feed: Gecko giữ vị trí cuộn cũ sau Next. Kẹt 30 giây hoặc chạm lệch | Snapshot 11:21/11:25: cả danh sách card lệch đều 581 px (card cao 2512 = WebView, đỉnh 861 thay vì 280). Nút bình luận tính ra rơi vào chỗ trống → timeout mở khung (11:25:58) | Cache Trợ năng của Gecko lưu vị trí cuộn giữa hoạt ảnh | **Đã sửa an toàn:** chỉ cấp nút like/bình luận khi khung card khớp đỉnh WebView (±3 px) và media/nút nằm trong khung. Khi lệch, vẫn đọc clock để tính giờ xem và chỉ bấm Next của trang (nằm ngoài vùng cuộn). Có đường đọc dự phòng khi Gecko ẩn cả card: chọn card duy nhất có clock đã chạy. Quảng cáo LIVE không clock được nhận diện và bỏ qua sau 10 giây |
| 4 | Search ở cuối video (60/60, 21/21): báo lỗi giả, video không được tính | Log 10:43:37, 11:03:47 | TikTok tự chuyển bài ngay trước khi bấm Next | **Đã sửa:** đọc lại, chờ ≤2 giây khi trình phát đang giữa hai bài. Nếu đã sang bài khác (kể cả bài ảnh, nhận theo URL) thì tính video và không bấm |
| 5 | Feed "TikTok không phát được video này" lặp tới hết hạn | `retest2-playback-error.png` | Runner chỉ chờ trên cùng bài | **Đã sửa:** bỏ qua bài lỗi bằng nút Next đã xác minh, tối đa 3 bài liên tiếp (đếm qua cả các lần tiếp tục). Lúc chờ bài mới không bắt lỗi của bài cũ |
| 6 | Search: bài ảnh (`/photo/`) kẹt 30 giây | `retest2-search-photo.png` | Không có clock; trình phát chỉ nhận URL `/video/` | **Đã sửa:** nhận bài mới theo URL `/video/` hoặc `/photo/`. Bài ảnh bỏ qua sau 10 giây bằng "Go to next video" |
| 7 | Search: Post nằm ngoài mép phải WebView (`post-offscreen`), không cuộn vào được | `retest2-search-post-offscreen.png` | Gecko dựng trình phát rộng hơn màn hình | **Chưa sửa.** Đã thử bấm Post bằng `ACTION_CLICK` (`submitComment`): sau khi dán, Gecko bỏ ô nhập khỏi cây Trợ năng nên không tìm thấy Post. Kết quả là nội dung bị dán rồi dừng (`retest2-search-draft-not-sent.png`, chưa đăng gì). Đã hoàn tác: Search vẫn bỏ qua bình luận trước khi dán và xem tiếp |

## Chưa xử lý / cần quyết định

- **#3, tối ưu hơn:** có thể bù lệch bằng `đỉnh card − đỉnh WebView` (581 px khớp ảnh chụp). Như vậy trên máy ảo các video sau video đầu vẫn có like/bình luận. Cách này dựa trên giả định feed đã snap đúng card. Hiện tại runner chọn không chạm. Trên điện thoại thật trước đây toạ độ đúng, nên không mất tương tác.
- **#7:** cần cách khác để bấm Post của trình phát Search, ví dụ đọc toạ độ bằng JS (chỉ đọc, đúng quy tắc). Cũng có thể chỉ bình luận ở Feed.
- Lỗi đóng session `GeckoViewSessionStore … win is null` vẫn còn. App không crash.

## Test

- 141 test Dart đạt (`nurture_accessibility_runner`, `signup_accessibility`, `tiktok_nurture_recovery`, `tiktok_nurture_settings`, `tiktok_retained_session`, `tiktok_verification_pause`), trong đó có 10 test mới, mỗi test tái hiện một lỗi ở trên. Fixture mới `test/fixtures/nurture_feed_stale_live_ad.json` lấy từ snapshot thật và đã ẩn danh.
- 63 test JS đạt. `flutter analyze` sạch.
