# Điều tra lỗi đăng ký TikTok tự động trên Android

Cập nhật: 16/10/2026 (giờ Việt Nam).

**Cập nhật mới nhất:** đã tách nhánh
`experiment/android-signup-fixed-viewport-accessibility`, chuẩn hóa WebView
400×800 (1:2), ghi tọa độ và triển khai bộ chạy đăng ký Android dùng hoàn toàn
Accessibility cho thao tác UI. Một lượt ghi mẫu thật đã qua Sign up → Skip →
trang đăng nhập thành công (Messages/Profile, không còn Log in). OTP do người
dùng cung cấp; chưa xác minh phát lại toàn bộ tự động hoặc API OTP.
Đã sửa dropdown ngày sinh HTML không lộ các mục qua Accessibility và kiểm
chứng riêng bước tự chọn **28/10/1967** trên phiên giả lập đang mở.
Chi tiết triển khai và giới hạn kiểm chứng ở
[android-signup-coordinate-calibration.md](android-signup-coordinate-calibration.md).

Các phần bên dưới ghi lại **lịch sử điều tra luồng cũ**. Hai cờ thử nghiệm
nhập tay/bấm tự động không điều khiển nhánh đăng ký Android mới này.

**Cập nhật triển khai:** người dùng đã thử tự nhập bằng app + bấm nút thủ công
và báo vẫn gặp lỗi. Đã bật lại gesture Send code, Sign up sau OTP và Skip bằng
`_pauseSignupGestures = false`. Hiện tạm tắt tự điền bằng
`_pauseSignupFieldInput = true`: người dùng nhập/chọn email, OTP, mật khẩu và
ngày sinh trực tiếp trên TikTok, app tiếp tục tự bấm các nút. Chế độ này không
gọi OTP API hoặc helper tự nhập field. Bước chuẩn bị Send code vẫn focus nút.

**Kết quả người dùng báo sau đó:** nhập field thủ công + app tự bấm vẫn không
thành công, vẫn báo “Maximum number of attempts reached” sau Sign up.
Lượt thành công là **bắt đầu lại từ đầu, tự nhập và bấm toàn bộ**; chưa phải
thử bấm tay tiếp trên cùng màn/phiên tự động lỗi. Chưa xác nhận giữ nguyên email.

**Log đối chiếu mới đọc từ emulator-5554:**

- Lượt tự nhập + bấm tay: 19:12–19:14 có native input email, OTP và mật khẩu;
  chờ bấm tay Send code/Sign up; 19:14:04 ghi nhận lỗi giới hạn.
- Lượt nhập tay + tự bấm (PID 8240): 19:20:25 chờ nhập email; 19:21:06 gửi
  đúng một gesture Send code, hoàn tất; 19:21:10 xác nhận đã gửi mã;
  19:21:12 chờ nhập OTP; 19:22:53 sang màn mật khẩu; 19:22:54 chờ nhập mật khẩu.
- 19:23:16.823 dispatch Sign up; 19:23:17.190 gesture hoàn tất;
  19:23:18.741 ghi nhận lỗi giới hạn. Phần log hiện có chỉ có một yêu cầu
  gesture Sign up ở lượt này; số request mạng chưa được đo.
- Không thấy native input trong lượt PID 8240, cũng không thấy trạng thái
  `otp-submitted` giữa chờ nhập OTP và màn mật khẩu. Chưa có bằng chứng nhánh
  JavaScript xác nhận OTP đã được gọi ở lượt lỗi này.
- Đây là mốc thời gian trong log thiết bị; không có dữ liệu mạng của lượt
  tự động lỗi hoặc lượt hoàn toàn thủ công thành công để so sánh.

**Giới hạn của hai phép thử:** chế độ bấm tay trước đây chỉ chặn ba gesture
Send code/Sign up/Skip, không chặn toàn bộ JavaScript click trong luồng.
Chế độ nhập tay hiện tại vẫn gọi JavaScript click cho xác nhận OTP, các bước
điều hướng và Next; bước chuẩn bị Send code vẫn gọi `focus()` lên nút, có thể
làm ô email mất focus. Vì vậy chưa thể loại trừ riêng bước nhập hoặc bước bấm,
và chưa có bằng chứng xác định TikTok nhận diện tự động.

## Vấn đề cần xử lý

Theo các lần thử của người dùng, đăng ký tự động đi qua OTP, nhập mật khẩu và bấm Sign up thì bị lỗi:

