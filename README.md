## Quản lý state

App dùng GetX 4.7.3 (`GetMaterialApp`, `GetxController`, `GetBuilder`).
Logic khởi động, màn chính, quản lý/tạo/sửa proxy và WebView TikTok nằm trong
`lib/controller/`; giao diện nằm trong `lib/screen/`. Dữ liệu, SQLite, cấu hình
native và các script WebView nằm trong `lib/core/`. Mỗi màn có controller riêng,
được khởi tạo và đóng bởi `ControllerScope`. `onClose` giải phóng các ô nhập,
`TabController`, observer và hủy tác vụ OTP/WebView đang chờ. View không dùng
`setState` và chỉ gọi action hoặc đọc state từ controller.

## Quản lý cấu hình

Trên màn **Home**, phần **Cấu hình** hiển thị đầy đủ proxy, thông tin
xác thực proxy, User-Agent, email TikTok, mật khẩu TikTok, mật khẩu email OTP
và trạng thái đăng ký. Nút **Quản lý cấu hình** mở danh sách các bộ dữ liệu.
Mỗi bộ gộp proxy và tài khoản; không có ô tên riêng, danh sách nhận diện bằng
email và địa chỉ proxy. Chọn một dòng rồi nhấn **Sử dụng cấu hình này**.
Home hiển thị trực tiếp cấu hình và bình luận, không có thanh tab.
Trên Android, **Cài đặt → Quyền Trợ năng** có switch hiển thị quyền thực tế.
Chạm switch để mở Cài đặt Android và bật/tắt dịch vụ; khi quay lại app,
switch tự cập nhật theo quyền đã cấp.
Nút **Đăng ký tài khoản** ở cuối màn dành cho cấu hình chưa đăng ký;
cấu hình đã đăng ký hiển thị **Đăng nhập tài khoản**. Nút này chạy tác vụ
tương ứng, chỉ hiển thị khi đã chọn cấu hình và chỉ bật khi cấu hình có tài khoản.
Nút **Mở TikTok** phía dưới mở TikTok bằng bộ dữ liệu đang chọn.

Form tạo/sửa có switch **Đã đăng ký**. Bật lưu `statusAccount = registered`,
tắt lưu `statusAccount = unregistered` (mặc định). Đây là trạng thái do người
sử dụng đặt; độc lập với nhãn đã dùng proxy. Sửa trạng thái của cấu hình đang
chọn cũng cập nhật phần xem trước sau khi quay về Home.

App giữ cookie và phiên khi mở lại hoặc chọn lại cùng bộ dữ liệu. Khi áp dụng
cấu hình có proxy, User-Agent hoặc tài khoản khác, app xóa phiên WebView trước
khi chuyển. **Bỏ chọn cấu hình** chuyển sang kết nối trực tiếp và bỏ tài khoản
khỏi phần xem trước, giữ danh sách và phiên trình duyệt.

Form **Tạo cấu hình** tự tạo User-Agent mặc định. Nút **Đổi User-Agent**
cập nhật chuỗi trong form thêm hoặc sửa. App lưu chuỗi đang hiển thị cùng
proxy bằng SQLite; chọn lại proxy hoặc mở lại app sẽ khôi phục cấu hình đó.
Trên Android, nút đổi random UA Chrome desktop Linux hoặc Windows cùng phiên bản
Chrome 120–140. Bộ có 42 UA; dùng hết bộ trước khi lặp, không lặp ngay UA cuối.
Lịch sử được giữ qua các lần mở app. Không tạo mẫu macOS trên Android.
WebView giữ nguyên chuỗi đã lưu, kể cả UA nhập tay. Client Hints dùng
`Google Chrome`/`Chromium`, phiên bản và platform tương ứng với UA đã chọn,
`mobile=false`, `formFactors=["Desktop"]`, model trống và kiến trúc x86/64 bit.
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

Màn quản lý hiển thị chi tiết khi chọn một cấu hình. Form tạo/sửa gồm
thông tin kết nối, User-Agent và tài khoản TikTok. Nút tạo/lưu luôn ở cuối màn hình.

