# Phiên đăng nhập riêng theo cấu hình

Cookie TikTok được lưu cục bộ bằng `AccountSessions`, khóa theo ID cấu hình và
email. Hai cấu hình có cùng User-Agent hoặc email vẫn có kho cookie khác
nhau. Thay email trong cùng cấu hình không dùng lại cookie của email cũ.

## Luồng hoạt động

- Không khai báo proxy: đăng ký và nuôi dùng mạng mặc định của máy. App xóa
  proxy override trước khi mở tài khoản, cookie vẫn riêng theo configuration ID.
- Nếu khai báo proxy, trùng địa chỉ và username với cấu hình tài khoản khác sẽ
  bị chặn khi đăng ký. Đổi mật khẩu proxy không tạo allocation
  mới. Gateway cùng địa chỉ nhưng username riêng được xem là allocation riêng;
  app không thể bảo đảm chúng có IP thoát khác nhau nếu nhà cung cấp dùng IP chung.
- Màn Nuôi có nút Nuôi trên từng tài khoản. Bấm nút sẽ chọn đúng configuration ID,
  khôi phục cookie của tài khoản đó và áp dụng proxy cùng credentials đã lưu trước
  khi mở TikTok. Không có proxy thì dùng mạng mặc định của máy.

- Đăng ký bắt đầu với WebView sạch. Sau khi đăng ký thành công, app lưu cookie
  và giữ đăng nhập. Nếu bật nuôi sau đăng ký, app nuôi rồi trở về Home, giữ phiên.
- Trước khi chuyển cấu hình, app lưu cookie của tài khoản hiện tại, xóa
  cookie/storage/cache đang dùng, rồi khôi phục cookie của cấu hình tiếp theo.
- Nuôi mở trang chủ, kiểm tra trạng thái đăng nhập trực tiếp trên TikTok bằng
  Accessibility hoặc JavaScript. Nếu chưa xác nhận sau khoảng 10 giây, app chạy
  luồng đăng nhập sẵn có, bao gồm OTP/CAPTCHA, rồi nuôi khi đăng nhập thành công.
- Cookie hết hạn không được khôi phục. Server vẫn có thể thu hồi cookie chưa
  hết hạn; kiểm tra trang thật và bước đăng nhập lại xử lý trường hợp này.
- Nếu native WebView mất cookie khi khởi động lại, app khôi phục bản đã lưu khi
  mở tài khoản. Phiên từ bản app cũ chỉ được nhận khi trạng thái tài khoản hiện
  tại cho phép tái sử dụng.
- Marker chủ sở hữu được ghi trước khi đổi kho cookie. Nếu xóa/khôi phục bị lỗi
  hoặc app bị tắt giữa chừng, cookie dở dang không được ghi vào kho tài khoản cũ.
- Xóa cấu hình trong giao diện cũng xóa bản cookie đã lưu.

## Phạm vi và giới hạn

Đây là các kho cookie luân phiên trên **một WebView store native**, không phải
nhiều browser profile chạy đồng thời. Cần đóng WebView tài khoản cũ trước khi
đổi cấu hình. Local storage, session storage và IndexedDB không được sao lưu;
app gọi API xóa storage/cache khi đổi cấu hình và khôi phục cookie đăng nhập.

`clearAppSession()` chờ API xóa cookie, xóa WebStorage/dữ liệu website và cache.
Trên Android, `WebStorage.deleteAllData()` không cung cấp callback hoàn tất;
chưa có bằng chứng runtime rằng mọi service worker/Cache Storage đã biến mất
trước lần tải tiếp theo. Vì vậy không khẳng định cách ly toàn bộ dữ liệu browser.
Trên iOS/macOS, API xóa website data chờ completion callback.

Metadata cookie được giữ khi WebView cung cấp: domain, path, expiration,
HttpOnly, Secure và SameSite. Android cũ không hỗ trợ GET_COOKIE_INFO có thể
chỉ trả tên/giá trị; không thể tái tạo chính xác metadata không được cung cấp.
Các cookie được chụp từ URL trang chủ TikTok, không phải bản sao toàn bộ cookie
của mọi domain/path. Không xuất cookie ra Excel hoặc ghi giá trị vào log.

## Kiểm thử

`account_sessions_test.dart` kiểm tra đổi A → B → A, giữ HttpOnly/domain,
khôi phục khi native store trống, cookie hết hạn, đổi email, lỗi khôi phục,
đăng ký mới và xóa kho cookie. `signup_login_nurture_flow_test.dart` kiểm tra
đăng ký/nuôi giữ phiên, bỏ đăng nhập khi trang xác nhận đã đăng nhập và chạy
đăng nhập khi phiên không hợp lệ. Đây là kiểm thử API giả; cần kiểm tra thêm
trên thiết bị thật với TikTok để xác nhận vòng đời cookie/storage của WebView.
