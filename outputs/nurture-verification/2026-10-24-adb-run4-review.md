# Nuôi lần lượt sau khi sửa lỗi dừng sau CAPTCHA (ADB, 24/10/2026 15:17–15:31)

Bản debug mới gồm sửa `NurtureDialogOpen`: hộp thoại "Verifying..." chỉ làm tạm dừng nuôi rồi chạy tiếp, ở cả chế độ nuôi một tài khoản. Đã cài bằng `adb install -r` lên `emulator-5554` (API 28) và bật lại Trợ năng. Sao lưu DB trước khi cài (`integrity_check` ok).

## Kết quả

Hàng đợi (bấm qua ADB lúc 15:17:27) chạy 5 → 1 → 4 và kết thúc lúc 15:28 với thông báo "2 xong, 1 lỗi". Lúc 15:28:38 có thêm một phiên cấu hình 5 không do ADB khởi động.

| Cấu hình | Chế độ | Bắt đầu | Thời lượng (giây) | Xem (giây) | Video | Tim | Bình luận |
|---|---|---|---:|---:|---:|---:|---:|
| 5 | search "Life hacks" | 15:22:18 | 154 | 123 | 2 | 1 | 0 |
| 1 | feed | 15:25:10 | 172 | 145 | 1 | 0 | 0 |
| 4 | — | — | lỗi proxy 402 | — | — | — | — |
| 5 (thêm) | search "Music" | 15:28:38 | 153 | 8 | 0 | 0 | 0 |

**Đã xác nhận phần sửa CAPTCHA:** có 2 CAPTCHA (15:22:33 Search cấu hình 5, 15:25:21 Feed cấu hình 1), cả hai được giải và nuôi tiếp ngay. Không còn lỗi "đang mở hộp thoại", không có FATAL.

## Vấn đề

1. **Cấu hình 1 không có proxy.** URL proxy trống (đã trống từ trước 14:45). App dùng IP mạng thật `113.190.206.105`, trùng IP public của máy Mac. Đây là thiếu cấu hình, không phải lỗi code; cần nhập proxy cho cấu hình này. Chặn WebRTC/Local IP không bị ảnh hưởng.
2. **Trang trắng khi mở cấu hình 5 lần đầu:** 15:17:42–15:20:43, app báo "Chưa xác nhận được đăng nhập" nên lần đầu bị tính lỗi. Sau đó cấu hình 5 vẫn chạy được ở lượt sau, lúc 15:22 (`2026-10-24-adb-run4-login-blank.png`).
3. **Video Search đứng yên mà runner không phát hiện:** phiên 15:28 đứng ở 00:16/00:25 từ khoảng 15:29:02 tới hết phiên, chỉ xem 8 giây. Lúc 15:29:02 Gecko unbind media service ("Media service has been unbound. Stopping."). Runner chỉ xử lý trường hợp không đọc được đồng hồ, chưa có cơ chế phát hiện đồng hồ đứng yên (`2026-10-24-adb-run4-search-stalled.png`).
4. **Không tăng bình luận** (xem mục dưới).
5. Gecko `WindowEventDispatcher, win is null` khi đóng phiên vẫn còn, không gây crash.

## Vì sao anthanyxa13052004 không tăng bình luận

Tổng các phiên của cấu hình 5 trong SQLite:

| Chế độ | Phiên | Video xem hết | Bình luận |
|---|---:|---:|---:|
| search | 15 | 30 | 0 |
| feed | 12 | 22 | 1 (11:21:06) |

- **Search:** nút Post của trình phát tìm kiếm nằm ngoài mép phải WebView. App bỏ qua bình luận *trước khi dán* (`post-offscreen`, 15:22:57 và 15:24:00), nên tỷ lệ 60% không có tác dụng ở chế độ này. Đây là lỗi #7 chưa sửa trong `2026-10-24-retest2-review.md`.
- **Feed:** sau Next, Gecko giữ vị trí cuộn cũ (`card geometry unsettled`). Runner cố ý không bấm like/bình luận khi khung card lệch, nên chỉ video đầu có cơ hội bình luận. Ở video đầu, bước đặt con trỏ đôi khi hết thời gian chờ ("ô nhập 0/0/0", cấu hình 1 lúc 15:25:27).
- Bình luận chỉ được thử ở video xem hết, và phải trước mốc 50% của video. Điều kiện này giảm thêm số lần thử, nhưng không phải nguyên nhân chính.