> Maximum number of attempts reached. Try again later.

Người dùng cho biết chuyển sang đăng ký thủ công thì thành công bình thường. Cần tìm khác biệt trong luồng tự động, không kết luận đơn giản rằng IP bị giới hạn hoặc mật khẩu sai.

Thiết bị đang kiểm tra là **Android giả lập**, ADB serial `emulator-5554`. Giao diện có hình thức giống iPhone, nhưng đó không phải bằng chứng về nền tảng. Nhận định ban đầu trong cuộc trao đổi về đường bấm JavaScript trên iPhone đã được đính chính.

## Bằng chứng đã thu được

- Màn mật khẩu hiển thị dấu xanh cho cả hai điều kiện: 8–20 ký tự; có chữ, số và ký tự đặc biệt.
- Mật khẩu random đã được bổ sung một ký tự từ `!@#$%^&*`, vẫn dài 9–13 ký tự, gồm chữ hoa, chữ thường và hai chữ số.
- Log lượt tự động lúc 17:58 ghi nhận:
  - 17:58:44: nhập OTP qua native input.
  - 17:58:46: chuyển đến màn mật khẩu, nhập mật khẩu và chờ gửi.
  - 17:58:56: gửi một yêu cầu chạm Sign up qua Accessibility; gesture hoàn tất.
  - 17:58:57: nhận thông báo giới hạn số lần thử; app dừng tự động.
- Log lượt trước lúc 17:44 cũng có chuỗi Sign up → gesture hoàn tất → lỗi giới hạn tương tự.
- Trong các đoạn log đã xem, mỗi lượt lỗi nêu trên có một yêu cầu gesture Sign up. Chưa thấy bằng chứng bấm lặp ở các lượt này; số request mạng thực tế chưa được đo.

## Các lần bấm thử trực tiếp bằng ADB

1. Bấm Sign up một lần trên màn mật khẩu đang mở: TikTok báo **“Verification code is expired or incorrect. Try again.”** App nhận mã lỗi **1704**. Việc chờ kiểm tra có thể làm OTP hết hạn, nhưng thông báo không phân biệt hết hạn hay nhập sai.
2. Sau khi người dùng nhập lại OTP, bấm Sign up một lần bằng ADB: chuyển được sang **Create username**. Đây là bằng chứng đã qua bước mật khẩu, chưa phải xác nhận hoàn tất đăng ký/đăng nhập.
3. Người dùng chạy lại luồng tự động: khi kiểm tra màn hình, lỗi giới hạn đã xuất hiện. Log xác nhận app đã tự bấm Sign up trước lúc kiểm tra.
4. Theo yêu cầu người dùng, bấm thêm đúng một lần bằng ADB trên màn đang báo giới hạn: màn hình vẫn hiển thị lỗi giới hạn; phần log được lọc không có mã lỗi mới. Chưa có dữ liệu mạng để xác nhận phản hồi mới hay thông báo cũ được giữ nguyên.
5. Người dùng thử đăng ký thủ công và báo thành công; khẳng định luồng tự động thường bị lỗi còn thủ công thì được.

**ADB `input tap` không tương đương hoàn toàn với chạm tay**, và cũng khác đường Accessibility mà app sử dụng. Không dùng kết quả ADB để khẳng định riêng cơ chế nào bị TikTok chặn.

Chưa làm rõ đầy đủ việc lần thủ công thành công có giữ nguyên email, OTP, phiên và màn mật khẩu của lượt tự động lỗi hay đã bắt đầu lại. Đây là biến cần kiểm soát ở lần thử tiếp theo.

## Đường xử lý hiện tại cần đọc

- `lib/controller/tiktok_controller.dart`
  - `_usesKeyboardInput`: bật trên Android.
  - `_usesAccessibility`: mặc định bật trên Android.
  - `inputAccountText`: email/mật khẩu dùng native `typeText` trên Android; OTP dùng đường paste. Có retry khi native action bị từ chối.
  - `clickSignupPasswordSubmit` → `tapAccountButton`: gửi gesture qua Accessibility; có latch theo action và attempt để tránh gửi lại.
  - Vòng lặp signup truyền `allowPasswordSubmit`; mặc định chờ 10 giây ở bước mật khẩu trước khi gửi.
  - `showAccountFailure`: dừng thao tác tài khoản khi nhận lỗi.
