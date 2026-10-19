# Tọa độ đăng nhập Android

Ghi thực tế ngày 17/10/2026 trên Pixel 9 Android emulator, 1080×2424,
density 420. `StandardSignupViewport` dùng `flutter_screenutil` với khung thật
400×800, tỷ lệ 1:2; WebView desktop rộng 980 CSS px, khóa zoom. Cùng layout
và cấu hình viewport với đăng ký tự động. Không dùng Transform/FittedBox.

## Các điểm đã ghi

Profile: [`assets/login-coordinate-profile.json`](../assets/login-coordinate-profile.json).
Snapshot đã che dữ liệu: `outputs/login-calibration/`.

| Bước | X | Y |
| --- | ---: | ---: |
| Log in trên trang chủ | 370.95 | 19.68 |
| Use phone or email | 202.06 | 369.45 |
| Username or email | 217.62 | 347.14 |
| Ô tài khoản | 202.06 | 379.38 |
| Ô mật khẩu | 202.06 | 404.12 |
| Continue gửi mật khẩu | 202.06 | 452.11 |
| Quay lại chọn phương thức (ghi mẫu) | 125.40 | 297.47 |
| Xóa email cũ (ghi mẫu) | 260.73 | 379.19 |
| Email xác minh | 198.69 | 362.32 |
| Ô OTP | 197.56 | 354.26 |
| Next xác nhận OTP | 197.38 | 410.31 |
| Resend code | 125.21 | 377.69 |

Đã chạm các bước trên bằng Accessibility, dán tài khoản/mật khẩu và xác nhận
Continue được bật. Tọa độ các ô giữ nguyên khi bàn phím mở/đóng. Gửi Continue
một lần cho mỗi tài khoản được cung cấp; TikTok trả lỗi tài khoản hoặc mật
khẩu không khớp với hai tài khoản đầu. Không gửi lại cùng thông tin.
Tài khoản thứ ba đã qua mật khẩu và tới **Verify it’s really you**. Đã ghi
Email xác minh, chạm một lần, thấy **Enter 6-digit code**, Resend code đang
đếm ngược và Next tắt. Đã ghi tọa độ ô OTP và Next từ màn này. Chọn Email
tự gửi mã, không có Send code riêng. Đã nhập OTP do người dùng cung cấp bằng
Accessibility, kiểm tra Next bật và chạm một lần theo điểm đã ghi. Trang chủ
hiện Messages + Profile, hộp xác minh biến mất: **lượt ghi mẫu đăng nhập đã
thành công**. Profile có đủ 12 điểm đã quan sát, bao gồm 2 điểm hỗ trợ ghi mẫu.
Resend code được đo khi nút bật; không cần bấm gửi lại trong lượt thành công.
Phát lại hoàn toàn không can thiệp và API OTP thật vẫn chưa được kiểm chứng.
Không dùng tọa độ đăng ký để giả định vị trí các bước xác minh đăng nhập.

## Phát lại và lưu lần đầu

`LoginCoordinateProfile.load()` nạp asset và các điểm ghi thêm trong
`SharedPreferences` (khóa `login_coordinate_profile_v1`). Bộ chạy luôn dùng
điểm đã lưu, quy đổi theo bounds WebView 1:2. Node Accessibility chỉ xác nhận
control hiện tại đúng nhãn, được bật và chứa điểm đó. Nếu control lệch khỏi
điểm cũ, dừng để ghi lại; không tự chuyển sang điểm mới.

Nếu một biến thể mới chưa có điểm (chẳng hạn Send code riêng), app ghi tâm
control từ snapshot Accessibility và lưu
**trước** thao tác đầu. Các lượt sau dùng điểm này. Profile không lưu tài khoản,
mật khẩu hoặc mã OTP. Menu Paste của Android và đóng bàn phím do helper
Accessibility xử lý; vị trí menu hệ thống phụ thuộc IME, không thuộc viewport web.

Luồng đăng nhập Android không dùng JS/DOM để tìm tọa độ, chạm, nhập hoặc
xác nhận kết quả. Các script bảo vệ WebView/cấu hình trình duyệt vẫn áp dụng
khi tạo WebView; Auto nuôi chạy riêng sau khi xác nhận đăng nhập thành công.

## Gửi lại mã tối đa một lần

Khi API báo HTTP 408, hết thời gian chờ request, hoặc reader không trả kết quả
trong `waitSeconds + 15`, runner hủy request cũ và chờ Resend code được bật
(tối đa 75 giây). Runner chạm đúng điểm đã lưu bằng Accessibility **một lần
trong mỗi lượt đăng nhập**. Sau đó chờ TikTok tắt Resend code và hiện bộ đếm
gửi lại (tối đa 15 giây), rồi mới tạo request API mới. Phản hồi muộn từ request
cũ bị bỏ qua; mã cũ trong controller được xóa.

Nếu lần chờ OTP thứ hai cũng hết hạn, app dừng và báo đã gửi lại 1 lần, không
bấm thêm. Lỗi token/hộp thư/kết nối, CAPTCHA, rời trang, app ra nền, nút không
sẵn sàng hoặc không có phản hồi sau gesture đều dừng; không dùng các lỗi này
để gửi lại. Nếu ô OTP có bản nháp, không xóa hay gửi lại mã. Kiểm thử xác minh
giới hạn một gesture, request mới sau phản hồi, hủy tác vụ và API treo.

## Công cụ ghi mẫu

`flutter run -t tools/login_calibration_main.dart -d emulator-5554` mở trang
TikTok trong khung chuẩn, không tự nhập tài khoản hay gửi biểu mẫu.
`tools/login_calibrate.py` đọc snapshot và chạm qua bridge debug của plugin.

```sh
python3 tools/login_calibrate.py snapshot current
python3 tools/login_calibrate.py record select-verification-email Email --tap
python3 tools/login_calibrate.py record send-code 'Send code' --tap
python3 tools/login_calibrate.py record focus-otp --editor otp
python3 tools/login_calibrate.py record submit-otp Next
python3 tools/login_calibrate.py export
```

Gặp nhãn trùng, dùng `--id` từ snapshot. `--allow-disabled` chỉ ghi geometry;
không được kết hợp để bấm nút tắt. `export` chép điểm ghi trên thiết bị về asset
để các bản cài tiếp theo dùng lại. Chỉ đánh dấu hoàn chỉnh sau khi đã quan sát
và kiểm chứng các bước xác minh thật.
