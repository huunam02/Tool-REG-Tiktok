## Quản lý state

App dùng GetX 4.7.3 (`GetMaterialApp`, `GetxController`, `GetBuilder`).
Logic khởi động, màn chính, quản lý/tạo/sửa proxy và WebView TikTok nằm trong
`lib/controller/`; giao diện nằm trong `lib/screen/`. Dữ liệu, SQLite, cấu hình
native và các script WebView nằm trong `lib/core/`. Mỗi màn có controller riêng,
được khởi tạo và đóng bởi `ControllerScope`. `onClose` giải phóng các ô nhập,
`TabController`, observer và hủy tác vụ OTP/WebView đang chờ. View không dùng
`setState` và chỉ gọi action hoặc đọc state từ controller.

## Proxy

Trong **Thiết lập chung**, phần **Proxy** chỉ hiển thị proxy đang sử dụng và
nút **Quản lý proxy**. Thêm, sửa, xóa và chọn proxy trong màn quản lý; bấm một
dòng rồi nhấn **Sử dụng proxy này** để dùng cho lần mở TikTok tiếp theo. **Không dùng
proxy** chuyển sang kết nối trực tiếp nhưng giữ danh sách và phiên trình duyệt.
App giữ nguyên cookie, dữ liệu phiên, cache và User-Agent khi khởi động lại
hoặc chọn lại đúng cấu hình proxy đang dùng. Chỉ khi nhấn **Sử dụng proxy này** với
proxy hoặc User-Agent khác, app mới xóa cookie, dữ liệu phiên và cache WebView
trước khi lưu cấu hình mới. Nếu xóa phiên thất bại, proxy hiện tại không đổi
và có thể thử lại.

Form **Thêm proxy** tự tạo User-Agent mặc định. Nút **Lấy User-Agent Chrome desktop** trên Android hoặc **Tạo User-Agent mới** trên iOS
cập nhật chuỗi trong form thêm hoặc sửa. App lưu chuỗi đang hiển thị cùng
proxy bằng SQLite; chọn lại proxy hoặc mở lại app sẽ khôi phục cấu hình đó.
Trên Android, chuỗi được chuẩn hóa khi mở WebView theo Chrome bật desktop:
`Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/<major>.0.0.0 Safari/537.36`.
`major` lấy từ Chromium thực tế trên thiết bị, không random phiên bản 120–140
nữa. Client Hints dùng `Google Chrome`/`Chromium`, cùng phiên bản thực tế,
`platform="Linux"`, `mobile=false`, `formFactors=["Desktop"]`, model trống và kiến trúc x86/64 bit.
Điện thoại vẫn giữ khả năng cảm ứng. Metadata được cấu hình native trước
request đầu tiên, cho cả WebView TikTok và WebView kiểm tra IP. Nếu Android
System WebView không hỗ trợ `USER_AGENT_METADATA` và `USER_AGENT_METADATA_FORM_FACTORS`, app báo lỗi thay vì tải
trang với nhận diện không đồng nhất. Cần build và chạy lại ứng dụng khi thay
phần native; hot reload không cập nhật MethodChannel Android.
Android dùng AndroidX WebKit 1.16.0 và yêu cầu Android 7.0 (API 24) trở lên.
Đây vẫn là WebView; đồng bộ User-Agent/Client Hints không biến engine thành Chrome thật.
Trên iOS, User-Agent vẫn được random, dùng hết bộ trước khi lặp và giữ lịch sử
qua các lần mở app. WebView dùng đúng chuỗi đã chọn và đặt chế độ `DESKTOP`.
iOS không tự thay chuỗi đã chọn bằng Safari native của máy;
việc đó từng khiến các User-Agent khác nhau trở thành cùng một chuỗi thực tế.
Safari desktop từ thông tin native chỉ là phương án dự phòng khi chưa có
User-Agent cấu hình. Đổi chuỗi User-Agent không thay đổi engine WebKit trên iOS
và chưa khẳng định sẽ gỡ được giới hạn từ máy chủ TikTok.
Trong bản debug, lọc `[WebView identity]` để xem `navigator.userAgent` thực tế
và kết quả so sánh với cấu hình. Dòng `Proxy IP detected` và IP trên AppBar
cho biết IP đầu ra đã kiểm tra bằng WebView dùng cùng cấu hình proxy.
Kết nối trực tiếp cũng giữ User-Agent qua các lần mở app. Sửa tên hoặc cấu
hình một mục giữ User-Agent của mục đó nếu không đổi ô User-Agent.
Xóa một mục khỏi danh sách vẫn giữ cấu hình và User-Agent đang sử dụng.