- `lib/core/scripts/auto_signup_script.dart`
  - `paste`: focus/select ô nhập, gọi native bridge, kiểm tra giá trị; sau khi native input được xác nhận và giá trị khớp thì bỏ focus bằng `blur()`.
  - Bước mật khẩu chờ màn ổn định và nút khả dụng, đặt `passwordSubmitted` trước khi gửi thao tác.
  - Android dùng `FlutterSignupPasswordSubmit`; nhánh JavaScript `button.click()` không phải đường mặc định trên Android.
  - Có phát hiện lỗi giới hạn inline trước thao tác tiếp theo.
- `lib/core/send_code_accessibility.dart`: thực hiện gesture qua Accessibility, cần đối chiếu với log và trạng thái nút thực tế.
- `lib/core/tiktok_account_failure.dart`: nhận diện lỗi tài khoản và thông báo giới hạn.
- `lib/core/account_password.dart`: bộ tạo mật khẩu.

## Kết luận hiện tại và giới hạn

**Có sự khác biệt quan sát được giữa đăng ký tự động và thủ công. Chưa xác định nguyên nhân gốc.**

Khả năng TikTok nhận diện tự động là giả thuyết của người dùng, chưa được chứng minh bởi phản hồi mạng hoặc log hiện có. Thông báo giới hạn không cho biết yếu tố nào gây lỗi. Chưa thể quy nguyên nhân riêng cho IP, email, thiết bị, Accessibility, tốc độ thao tác hay OTP.

Mật khẩu đạt điều kiện trên UI; không có bằng chứng lỗi định dạng mật khẩu. Một lần lỗi OTP và một lần qua bước mật khẩu sau khi nhập lại OTP là dữ kiện riêng, không giải thích toàn bộ lỗi giới hạn của luồng tự động.

## Hướng kiểm tra tiếp

1. Đã thử **nhập field thủ công + bấm nút tự động trên Android**, vẫn lỗi giới hạn sau Sign up. Phép thử cần tiếp theo là giữ nhập tay và các bước trước giống lượt này, nhưng dừng trước Sign up để bấm tay ngay trên cùng phiên; chế độ dừng riêng nút cuối chưa được thêm.
2. Ghi nhận cùng email, phiên và lần cấp OTP; tránh chờ lâu làm OTP hết hạn. Không ghi giá trị bí mật vào log.
3. Nếu nhập tay + tự bấm thành công ổn định, tập trung điều tra native input, paste OTP, focus và `blur()` của luồng tự điền. Kết quả riêng lẻ chưa đủ xác nhận nguyên nhân.
4. Nếu vẫn lỗi, đối chiếu cả phiên/OTP, trạng thái validation/loading và thao tác nút: mục tiêu, tọa độ, số lần dispatch và số request thực tế.
5. Bổ sung log chẩn đoán chỉ chứa mốc thời gian, attempt, bước, kết quả bridge, trạng thái validation và mã lỗi. Nếu cần quan sát mạng, chỉ lưu endpoint, mã trạng thái và mã lỗi đã lọc; không lưu mật khẩu, OTP, cookie, token hay thông tin hộp thư.
6. Đánh giá từng thay đổi riêng dựa trên bằng chứng. Không coi việc ngẫu nhiên hóa thao tác hoặc đổi IP là cách sửa đã được xác nhận.

## Kiểm thử và thay đổi đã thực hiện

- Đã sửa `lib/core/account_password.dart` và cập nhật kỳ vọng trong `test/account_password_test.dart` để mật khẩu random có ký tự đặc biệt.
- `flutter test test/account_password_test.dart`: 3 kiểm thử đạt.
- `node --test test/auto_signup_script_test.js`: 90 kiểm thử đạt, gồm kiểm tra field nhập tay, OTP sáu ô, ngày sinh và gọi bridge tự bấm ba nút.
- Các kiểm thử trên xác nhận logic ở mức kiểm thử, **không chứng minh TikTok thực tế chấp nhận đăng ký tự động**.
- Đã bật lại gesture đăng ký Android cho Send code, Sign up và Skip; tạm vô hiệu hóa tự nhập dữ liệu và OTP API đăng ký. Đây là thay đổi chẩn đoán, chưa xác nhận sửa được nguyên nhân gốc.
- Chưa thu thập phản hồi mạng cho lần điều tra tiếp theo.