Các ô trong app hiển thị dữ liệu trực tiếp, gồm mật khẩu TikTok, mật khẩu hộp
thư OTP, mật khẩu proxy, token API và dữ liệu import; không có nút hiện/ẩn.

Proxy HTTP/HTTPS cần có cổng, ví dụ `http://127.0.0.1:8080`; nhập thông tin xác
thực ở các ô riêng trong màn quản lý. Dữ liệu nằm trong `proxies.db`,
chỉ có một bảng ứng dụng `configurations`, gồm cả tài khoản, `statusAccount`
và cờ chọn cấu hình hiện tại. Migration giữ proxy/User-Agent, tài khoản nếu
đã có và bộ dữ liệu đang chọn; chuyển dữ liệu rồi xóa hai bảng cũ.
Các proxy cũ chưa có tài khoản có thể bổ sung ở màn sửa cấu hình.

Nút **Import data** trên màn tạo mở bottom sheet có hai mục:
**Từ file** (Excel `.xlsx`, `.xls` hoặc `.txt`) và **Dán từ clipboard**.
TXT và clipboard nhận nhiều cấu hình,
mỗi cấu hình một dòng theo định dạng:
`host:port:username:password email|mật_khẩu_TikTok|mật_khẩu_email_OTP[|0/1]`.
Thêm `|1` ở cuối để đặt **Đã đăng ký**; `|0` hoặc không thêm trạng thái đặt
**Chưa đăng ký**, kể cả khi công tắc đang bật. Giá trị khác báo lỗi import.
Proxy và tài khoản cách nhau một dấu cách. Dòng trống được bỏ qua. Nếu có dòng
lỗi, app báo số dòng và giữ nguyên dữ liệu trước đó để sửa rồi import lại.
Mỗi dòng hiển thị một mục **Thông tin cấu hình** riêng, có proxy, tài khoản,
trạng thái và User-Agent độc lập, chỉnh sửa riêng trước khi lưu.
Cấu hình đầu giữ User-Agent đang hiển thị; các cấu hình tiếp theo tự tạo
User-Agent riêng và có nút đổi riêng. Nhấn **Tạo N cấu hình** để lưu
cả danh sách trong một giao dịch; lỗi lưu không để lại cấu hình lưu dở.

Excel nhận dữ liệu trên tất cả sheet, mỗi cấu hình một dòng: toàn bộ chuỗi
trong một ô; hai cột proxy và chuỗi tài khoản; hoặc các cột proxy, email,
mật khẩu TikTok, mật khẩu email và trạng thái (cột trạng thái không bắt buộc).
Có thể đặt tiêu đề `Proxy` hoặc `Data` ở dòng đầu. Dòng trống được bỏ qua;
lỗi Excel hiển thị tên sheet và số dòng. Ô nhập thủ công vẫn dùng được,
nhấn dấu ✓ trong ô để import dữ liệu đã nhập.

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

Luồng đăng ký và đăng nhập dùng tài khoản và mật khẩu hộp thư của
cấu hình đang chọn. Tạo hoặc sửa dữ liệu qua **Quản lý cấu hình** trên
màn **Home**, rồi chọn cấu hình để sử dụng.

Khi chạy đăng ký, app tự tạo ngày sinh ngẫu nhiên trong khoảng 1960–2004,
bao gồm ngày hợp lệ theo số ngày của từng tháng và năm nhuận.
Luồng **Tự động đăng ký** mở trang chủ TikTok → bấm Account → mở dialog Login
→ bấm Sign up → Use phone or email → Use Email, rồi tiếp tục điền ngày sinh,
email, mật khẩu và xử lý OTP như trước. Biểu mẫu trong dialog được hỗ trợ cả
khi URL vẫn ở trang chủ.
Sau khi gửi OTP và mật khẩu, nếu xuất hiện màn **Create username**, app chờ
2 giây khi nút **Skip** sẵn sàng rồi bấm một lần để bỏ qua bước tạo tên người
dùng, kể cả khi tên gợi ý không khả dụng. Trên Android, nút Skip dùng
`dispatchGesture()` tại tọa độ hiện tại trong WebView. App tiếp tục chờ xác nhận đăng ký
thành công; nút **Dừng** vẫn hủy được thao tác trong thời gian chờ.

