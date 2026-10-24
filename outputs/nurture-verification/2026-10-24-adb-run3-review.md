# Kiểm tra nuôi lần lượt qua ADB — 24/10/2026 (14:46–14:59)

Máy ảo `emulator-5554` (API 28, 1440×2960), `com.brisklane.browser`, APK debug cài lúc 12:16 (khớp mã nguồn hiện tại, không build lại). Đã kiểm tra dịch vụ Trợ năng đang bật trước khi chạy. Sao lưu DB trước khi chạy (`integrity_check` = ok). Theo dõi chỉ bằng `screencap` mỗi 15 giây, `logcat` và đọc SQLite; không dùng `uiautomator`, không thao tác trên trang khi đang chạy.

Lúc 14:46:40 bấm **Chạy nuôi lần lượt các tài khoản** qua ADB. Hàng đợi 5 → 1 → 4 kết thúc khoảng 14:52, thông báo **"Đã tự nuôi 3 cấu hình: 2 xong, 1 lỗi"**. Cấu hình 4 lỗi ngay khi mở, khớp với lỗi proxy 402 đã biết.

Từ 14:52:47 có thêm một lượt nuôi cấu hình 5 → 1 **không do ADB khởi động**. Danh sách trên màn hình đã được cuộn và chọn cấu hình 5. Tỷ lệ bình luận của cấu hình 5 cũng đổi từ 20% sang 50% trong khoảng thời gian chạy. Có thể đã có người thao tác trực tiếp trên máy ảo. Bảng dưới vẫn ghi lượt này, tách riêng.

## Phiên mới (SQLite `nurture_sessions`)

| Lượt | Cấu hình | Chế độ | Từ khóa | Thời lượng (giây) | Xem (giây) | Video | Tim | Bình luận |
|---|---|---|---|---:|---:|---:|---:|---:|
| ADB | 5 | search | Fashion | 130 | 47 | 6 | 1 | 0 |
| ADB | 1 | search | Pet care | 159 | 61 | 1 | 0 | 0 |
| ADB | 4 | — | — | lỗi mở (proxy) | — | — | — | — |
| Thêm | 5 | search | Travel in Vietnam | 129 | 59 | 4 | 1 | 0 |
| Thêm | 1 | feed | — | 169 | 162 | 2 | 0 | 0 |

Tất cả các phiên có phase `completed`. Không có AndroidRuntime FATAL; tiến trình chính không chết. Hàng đợi tự chuyển tài khoản đúng.

## Hoạt động đúng

- CAPTCHA xoay: lần đầu (cấu hình 5) xuất hiện hộp thoại Verifying 2 lần; app thử 3 lần (14:47:21–14:47:39) rồi qua được, không đóng CAPTCHA. Phiên sau qua ngay sau 1 lần thử.
- Search mở kết quả, chuyển video bằng Next đã xác minh. Thả tim thành công 2 lần (cấu hình 5).
- Cấu hình 4 lỗi proxy được tính là lỗi và hàng đợi đi tiếp.

## Vấn đề

1. **Thời gian xem thấp ở Search**: chỉ 47–61 giây trên 129–159 giây phiên. Cấu hình 1 (Pet care) sau Next lúc 14:50:46 đọc `unreadable clocks=[]`. Trình phát đen, đang dừng ở nút Play (`2026-10-24-adb-run3-search-paused.png`). App chờ tới 14:51:41 rồi báo "Nhiều bài liên tiếp không đọc được tiến độ", nên phiên hết hạn mà chỉ xem 1 video. Tiến trình `media` của Gecko chết nhiều lần (14:48:32, 14:49:02, 14:54:57, 14:58:05; `fore SVC`). Cần điều tra xem video không phát có trùng thời điểm tiến trình media chết không.
2. **Bình luận Search vẫn bị bỏ qua** (`post-offscreen`, 14:49:59), như các lần trước. Chưa có bình luận nào trong lượt này.
3. **Feed không tương tác**: phiên Feed cấu hình 1 xem tốt (162/169 giây), nhưng sau mỗi Next đều báo `card geometry unsettled; like/comment wait for it`, nên 0 tim và 0 bình luận. Đây là hành vi an toàn đã chọn khi geometry Gecko lệch, nhưng trên máy ảo nó làm mất toàn bộ tương tác sau video đầu.
4. Lỗi Gecko `WindowEventDispatcher, win is null` khi đóng phiên vẫn còn (4 lần), không gây crash.
5. Tổng kết hàng đợi báo "2 xong" dù phiên Search chỉ xem 61/159 giây. Chưa có cảnh báo chất lượng phiên.

## Bằng chứng

- `2026-10-24-adb-run3-sessions.json`: số liệu các phiên mới.
- `2026-10-24-adb-run3-nurture.log`: log Nurture/Diag đã lọc; đã bỏ Remote Config, khóa và IP proxy.
- `2026-10-24-adb-run3-queue-summary.png`: thông báo kết thúc hàng đợi.
- `2026-10-24-adb-run3-search-paused.png`: trình phát Search đen sau Next.