Mỗi proxy có trạng thái **Chưa sử dụng** hoặc **Đã sử dụng**, lưu bằng SQLite.
Proxy mới mặc định chưa sử dụng; app đánh dấu đã sử dụng sau khi áp dụng thành
công. Nhãn **Đang dùng** cho biết kết nối hiện tại, riêng với trạng thái lịch
sử. Có thể tìm theo tên/địa chỉ/tài khoản và lọc theo trạng thái. Khi nâng cấp
dữ liệu cũ, app đánh dấu proxy đang dùng là đã sử dụng.

Màn chính hiển thị đầy đủ tên, địa chỉ, tài khoản, mật khẩu và
User-Agent; các giá trị có nút sao chép. Màn quản lý hiển thị chi tiết ngay khi
chọn một proxy. Tạo proxy và sửa proxy có hai màn riêng. Các nhóm trong form
gồm thông tin kết nối (tài khoản và mật khẩu không bắt buộc) và User-Agent ở cuối. Nút tạo/lưu
luôn ở cuối màn hình.

Các ô trong app hiển thị dữ liệu trực tiếp, gồm mật khẩu TikTok, mật khẩu hộp
thư OTP, mật khẩu proxy, token API và dữ liệu import; không có nút hiện/ẩn.

Proxy HTTP/HTTPS cần có cổng, ví dụ `http://127.0.0.1:8080`; nhập thông tin xác
thực ở các ô riêng trong màn quản lý. Dữ liệu nằm trong `proxies.db`, với hai
bảng `proxies` và `current_proxy`. App tự nâng cấp dữ liệu cũ, thêm User-Agent
và đưa proxy đang cache chưa có trong danh sách vào danh sách quản lý.

Màn tạo proxy có khối **Import data** riêng và nút **Import proxy**: dán một dòng
`host:port:username:password` để điền địa chỉ HTTP, tài khoản và mật khẩu.
Import tự điền **Tên proxy** theo dạng `Proxy <host>`, không có dấu gạch ngang
và không kèm port, ví dụ `Proxy 31.57.78.19`; có thể sửa tên trước khi lưu.
User-Agent được giữ khi import. User-Agent nằm cùng khối **Thông tin kết nối**
với tên, địa chỉ, tài khoản và mật khẩu proxy. Màn sửa proxy không có import.
Kiểm tra các ô rồi bấm tạo/lưu để lưu proxy.

Đăng ký, đăng nhập và xem TikTok đều áp dụng cùng proxy trước khi mở WebView.
Các thao tác tự động nhập email/mật khẩu/OTP, chọn Email, gửi biểu mẫu và Skip
chạy trong cùng WebView, giữ cùng User-Agent/Client Hints và cấu hình proxy.
API lấy OTP dùng HTTP client Dart riêng: cấu hình proxy và User-Agent của
WebView không áp dụng cho request API này.
Android cần WebView hỗ trợ `PROXY_OVERRIDE`; iOS cần iOS 17 trở lên.
IP được kiểm tra bằng WebView nền dùng cùng proxy và kho dữ liệu mặc định,
không gọi `fetch` từ trang TikTok để tránh bị CSP/CORS chặn. App thử hai dịch vụ
IP, mỗi dịch vụ tối đa 8 giây; nút **Thử lại** chỉ kiểm tra lại IP. Nếu chưa nhận
được IP, app báo chưa xác minh, không kết luận proxy hỏng. Việc kiểm tra chạy
độc lập và không trì hoãn đăng ký/đăng nhập.

## Chọn sở thích

