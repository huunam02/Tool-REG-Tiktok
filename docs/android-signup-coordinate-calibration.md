# Đăng ký Android bằng tọa độ và Accessibility

Cập nhật 16/10/2026. Nhánh: `experiment/android-signup-fixed-viewport-accessibility`.

## Kết quả ghi mẫu

Đã thao tác một lượt thật trên Pixel 9 giả lập Android, màn hình 1080×2424,
density 420, bằng cấu hình người dùng chuẩn bị. Lượt này qua OTP, dán mật khẩu,
bấm **Sign up**, tới **Create username**, bấm **Skip**, rồi thấy **Messages** và
**Profile**; nút **Log in** biến mất. Đây là một lượt ghi mẫu thành công,
chưa phải bằng chứng bộ chạy mới đã phát lại toàn bộ không cần can thiệp.

OTP lượt này do người dùng cung cấp. Tự động gọi API OTP chưa được kiểm chứng:
automatic approval review đã chặn request gửi thông tin hộp thư tới API đang
cấu hình. Không dùng đường khác để vượt chặn. App vẫn giữ chức năng API OTP
sẵn có, hoặc dùng `signupOtp` khi cấu hình có mã.

## Viewport và tọa độ

`StandardSignupViewport` dùng `flutter_screenutil`, design size **400×800**,
đặt kích thước thật cho PlatformView và giữ tỷ lệ **1:2** bằng vùng trống khi cần.
Android khóa viewport desktop rộng **980 CSS px**, khóa zoom theo chiều rộng
WebView. Không dùng Transform để phóng PlatformView. Ở lượt đo, WebView có
bounds vật lý `[6, 289, 1073, 2423]`.

Tọa độ lưu theo hệ 400×800 trong
[`assets/signup-coordinate-profile.json`](../assets/signup-coordinate-profile.json).
Khi chạy, app đọc bounds WebView qua Accessibility rồi quy đổi sang tọa độ màn
hình. Trước mỗi lần bấm control, app kiểm tra nhãn, trạng thái bật và bounds.
Các mục trong dropdown ngày sinh được tìm theo nhãn và vị trí đang hiển thị,
rồi đọc lại kết quả lựa chọn. Nếu tỷ lệ hoặc control thay đổi, app dừng để đo lại.
Trước Log in, app chờ WebView tải xong ít nhất 5 giây và nút ổn định 2 giây.

| Bước | X | Y |
| --- | ---: | ---: |
| Log in | 371.13 | 19.31 |
| Sign up trong Login | 233.18 | 501.59 |
| Use phone or email | 199.63 | 347.89 |
| Use email | 145.08 | 422.12 |
| Ô email | 199.81 | 405.44 |
| Send code | 202.06 | 466.17 |
| Ô OTP đầu tiên | 146.39 | 389.32 |
| Ô mật khẩu | 202.06 | 386.13 |
| Sign up sau mật khẩu | 202.06 | 446.30 |
| Skip username | 202.06 | 472.16 |

## Ngày sinh

Mẫu ban đầu chọn **03/02/2001**. Bộ chạy hiện tại chọn năm → tháng → ngày theo
cấu hình, hoặc tạo ngày hợp lệ ngẫu nhiên trong các năm 1960–2004. Sau mỗi
lựa chọn, bộ chạy đọc lại giá trị Spinner trước khi tiếp tục.

Lỗi thực tế ngày 16/10: danh sách năm mở trên màn hình nhưng không có các mục
trong cây Accessibility. Đây là combobox HTML, còn bộ chạy cũ chỉ chờ
ListView/NumberPicker native. Khi không có danh sách native, bộ chạy mới đọc
nhãn và geometry của listbox HTML qua JavaScript chỉ đọc. Các mục ngoài vùng
cuộn, bị modal cắt hoặc bị che được loại bỏ; mọi bấm và vuốt vẫn dùng
`dispatchGesture()`. Không dùng DOM để đặt giá trị, click hoặc cuộn.

Đã hot reload bản sửa vào phiên app đang mở, chạy riêng `selectBirthday()` và
nhận kết quả `ok: true`, ngày **28/10/1967**. Screenshot và snapshot
`outputs/signup-calibration/birthday-fixed-verified.json` xác nhận October/28/1967;
ô email còn trống, Send code chưa được bấm. Kiểm chứng này chưa bao gồm phần
gửi mã, API OTP hoặc đăng ký trọn luồng.

## Nhập dữ liệu

Luồng đăng ký Android mới dùng `flutter_accessibility_service` cho toàn bộ
bấm, vuốt, focus bằng chạm, dán và đóng bàn phím. Không gọi JavaScript/DOM để
điền field hoặc bấm nút đăng ký. Script nhận diện WebView và cấu hình proxy
vẫn được áp dụng trước khi tải trang.

- Email và mật khẩu: clipboard → `ACTION_PASTE` vào editor đang focus;
  kiểm tra email khớp hoặc độ dài mật khẩu khớp. Không ghi đè bản nháp khác.
- OTP: `ACTION_PASTE` trực tiếp từng nhận thành công nhưng sáu ô không được
  điền. Nhấn giữ ô đầu → bấm menu **Paste** bằng `dispatchGesture()` đã điền
  đủ mã và chuyển tới mật khẩu trong lượt thật. Native helper tự tìm bounds
  menu Paste/Dán hiện tại, không cố định tọa độ menu hệ thống.
- Clipboard cũ được khôi phục sau thao tác; snapshot không lưu giá trị editor,
  mật khẩu, email hoặc OTP. Hủy tác vụ cũng chặn bước dán tiếp theo.

Bộ chạy chỉ bấm Send code, Sign up và Skip một lần trong mỗi lượt. Chờ bằng
trạng thái Accessibility; gặp lỗi OTP/email hoặc giới hạn thử thì dừng. Thành
công cần Messages + Profile và không còn Login/form mật khẩu/username.
Nếu đã đăng nhập từ đầu, app không gửi lại biểu mẫu.

## Công cụ và kiểm chứng

`tools/signup_calibrate.py` điều khiển bridge debug bằng ADB để ghi snapshot
và tọa độ. Bridge chỉ đăng ký trong bản debuggable và yêu cầu quyền DUMP của
shell. Chạm/dán đi qua plugin; lệnh vuốt ADB chỉ dùng khi thu thập mẫu.
Không dùng công cụ này để tự thử lại khi TikTok báo giới hạn.

Snapshot đã lọc nằm ở `outputs/signup-calibration/`, chuỗi thao tác ở
`actions.jsonl`. Fixture tối giản trong
`test/fixtures/signup_accessibility_recording.json` phục vụ kiểm thử bộ chạy
theo các trạng thái thực đã thu thập. Các kiểm thử kiểm tra kết thúc thành
công, hủy sau OTP, từ chối paste, sai ngày sinh và tài khoản đã đăng nhập.
Các kiểm thử bổ sung bao gồm dropdown HTML không có mục trong Accessibility,
danh sách năm mở sẵn, ngày nhuận, cuộn không di chuyển và quy đổi tọa độ CSS.

Phạm vi còn cần xác minh: phát lại trọn luồng trên một cấu hình chưa đăng ký,
API OTP, thiết bị/kích thước khác, ngôn ngữ khác tiếng Anh và thay đổi giao
diện từ TikTok. Tỷ lệ chuẩn giúp quy đổi tọa độ nhưng không bảo đảm mọi thiết
bị hoặc mọi phiên bản trang có cùng bố cục.
