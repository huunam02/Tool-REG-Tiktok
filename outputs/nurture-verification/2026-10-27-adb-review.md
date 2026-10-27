# Kiểm tra ADB và sửa luồng nuôi — 27/10/2026

Đã thoát app, cài APK debug từ mã đã sửa bằng `adb install -r`, bật lại Trợ năng,
mở lại và chạy cấu hình **enoch (ID 14)** trên `emulator-5554`, Android 9/API 28,
màn hình 1440×2960. Không xóa dữ liệu, đổi proxy, mật khẩu, tỷ lệ hoặc thời lượng.

## Kết quả sau lần khởi động lại cuối

Phiên Feed bắt đầu khoảng 18:12:34 và kết thúc 18:15:21, giờ Việt Nam.
App tự về Home; controller TikTok được đóng, `opening=false`, `selectingNurture=false`.

| Trạng thái | Thời lượng | Thời gian xem | Video | Xem đầy đủ | Bỏ qua | Tim | Bình luận |
|---|---:|---:|---:|---:|---:|---:|---:|
| completed | 167 giây | 157 giây | 2 | 1 | 1 | 0 | 0 |

Số video là số runner ghi nhận hoàn tất/bỏ qua, không phải mọi bài hiển thị.
Tỷ lệ giữ nguyên: tim 30%, bình luận 20%, xem lâu 50%, thời lượng 2–3 phút.
Lượt ngắn này không phát sinh tim hoặc bình luận; không dùng nó để kết luận hai thao tác đó đã được kiểm chứng trên máy.
Hai lần Next đã chuyển bài, nhận diện cả video ngang và dọc. Không phát hiện AndroidRuntime fatal trong log thu được.

## Lỗi và thay đổi

1. **Bấm nhầm tiêu đề Log in thay vì Continue.** Snapshot thật có tiêu đề dạng
   clickable View. Điểm cũ và việc ưu tiên vùng nhỏ khiến runner chọn tiêu đề.
   Nút gửi giờ phải nằm dưới ô mật khẩu, trong đúng dialog. Đã kiểm chứng trên
   máy: bấm `Continue` tại bounds `(590,1623)–(851,1657)`; enoch qua mật khẩu,
   chọn Email, lấy OTP, nhập mã và bấm Next thành công.
2. **Nhận diện đăng nhập chậm khi Search có placeholder chủ đề gợi ý.** Không
   còn yêu cầu mọi editor phải có hint bắt đầu bằng Search. Vẫn yêu cầu
   Messages/Profile và loại trừ hộp đăng nhập/xác minh. Enoch giữ đăng nhập sau
   các lần đóng/mở lại; không cần gửi lại OTP trong lượt cuối.
3. **CAPTCHA theo khung desktop hiện tại.** Giữ đúng công thức trong
   `tiktok_rotate_captcha_guide.md`; đổi CSS sang màn hình theo riêng hai trục
   và cộng offset WebView. Refresh dùng cùng cách tính, có đủ viewportHeight.
   Test dùng trang 1920×955 và WebView `(0,1186)–(1440,1902)`, cùng viewport có
   offset và CSS transform. Thêm debug `captcha-layout` chỉ đọc geometry, không
   gọi API/kéo/Refresh và không xuất URL ảnh hoặc key.
4. **SadCaptcha HTTP 401.** Lần Search trước sửa đã hiện CAPTCHA xoay thật và
   dịch vụ từ chối yêu cầu. Bản sửa phân biệt 401/402/403, dừng ngay ở HTTP 4xx;
   không thử ba lần với cùng key bị từ chối. HTTP 5xx vẫn có tối đa ba lượt thử.
   Cần cập nhật `sadcaptcha_license_key` hợp lệ trong Firebase Remote Config để
   xác nhận giải CAPTCHA đầu cuối. Chưa có lần giải CAPTCHA thành công trong
   lượt kiểm tra này; phiên Feed cuối không phát sinh CAPTCHA.
5. **Search tổng hợp chỉ hiện LIVE, video nằm dưới viewport.** Tái hiện với
   Painting, trước sửa bị timeout. Thêm tối đa hai cú cuộn trong container kết
   quả đã xác minh có tile video dưới màn hình; không bấm LIVE. Hai test mới
   bao phủ cuộn thành công và cuộn không có tác dụng. Lượt thực tế sau sửa chọn
   Feed ngẫu nhiên, nên phần cuộn Search mới chưa được xác nhận lại trên máy.

Các tài khoản thử trước khi người dùng chỉ định enoch: cấu hình 9 tải trắng,
cấu hình kế tiếp không kết nối được proxy, cấu hình 12 bị TikTok báo lỗi thông
tin đăng nhập. Không sửa thông tin tài khoản hoặc proxy để vượt các lỗi này.

## Kiểm chứng và dữ liệu

- Bộ CAPTCHA/đăng nhập/nuôi: **174 test đạt**. Sau bổ sung hai test Search:
  chạy lại nhóm runner/phục hồi/giữ phiên/xác minh, **142 test đạt**.
- **9 test DOM/CSS thật đạt** trong Chrome headless, không có test bị bỏ qua.
- Analyze các file sửa sạch; `git diff --check` sạch; APK ARM64 build thành công.
- Backup riêng tại `/tmp/nurture-20261027-private/verified-before.tar`, đọc được
  đầy đủ, SQLite `integrity_check=ok`. Không đưa backup/cookie/thông tin đăng
  nhập vào repo. So sánh DB xác nhận các thông tin tài khoản/proxy/thông số nuôi
  giữ nguyên. Project đã có nhiều thay đổi trước lượt này; không hoàn tác chúng.
- Máy Mac ban đầu hết chỗ ghi và máy ảo mất kết nối. Đã xóa file build trung
  gian có thể tạo lại sau khi được cho phép và khởi động lại AVD giữ nguyên dữ
  liệu; không load snapshot và không chạy instrumentation xóa/cài lại app.

Bằng chứng: `2026-10-27-enoch-sessions.json`, `2026-10-27-enoch-final.png`,
`2026-10-27-adb-selected.log` và các file kết quả test/analyze cùng tiền tố.
Log chọn lọc không chứa API key, mật khẩu hoặc mã OTP.