Khi modal **What would you like to watch on TikTok?** xuất hiện, app tự chọn
ngẫu nhiên 3 sở thích khác nhau rồi bấm **Continue** khi đã đủ 3 và nút được bật.
Nếu đã chọn sẵn 1–2 mục, app giữ các mục đó và chọn thêm cho đủ 3. Bộ quan sát
hoạt động cả khi modal xuất hiện muộn trong lúc xem, đăng ký hoặc đăng nhập;
không bấm lại Continue trong cùng modal và tạm ngưng khi trang ở nền.

## Ngôn ngữ WebView

Tạm tắt ép tiếng Anh cho cả xem, đăng nhập và đăng ký. App không đặt locale
native, không gửi header `Accept-Language` riêng, không thêm `lang=en` vào URL
và không ghi đè `navigator.language` / `navigator.languages`. Ngôn ngữ do máy
và phiên TikTok hiện tại quyết định. iOS gỡ các override `en-US` / `en_US`
đã được bản trước lưu; cookie và thiết lập ngôn ngữ khác được giữ nguyên.
Script tiếng Anh trong `lib/core/webview_locale.dart` được giữ để bật lại sau,
hiện không được inject. Dừng app và build/chạy lại hoàn toàn để áp dụng thay
đổi native; hot reload không đủ.

## OTP API

Tab **Đăng ký** và **Đăng nhập** có khối **Import data** riêng với ô
**Dữ liệu import** và nút **Import data**. Mật khẩu email OTP nằm cùng khối
thông tin tài khoản với email và mật khẩu TikTok.
Dán một tài khoản theo dạng `email|pass_dangky|passemail_otp`, rồi bấm import
để điền email, mật khẩu TikTok và mật khẩu hộp thư OTP của tab đang mở.
Ở tab Đăng nhập, cột thứ hai là mật khẩu đăng nhập TikTok. Mỗi lần import một
dòng; dữ liệu thiếu cột, sai email hoặc thiếu mật khẩu sẽ báo lỗi và giữ nguyên
các thông tin đã nhập. Có thể chỉnh sửa các ô sau khi import.

Khi chạy đăng ký, app tự tạo ngày sinh ngẫu nhiên trong khoảng 1960–2004,
bao gồm ngày hợp lệ theo số ngày của từng tháng và năm nhuận.
Luồng **Tự động đăng ký** mở trang chủ TikTok → bấm Account → mở dialog Login
→ bấm Sign up → Use phone or email → Use Email, rồi tiếp tục điền ngày sinh,
email, mật khẩu và xử lý OTP như trước. Biểu mẫu trong dialog được hỗ trợ cả
khi URL vẫn ở trang chủ.
Sau khi gửi OTP và mật khẩu, nếu xuất hiện màn **Create username**, app chờ
2 giây khi nút **Skip** sẵn sàng rồi bấm một lần để bỏ qua bước tạo tên người
dùng, kể cả khi tên gợi ý không khả dụng. App tiếp tục chờ xác nhận đăng ký
thành công; nút **Dừng** vẫn hủy được thao tác trong thời gian chờ.

Luồng **Tự động đăng nhập** mở trang chủ TikTok → bấm Account → mở dialog Login
→ Use phone or email → Username or Email, rồi tiếp tục nhập tài khoản, mật khẩu
và xử lý OTP như trước, kể cả khi dialog giữ nguyên URL trang chủ.
Khi hiện **Verify it’s really you**, app tự bấm đúng ô **Email**, chờ TikTok
mở bước nhập mã rồi gọi API OTP. Luồng đăng nhập có tối đa 120 giây để mở
biểu mẫu; sau khi gửi mật khẩu, chọn Email hoặc gửi OTP, mỗi bước có thêm
45 giây chờ kết quả để tránh dừng ngay khi hộp xác minh xuất hiện trên mạng chậm.
Đăng ký và đăng nhập tự động nghỉ 2,5 giây giữa các thao tác thông thường.
Từ bước yêu cầu/nhập OTP, app kiểm tra mỗi 300 ms để nhập mã và bấm tiếp
ngay khi sẵn sàng; không chờ cố định 5 giây trước khi nhập OTP.
Các bước mở Account, chọn phương thức/email, gửi mã, xác nhận OTP, gửi mật khẩu,
đăng ký và Skip đều có chốt theo bước trong mỗi lần chạy. Trang tạo lại nút DOM
không khiến app bấm lại bước đã thực hiện; cùng một nút vẫn có thể được dùng
ở hai bước khác nhau như gửi mật khẩu rồi xác nhận OTP. Mỗi thao tác nút chỉ
gọi click, không phát thêm chuỗi pointer/mouse. Bước Send code đăng nhập cũng
chờ bộ đếm gửi lại hoặc màn OTP xác nhận gửi mã; hết 15 giây không có xác nhận
thì dừng, chưa gọi API lấy OTP và không tự gửi lại mã.

