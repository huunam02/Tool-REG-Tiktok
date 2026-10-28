# Đăng ký Android bằng tọa độ và Accessibility

Cập nhật 17/10/2026. Nhánh: `experiment/android-signup-fixed-viewport-accessibility`.

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
Trước thao tác đầu, app chờ WebView tải xong ít nhất 5 giây và nút ổn định
2 giây. Nếu popup **Log in to TikTok** đã mở, app kiểm tra nút **Sign up**
trong popup rồi tiếp tục từ đó; nếu đã ở **Sign up for TikTok**, app kiểm tra
**Use phone or email**. Popup xuất hiện trong lúc chờ cũng được nhận diện lại,
ưu tiên hơn các nút trang chủ còn lộ trong Accessibility. Không bấm Log in
phía sau popup. Vẫn dừng nếu nút bị tắt, lệch tọa độ hoặc trang chưa tải xong.
Nếu sau 60 giây trang vẫn không có nút Log in/Sign up (trang treo, chỉ hiện
video), app tải lại trang **một lần** rồi chạy lại từ đầu với phiên và proxy
cũ; lúc đó chưa nhập hay gửi gì. Lần thứ hai vẫn treo thì báo lỗi; khi chạy
lần lượt, cấu hình được ghi vào Cấu hình lỗi và app chuyển sang cấu hình kế.

Đã xác nhận lỗi chờ Log in trên phiên giả lập: snapshot chỉ có popup đăng nhập,
không còn control Log in của trang chủ. Sau hot reload, chạy bộ runner mới từ
popup đó đã qua Sign up → Use phone or email → biểu mẫu ngày sinh/số điện thoại.
Phép kiểm chứng hủy runner khi mở biểu mẫu, trước nhập dữ liệu hoặc gửi OTP.
Snapshot cuối ở `outputs/signup-calibration/entry-modal-fixed-verified.json`:
ô Phone number có độ dài 0, Send code đang tắt. Đây là kiểm chứng riêng bước
vào đăng ký, chưa phải phát lại trọn luồng.

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

### Khung desktop (GeckoView), từ 27/10/2026: không còn JavaScript

GeckoView đưa các mục của danh sách mở vào Accessibility dưới dạng `MenuItem`
(bounds không bị cắt). App không còn đọc listbox bằng JavaScript. Geometry đo
trên Galaxy S8 AVD lưu ở `desktop.birthdayMenu` trong
`assets/signup-coordinate-profile.json`: vùng nhìn thấy y 404,9–695,1, mỗi
mục 34,075, scroller cao 320,7 (Month dừng sau 88,2), cột Month/Day/Year, danh
sách mở ở 2025 (năm hiện tại − 1)/January/1, và mỗi lần vuốt 80% → 20% cuộn
đúng 128,28 (16/16 lần đo).

Mặc định app **tính sẵn** số lần vuốt và điểm chạm rồi bấm thẳng vào hàng, không
đọc danh sách; chỉ đọc giá trị ô Year/Month/Day sau khi chọn. **Chỉ khi lỗi**
(ô chưa hiện đúng giá trị) mới mở lại (`reopen-*`) và đọc các `MenuItem` qua
Accessibility để cuộn và chọn lại. Ngày cuối tháng có thể nằm ở chỗ độ dài danh
sách 28–31 làm vị trí khác nhau thì đọc danh sách ngay. Kiểm chứng 27/10: 9 lần
đăng ký dừng trước email chọn đúng 27/27 trường (26 theo vị trí tính sẵn, 1 ngày
28 đọc danh sách); một bản cố ý sai số đo đã tự sửa Year 1971 và Day 24.

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

Sau mỗi thao tác bấm, chọn mục ngày sinh, cuộn dropdown, dán email/mật khẩu
hoặc đóng bàn phím, bộ chạy chờ ngẫu nhiên **2–7 giây** trước thao tác tiếp.
Riêng ngay sau khi dán OTP vẫn chờ **650 ms** như trước để chuyển sang bước
xác minh/mật khẩu. Nhịp kiểm tra trạng thái, chờ API OTP và điều kiện trang
ổn định trước thao tác đầu tiên giữ nguyên. Hủy trong lúc delay sẽ chặn
thao tác tiếp theo.

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