Luồng **Tự động đăng nhập** mở trang chủ TikTok → bấm Account → mở dialog Login
→ Use phone or email → Username or Email, rồi tiếp tục nhập tài khoản, mật khẩu
và xử lý OTP như trước, kể cả khi dialog giữ nguyên URL trang chủ.
Khi hiện **Verify it’s really you**, app chờ 5 giây trước khi chọn ô **Email**.
Trên Android, app lấy lại tọa độ từ WebView và dùng `dispatchGesture()` chạm
80 ms, có kiểm tra ô đang hiển thị và không bị che. Sau đó app chờ TikTok
mở bước nhập mã rồi gọi API OTP. Luồng đăng nhập có tối đa 120 giây để mở
biểu mẫu; sau khi gửi mật khẩu, chọn Email hoặc gửi OTP, mỗi bước có thêm
45 giây chờ kết quả để tránh dừng ngay khi hộp xác minh xuất hiện trên mạng chậm.
Đăng ký và đăng nhập tự động nghỉ 2,5 giây giữa các thao tác thông thường.
Từ bước yêu cầu/nhập OTP, app kiểm tra mỗi 300 ms để nhập mã và bấm tiếp
ngay khi sẵn sàng; không chờ cố định 5 giây trước khi nhập OTP.
Các bước mở Account, chọn phương thức/email, gửi mã, xác nhận OTP, gửi mật khẩu,
đăng ký và Skip đều có chốt theo bước trong mỗi lần chạy. Trang tạo lại nút DOM
không khiến app bấm lại bước đã thực hiện; cùng một nút vẫn có thể được dùng
ở hai bước khác nhau như gửi mật khẩu rồi xác nhận OTP. Trên Android, Send code
của cả đăng ký và đăng nhập, ô Email xác minh đăng nhập, Sign up sau OTP, Skip tạo username và Continue
trong biểu mẫu đăng nhập dùng
`flutter_accessibility_service 1.2.0` để
`dispatchGesture()` một cú chạm 80 ms tại tọa độ nút trong WebView, sau khi
kiểm tra nút đang hiển thị, được bật và không bị che. Không cần node Accessibility
để bấm tọa độ; các sự kiện System UI không làm mất mục tiêu. Mỗi bước chỉ yêu cầu một gesture
trong mỗi lượt chạy; cần bật quyền Trợ năng cho Tool TikTok. Các nút còn lại gọi click một lần.
Continue/Tiếp tục có chốt riêng cho bước gửi mật khẩu và bước xác nhận OTP,
kể cả khi trang dùng lại cùng một nút. App lấy lại tọa độ khi chạm và dừng nếu
gesture không hoàn tất.
Bước Send code đăng nhập cũng
chờ bộ đếm gửi lại hoặc màn OTP xác nhận gửi mã; hết 15 giây không có xác nhận
thì dừng, chưa gọi API lấy OTP và không tự gửi lại mã.

App luôn lấy OTP qua API cho **Đăng nhập** và **Đăng ký**. Mở biểu tượng
**Cài đặt** trên AppBar, chọn **Cấu hình OTP API** để sửa URL và token dùng chung
cho hai luồng. App lưu cấu hình bằng `SharedPreferences`; các giá trị
`otpApiUrl` và `otpApiToken` trong `lib/core/config.dart` là mặc định lần đầu.
Nhập mật khẩu hộp thư của email trong màn tạo hoặc sửa cấu hình.
Mật khẩu hộp thư là trường riêng với mật khẩu TikTok. App tự lấy mã OTP từ API.