App luôn lấy OTP qua API cho **Đăng nhập** và **Đăng ký**. Mở biểu tượng
**Cài đặt** trên AppBar, chọn **Cấu hình OTP API** để sửa URL và token dùng chung
cho hai luồng. App lưu cấu hình bằng `SharedPreferences`; các giá trị
`otpApiUrl` và `otpApiToken` trong `lib/core/config.dart` là mặc định lần đầu.
Trong từng tab, nhập mật khẩu hộp thư của email tương ứng.
Mật khẩu hộp thư là trường riêng với mật khẩu TikTok. App tự lấy mã OTP từ API.

App dùng thư viện `http` để gọi `POST /api/code` sau khi TikTok yêu cầu OTP, với JSON
`{"email":"email|mật khẩu hộp thư","wait":180}` và headers
`X-Reader-Token`, `ngrok-skip-browser-warning: 1`. Khi API trả
`{"ok":true,"code":"012345"}`, app dán mã bằng clipboard native rồi xác nhận.
Trong thời gian chờ, app vẫn theo dõi CAPTCHA, lỗi biểu mẫu và nút Dừng.
Ở luồng đăng ký, app bỏ focus khỏi ô vừa dán và chỉ gọi click một lần cho
Send code, không phát thêm chuỗi pointer/mouse có thể kích hoạt handler khác.
App chờ phản hồi của Send code
(đếm ngược/gửi lại mã hoặc chuyển sang ô OTP) trước khi gọi API. Nếu TikTok
chưa phản hồi trong 15 giây, app báo lỗi và dừng; app không tự gửi mã lần nữa.
App cũng đọc lỗi tài khoản trong console TikTok. Nếu TikTok báo
`Maximum number of attempts reached` khi lấy region, app hiển thị giới hạn số
lần thử và dừng luồng tài khoản/OTP. Lỗi `account-api` hoặc `email bind failed`
được hiển thị riêng với mã lỗi; không suy đoán nguyên nhân chỉ từ mã 7.
Luồng tự động cũng nhận diện thông báo giới hạn hiển thị trực tiếp trong
biểu mẫu, kể cả màn mật khẩu sau OTP không có `role=alert`. Khi gặp lỗi này,
app dừng thao tác và hủy yêu cầu OTP đang chờ; nút **Quay về cấu hình** trở về
màn trước và giữ thông tin đã nhập. Đây là phản hồi từ TikTok; app không gỡ
giới hạn hay tự gửi lại đăng ký. Không có thời gian chờ cụ thể trong phản hồi.

Trong bản debug, mở **Debug Console** và lọc `[OTP API]` để xem request,
HTTP status, thời gian chờ và response data (bao gồm trường `code`). Token và
mật khẩu hộp thư được che trong log. Bản release không in các log này.

Sau khi kiểm tra URL và token trong màn Cài đặt, chạy hoặc build từ terminal:

```sh
flutter run
flutter build apk --debug
```

## Getting Started

Nên dùng Flutter 3.41.8 hoặc mới hơn cho dự án này.

Flutter 3.27.x has an iOS platform-view hot-restart bug that can throw
`PlatformException(recreating_view)` ([Flutter fix](https://github.com/flutter/flutter/pull/164456)).
After changing SDKs, stop the running app and reload the VS Code window before
launching again.

With Xcode 26, use an iOS 18.4 or newer simulator. The simulator deployment
target is set to 18.4 for Runner and the WebView pod so WebKit's Swift symbols
link to the system framework. Otherwise, iOS 18.5 can terminate the app at
launch with `Library not loaded: /usr/lib/swift/libswiftWebKit.dylib`.
Physical-device deployment targets are unchanged. After editing the Podfile,
stop the app and run a full build; hot reload does not rebuild native pods.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