App dùng thư viện `http` để gọi `POST /api/code` sau khi TikTok yêu cầu OTP, với JSON
`{"email":"email|mật khẩu hộp thư","wait":180}` và headers
`X-Reader-Token`, `ngrok-skip-browser-warning: 1`. Khi API trả
`{"ok":true,"code":"012345"}`, app dán mã bằng clipboard native rồi xác nhận.
Trong thời gian chờ, app vẫn theo dõi CAPTCHA, lỗi biểu mẫu và nút Dừng.
Ở luồng đăng ký, app chờ 5 giây sau khi nhập xong thông tin và nút Send code
được bật. Nếu nút bị thay thế hoặc tắt, thời gian chờ bắt đầu lại.
Ở luồng đăng ký Android, app bỏ focus khỏi ô vừa dán và chạm Send code qua
Accessibility; không gọi thêm JavaScript click cho nút này.
Sau OTP, ở modal nhập mật khẩu, app chờ 10 giây kể từ khi mật khẩu đã nhập đúng
và nút **Sign up** được bật. Trên Android, nút này cũng được chạm bằng
`dispatchGesture()` tại tọa độ WebView, với chốt riêng để không gửi đăng ký hai lần.
Nếu nút bị tắt hoặc thay thế trong lúc chờ, thời gian chờ bắt đầu lại.
App chờ phản hồi của Send code
(đếm ngược/gửi lại mã hoặc chuyển sang ô OTP) trước khi gọi API. Nếu TikTok
chưa phản hồi trong 15 giây, app báo lỗi và dừng; app không tự gửi mã lần nữa.
App cũng đọc lỗi tài khoản trong console TikTok. Nếu TikTok báo
`Maximum number of attempts reached` khi lấy region, app hiển thị giới hạn số
lần thử và dừng luồng tài khoản/OTP. Lỗi `account-api` hoặc `email bind failed`
được hiển thị riêng với mã lỗi; không suy đoán nguyên nhân chỉ từ mã 7.
Luồng tự động cũng nhận diện thông báo giới hạn hiển thị trực tiếp trong
biểu mẫu, kể cả màn mật khẩu sau OTP không có `role=alert`. Khi gặp lỗi này,
app dừng thao tác và hủy yêu cầu OTP đang chờ. Lỗi tài khoản và cảnh báo proxy
hiện bằng toast phía dưới, không thêm banner làm co WebView. Toast lỗi tài khoản
có nút **Cấu hình** trở về màn trước và giữ thông tin đã nhập. Trạng thái auto
và nút Dừng cũng nằm đè phía dưới để giữ nguyên kích thước WebView.
Đây là phản hồi từ TikTok; app không gỡ
giới hạn hay tự gửi lại đăng ký. Không có thời gian chờ cụ thể trong phản hồi.

Trong bản debug, mở **Debug Console** và lọc `[OTP API]` để xem request,
HTTP status, thời gian chờ và response data (bao gồm trường `code`). Token và
mật khẩu hộp thư được che trong log. Bản release không in các log này.

Sau khi kiểm tra URL và token trong màn Cài đặt, chạy hoặc build từ terminal:

```sh
./tool/flutterw run
./tool/flutterw build apk --debug
```

## Getting Started

Dự án dùng Flutter 3.41.8 (Dart 3.11.5), hỗ trợ `collection 1.19.1`
và `flutter_accessibility_service 1.2.0` mà không cần `dependency_overrides`.
SDK riêng trên máy hiện tại: `/Users/dion/Documents/development/new/flutter`.
SDK cũ tại `/Users/dion/Documents/development/old/flutter` được giữ nguyên.

Chạy các lệnh Flutter cho dự án bằng `./tool/flutterw` để chọn SDK riêng;
PATH mặc định của máy không thay đổi. Trên máy khác, đặt `FLUTTER_SDK_PATH`
trỏ đến SDK Flutter 3.41.8 hoặc mới hơn. VS Code dùng `dart.flutterSdkPath`
trong `.vscode/settings.json` (cấu hình riêng của workspace).

```sh
./tool/flutterw --version
./tool/flutterw pub get
./tool/flutterw analyze
./tool/flutterw test
```

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
