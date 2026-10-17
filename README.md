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
Home gồm hai tab **Cấu hình** và **Nuôi acc**. Tab Cấu hình giữ thông tin
cấu hình đã chọn. Tab Nuôi acc hiển thị các tài khoản, tổng số
phút xem, video đã xem và bình luận xác nhận thành công. Các cấu hình cùng
email được gộp vào một dòng thống kê, không phân biệt chữ hoa/thường.

Từ khóa và bình luận chỉ lấy từ Firebase Remote Config; Home không còn hai ô
nhập danh sách và không đọc dữ liệu danh sách cũ trong `app_settings`.

Tài liệu gửi khách: [Hướng dẫn cấu hình Firebase Remote Config](docs/huong-dan-cau-hinh-firebase.md).

Chọn kiểu **String** cho cả 5 tham số. Hai danh sách là chuỗi chứa JSON array,
đúng chữ hoa/thường:

| Tham số | Ví dụ giá trị |
| --- | --- |
| `search_keywords` | `["Travel", "Cà phê", "Technology"]` |
| `auto_comments` | `["Great video!", "Cảm ơn bạn ❤️"]` |

Tất cả tên tham số Remote Config dùng `snake_case`: `otp_api_url`, `otp_api_token`,
`sadcaptcha_license_key`, `search_keywords`, `auto_comments`. Hai tên cũ
`listSearchKeywords` và `AutoComments` đã đổi thành `search_keywords` và
`auto_comments`. Dữ liệu mặc định đầy đủ để sao chép từng tham số nằm trong
[remote_config_values.json](docs/remote_config_values.json); đây là dữ liệu
key/value để nhập từng tham số, không phải template import toàn bộ Firebase.
Tất cả giá trị trong file đều là chuỗi; dấu `\"` là cách JSON biểu diễn dấu nháy
trong chuỗi. Khi nhập vào ô giá trị String trên Firebase, dán nội dung như
`["Travel","Coffee"]`, không thêm dấu nháy ngoài và không thêm ký tự `\`.
App đọc String từ Remote Config rồi dùng `jsonDecode()` để lấy danh sách.

Publish cấu hình rồi mở lại app để fetch và activate. App bỏ khoảng trắng hai
đầu và các phần tử chuỗi rỗng. `[]` là danh sách rỗng: từ khóa rỗng chỉ nuôi news
feed, bình luận rỗng không tự bình luận. Nếu thiếu tham số hoặc JSON không phải
mảng chuỗi hợp lệ, app dùng các danh sách dự phòng trong `lib/core/config.dart`
(100 bình luận, 20 từ khóa tiếng Anh), đã đăng ký với Remote Config bằng `setDefaults()`.
Tab Nuôi acc hiển thị ba thống kê: phút xem video, số video đã xem và số bình luận.
Thẻ tài khoản không hiển thị dòng news feed/search keyword hoặc nút mở xem thủ công.
Kéo xuống để làm mới danh sách; không có nút làm mới riêng.

Thống kê chỉ ghi nhận video hiển thị và thời gian media thực sự tiến;
pause, tua, buffering và chạy nền không được tính. Một lượt video được ghi
khi kết thúc, chuyển video hoặc đóng phiên sau ít nhất một giây phát.
Bình luận được đếm sau phản hồi thành công có ID, chống đếm lặp trong trang.
Snapshot được lưu khoảng hai giây/lần và chốt khi đóng màn hình. Khi tiến
trình bị dừng đột ngột, phần thời gian sau snapshot cuối có thể chưa được lưu.
Các phiên của luồng tự động cũ không được đưa vào bộ thống kê mới này.
Trên Android, **Cài đặt → Quyền Trợ năng** có switch hiển thị quyền thực tế.
Chạm switch để mở Cài đặt Android và bật/tắt dịch vụ; khi quay lại app,
switch tự cập nhật theo quyền đã cấp.
Nút **Đăng ký tài khoản** ở cuối màn dành cho cấu hình chưa đăng ký;
cấu hình đã đăng ký hiển thị **Đăng nhập tài khoản**. Nút này chạy tác vụ
tương ứng, chỉ hiển thị khi đã chọn cấu hình và chỉ bật khi cấu hình có tài khoản.
Nút **Mở TikTok** phía dưới mở TikTok bằng bộ dữ liệu đang chọn.

Form tạo/sửa có switch **Đã đăng ký**. Bật lưu `statusAccount = registered`,
tắt lưu `statusAccount = unregistered` (mặc định). Khi đăng ký và bấm **Skip**
thành công, app tự lưu **Đã đăng ký** cho đúng cấu hình đang chạy; Home cập nhật
khi quay lại và chuyển nút sang **Đăng nhập tài khoản**. Trạng thái này độc lập
với nhãn đã dùng proxy. Sửa trạng thái của cấu hình đang
chọn cũng cập nhật phần xem trước sau khi quay về Home.
Form mới tự tạo mật khẩu TikTok dài 9–13 ký tự, chữ đầu viết hoa, các chữ
tiếp theo viết thường và hai chữ số cuối. Nút đổi mật khẩu tạo giá trị khác.
Mật khẩu có sẵn khi sửa hoặc import được giữ nguyên; mật khẩu TikTok trống
trong import được tạo mới. Mật khẩu hộp thư OTP vẫn phải được cung cấp.

App giữ cookie và phiên khi mở lại hoặc chọn lại cùng bộ dữ liệu. Khi áp dụng
cấu hình có proxy, User-Agent hoặc tài khoản khác, app xóa phiên WebView trước
khi chuyển. **Bỏ chọn cấu hình** chuyển sang kết nối trực tiếp và bỏ tài khoản
khỏi phần xem trước, giữ danh sách và phiên trình duyệt.
Phần xóa dữ liệu Android hiện dùng API WebStorage cũ; chưa xác minh xóa sạch
service worker/Cache Storage hoặc thời điểm hoàn tất ở backend. Kết quả kiểm tra
mã nguồn và phạm vi kiểm thử ghi ở [docs/session-audit.md](docs/session-audit.md).

Trên Android, **Mở TikTok**, **Đăng nhập**, **Đăng ký**, **Kiểm tra IP / User-Agent**,
**Kiểm tra IP với WhatIsMyIP**, kiểm tra IP nền và **Tra theo proxy** mặc định
đều dùng Chrome desktop theo phiên bản Chromium của Android System WebView
đang cài. User-Agent và Client Hints được cấu hình native trước request đầu tiên;
ví dụ engine 134 sẽ khai báo `Chrome/134.0.0.0`, không dùng phiên bản 151–155
chỉ vì cấu hình đã lưu có chuỗi đó. Bản tự động vẫn giữ các bước nhập tài khoản,
gửi mã, lấy OTP và tiếp tục biểu mẫu; chốt khởi động ngăn chạy lại khi reload/resume.
CPU/RAM/GPU lấy từ thiết bị, không chèn profile Pixel ở chế độ mặc định này.
Proxy được áp dụng trước khi tạo WebView; múi giờ đã lưu vẫn dùng cho các luồng
thông thường. Ngôn ngữ tiếng Anh hiện không bị ép.

Viewport desktop rộng 980 CSS px, thu vừa bề ngang WebView và cho phép zoom
ở luồng thông thường. Luồng đăng ký Android dùng vùng WebView tỷ lệ 1:2,
design size 400×800 qua `flutter_screenutil`, khóa zoom để phát lại tọa độ.
Kích thước màn hình, DPR và khả năng cảm ứng giữ theo thiết bị. Client Hints dùng
`Google Chrome`/`Chromium`, Linux/x86/64 bit, `mobile=false`,
`formFactors=["Desktop"]`, model trống; `navigator.platform=Linux x86_64`.
Đây vẫn là Android WebView, không mở Chrome ngoài app hoặc đổi hệ điều hành.
Nếu WebView không hỗ trợ `USER_AGENT_METADATA`, `USER_AGENT_METADATA_FORM_FACTORS`
hoặc `DOCUMENT_START_SCRIPT`, app báo lỗi và dừng trước khi tải trang ngoài.
Android dùng AndroidX WebKit 1.16.0 và yêu cầu Android 7.0 (API 24) trở lên.
Cần build/chạy lại khi sửa phần native; hot reload không cập nhật MethodChannel.

Form **Tạo cấu hình** và màn sửa vẫn lưu mẫu User-Agent cùng proxy bằng SQLite.
Các nút đổi mẫu, **Dùng Miui Browser 14 (Desktop)** và **Dùng Chrome Windows (Desktop)**
được giữ. Android random giữa 5 mẫu Chrome desktop 151–155 và Miui Browser
14.65.0-gn; Chrome Windows x64 là lựa chọn riêng. Chọn lại cấu hình hoặc mở lại
app vẫn giữ mẫu đã lưu. Các mẫu chỉ được dùng khi chọn **Dùng User-Agent đã chọn
(thủ công)** trong màn TikTok. Chế độ này đồng bộ UA/Client Hints/platform theo
mẫu, dùng profile CPU/RAM/GPU Pixel trước đây và tắt thao tác tài khoản tự động.
Mẫu Miui dùng Linux desktop/Chromium 135; mẫu Windows dùng Windows 10.0.0,
`navigator.platform=Win32`. Chúng chỉ mô phỏng nhận diện của trang/frame.
Nút **Desktop theo WebView (thủ công)** chuyển lại cấu hình engine, vẫn thao tác
thủ công. Quay về Home rồi mở lại để dùng cấu hình engine với luồng tự động.

Trong **Cài đặt**, **Kiểm tra IP / User-Agent** mở
[WhatIsMyBrowser](https://www.whatismybrowser.com/) và **Kiểm tra IP với WhatIsMyIP**
mở [WhatIsMyIP](https://www.whatismyip.com/) bằng cùng cấu hình proxy và engine.
Đối chiếu IP Address với IP đầu ra của proxy, không so với hostname proxy.
Trang kiểm tra dừng các thao tác TikTok; biểu tượng ngôi nhà quay lại TikTok.

App ẩn Local IP bằng cách vô hiệu hóa `RTCPeerConnection`, các alias và
`RTCIceGatherer`/`RTCIceTransport` trước script của trang, cho trang chính và iframe.
Không tạo SDP, ICE candidate hay phát Local IP mô phỏng từ cấu hình cũ.
Áp dụng cả TikTok, trang kiểm tra và các WebView nền, với proxy hoặc kết nối trực tiếp.
IP công khai vẫn do kết nối/proxy quyết định. WebRTC không hoạt động trong trang;
không đổi địa chỉ LAN của hệ điều hành. Android bỏ bypass ngầm cho localhost/link-local;
iOS đặt `allowFailover=false` để không chuyển sang kết nối trực tiếp khi proxy lỗi.

Trên iOS, User-Agent vẫn dùng mẫu đã chọn và chế độ `DESKTOP`; thay UA không đổi
engine WebKit. Script GPU Pixel của iOS và chế độ mẫu Android được giữ như trước.
Trong bản debug, lọc `[WebView identity]` để xem UA thực tế và kết quả so sánh
với nhận diện đang dùng. Dòng `Proxy IP detected` và IP trên AppBar là IP đầu ra
đã kiểm tra qua cùng proxy.
Android bật WebView remote debugging ở bản debug và tắt ở bản profile/release.
Khi Chrome đăng ký được nhưng app báo `Maximum number of attempts reached`,
không thể kết luận nguyên nhân chỉ từ console `get region err`.
Chạy `./tool/flutterw run`, mở TikTok trong app rồi mở
`chrome://inspect/#devices` trên Chrome máy tính, chọn **inspect** của WebView.
Trong **Network**, bật **Preserve log**, xem request tài khoản khi lỗi xuất hiện
và đối chiếu với Chrome trên cùng thiết bị: endpoint (không gồm query),
HTTP status, `error_code`/`status_code` và thông báo lỗi trong **Response**.
HTTP 200 vẫn có thể chứa mã lỗi nghiệp vụ. Khi chia sẻ kết quả, chỉ gửi các
trường trên; không gửi cookie, token, email, mật khẩu, OTP hay HAR chưa lọc.
Cấu hình engine mặc định đã vượt qua bước region và đến màn nhập OTP trong
lần kiểm tra thủ công trên emulator (Chrome/WebView 134). Luồng Accessibility
mới đã hoàn tất một lượt ghi mẫu tài khoản thật qua Sign up → Skip → Messages/Profile;
chưa xác minh phát lại toàn bộ không can thiệp. Phản hồi region HTTP 200 kèm
`error_code=7` không chỉ rõ lý do từ chối; cấu hình này không bảo đảm xóa giới hạn
phía TikTok. App không tự thử lại, xóa phiên hoặc đổi cấu hình khi gặp lỗi này.
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
thực ở các ô riêng trong màn quản lý. Dữ liệu nằm trong `proxies.db`, phiên bản
schema 10. Bảng `configurations` giữ tài khoản, `statusAccount` và cấu hình
hiện tại; `nurture_accounts`, `nurture_sessions` lưu lịch sử thống kê;
`app_settings` giữ dữ liệu chủ đề và bình luận cũ; Home không còn đọc/ghi hai danh sách này. Migration từ phiên bản 9 giữ
nguyên các dòng cấu hình và lựa chọn hiện tại, bổ sung các bảng mới.
Chi tiết cấu trúc và quy tắc lưu ở [docs/database.md](docs/database.md).
Các proxy cũ chưa có tài khoản có thể bổ sung ở màn sửa cấu hình.

Nút **Import data** trên màn tạo mở bottom sheet có hai mục:
**Từ file** (Excel `.xlsx`, `.xls` hoặc `.txt`) và **Dán từ clipboard**.
TXT và clipboard nhận nhiều cấu hình,
mỗi cấu hình một dòng theo định dạng:
`host:port:username:password|email|mật_khẩu_TikTok|mật_khẩu_email_OTP[|0/1]`.
Thêm `|1` ở cuối để đặt **Đã đăng ký**; `|0` hoặc không thêm trạng thái đặt
**Chưa đăng ký**, kể cả khi công tắc đang bật. Giá trị khác báo lỗi import.
Thứ tự bốn trường là **Proxy | Email | Password | Mail Password**, ngăn cách bằng
dấu `|`. Phần proxy vẫn dùng `host:port:username:password`. Dòng trống được bỏ qua. Nếu có dòng
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

Vào **Cài đặt → Xuất dữ liệu Excel → Xuất Excel data** để mở hộp thoại
chọn nơi lưu file `.xlsx`. File có một sheet **Data**, mỗi cấu hình một hàng:

- Năm cột đầu giữ định dạng import **Proxy | Email | Password | Mail Password |
  status(Đã dăng ký)** (`0/1`), tiếp theo là User-Agent, múi giờ và
  trạng thái đã sử dụng (`0/1`).
- Các cột tiếp theo là thống kê nuôi ghép theo email (không phân biệt hoa/thường):
  thời gian xem theo ms và phút, số video đã xem/xem hết/lướt sớm, bình luận,
  chế độ và từ khóa. Cấu hình chưa có thống kê
  xuất các số đếm bằng 0. Nếu nhiều cấu hình dùng cùng email, mỗi hàng hiển thị
  cùng thống kê tổng của tài khoản đó.
- Tài khoản chỉ còn lịch sử nuôi sau khi cấu hình bị xóa vẫn có một hàng riêng,
  với phần proxy, mật khẩu và trạng thái đăng ký để trống.

Khi import lại file xuất, app đọc năm cột đầu; các cột bổ sung chỉ dùng để tra
cứu, không khôi phục lịch sử nuôi. Hàng chỉ có thống kê nuôi được bỏ qua.
File xuất theo định dạng hai sheet trước đây vẫn nhập được.
Quy tắc kiểm tra import cũ vẫn áp dụng: cần proxy có xác thực và đủ tài khoản;
cấu hình dùng mạng mặc định hoặc chưa có tài khoản vẫn được xuất để tra cứu.
File xuất có chứa các mật khẩu đã lưu.

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

## Múi giờ theo proxy trong WebView Android

Khi import từ clipboard, TXT hoặc Excel trên Android, app tra
`https://ipwho.is/?fields=success,ip,timezone.id` lần lượt qua từng proxy rồi
điền **Múi giờ WebView** riêng cho từng cấu hình (ví dụ `America/New_York`).
Có trạng thái đang tra và lỗi riêng từng dòng; lỗi không làm mất dữ liệu import.
Nút **Tra theo proxy** cho phép tra lại, hoặc nhập/sửa mã IANA thủ công.
Đổi địa chỉ/tài khoản/mật khẩu proxy sẽ xóa múi giờ cũ và bỏ kết quả tra đang
chờ nếu nó thuộc kết nối trước. Lúc đang tra, nút lưu và import mới tạm khóa.

Khi lưu, `ProxyDraft`/`ProxyProfile`/`SavedProxy` giữ `timeZoneId`; SQLite
`configurations.time_zone_id` lưu chuỗi IANA. DB version 8 thêm cột mặc định
rỗng, giữ cấu hình, tài khoản và lựa chọn cũ. Múi giờ hiện ở form tạo/sửa,
chi tiết quản lý và phần cấu hình đang dùng trên Home. Mỗi lần tra tạm đổi
proxy WebView trong hàng đợi, hủy khi đóng form, rồi khôi phục override trước;
không đổi cấu hình được chọn hoặc xóa phiên/cookie.

Khi mở TikTok/đăng ký/đăng nhập/trang kiểm tra, WebView dùng múi giờ đã lưu,
không gọi API lại. Cấu hình cũ/chưa có múi giờ sẽ tra khi mở và lưu bổ sung
vào dòng đang chọn. Nếu proxy xoay IP hoặc đổi địa điểm, dùng **Tra theo proxy**
ở màn sửa rồi lưu/chọn lại cấu hình trước khi mở WebView. Không theo dõi IP
xoay khi trang đang mở. Địa điểm suy ra từ IP phụ thuộc cơ sở dữ liệu của API.

Script được chèn ở đầu document, cho cả trang và iframe, dùng dữ liệu IANA/ICU
trong WebView để tính offset và DST theo ngày. iOS và chế độ không proxy không
áp dụng bước mô phỏng múi giờ này.

Áp dụng cho `Intl.DateTimeFormat` mặc định và các hàm local của `Date`: getter,
setter, constructor/parse, `getTimezoneOffset`, `toString`, `toLocale*`.
Múi giờ được chỉ định rõ trong tùy chọn Intl vẫn được giữ. Timestamp thực,
`Date.now`, các hàm UTC, ISO và JSON không bị dịch giờ. Ngày giờ ISO không kèm
zone được hiểu theo múi giờ proxy; ISO chỉ có ngày vẫn giữ cách hiểu UTC.
Các định dạng ngày giờ cũ không chuẩn phụ thuộc bộ phân tích native của WebView;
tên múi giờ lịch sử có thể khác cách Date native hiển thị.

Không đổi múi giờ Android; không cần ADB, root, quyền hệ thống hoặc công cụ
chạy trên máy tính. Cơ chế chạy trong cả APK debug/release cài trên máy thật.
App xác nhận script trong document trống trước khi tải trang ngoài; API lỗi
hoặc WebView không áp dụng được sẽ báo lỗi và dừng mở trang. Cần build lại APK
để nhận thay đổi.

Giới hạn: đây là mô phỏng API JavaScript trong document/frame, không phải
múi giờ native của engine. Không áp dụng cho Web Worker, Service Worker,
Temporal hoặc điều khiển ngày/giờ native của Android; không cam kết mọi cách
kiểm tra đều trả cùng múi giờ. Script vẫn có thể được website nhận biết.

Kiểm thử JavaScript: `node --test test/webview_timezone_script_test.js`.
`WebViewTimeZoneTest` kiểm tra script thật trước JavaScript đầu tiên của trang
và iframe, lần lượt dùng New York/Tokyo, đồng thời xác nhận múi giờ và thiết lập
tự động của Android không đổi.

## Chọn sở thích

Khi modal **What would you like to watch on TikTok?** xuất hiện, app tự chọn
ngẫu nhiên 3 sở thích khác nhau rồi bấm **Continue** khi đã đủ 3 và nút được bật.
Nếu đã chọn sẵn 1–2 mục, app giữ các mục đó và chọn thêm cho đủ 3. Bộ quan sát
hoạt động cả khi modal xuất hiện muộn trong lúc xem, đăng ký hoặc đăng nhập;
không bấm lại Continue trong cùng modal và tạm ngưng khi trang ở nền.

## Ngôn ngữ WebView

Tạm tắt ép tiếng Anh khi chẩn đoán đăng ký: không gửi `Accept-Language`
tùy chỉnh, không chèn script sửa `navigator.language`/`navigator.languages`,
không ghi đè locale Android. iOS xóa các override `AppleLanguages`/`AppleLocale`
đã được app đặt trước đó. WebView dùng ngôn ngữ hệ thống; website vẫn có thể
ưu tiên ngôn ngữ đã lưu trong tài khoản/cookie.
`forceEnglishWebViewLocale=false` giữ script tiếng Anh trong mã để dễ bật lại;
muốn bật lại toàn bộ cần khôi phục cả cấu hình locale native.

## OTP API

**Đăng ký Android hiện tại:** toàn bộ thao tác UI dùng
`flutter_accessibility_service` và profile tọa độ đã ghi, gồm điều hướng,
chọn ngày sinh, dán email/OTP/mật khẩu và gửi biểu mẫu. Email/mật khẩu dùng
`ACTION_PASTE`; OTP dùng nhấn giữ → menu Paste bằng gesture vì paste trực tiếp
không điền được sáu ô ở lượt thử. App tự chọn năm → tháng → ngày theo cấu hình
hoặc ngày ngẫu nhiên 1960–2004. Với dropdown HTML không lộ các mục qua
Accessibility, app chỉ đọc nhãn/vị trí từ DOM rồi bấm/cuộn bằng Accessibility.
Đã kiểm chứng riêng bước này trên giả lập với **28/10/1967**. App đọc lại giá
trị ngày sinh trước khi gửi mã. Xem
[tài liệu ghi mẫu Android](docs/android-signup-coordinate-calibration.md).
Lượt ghi mẫu thật đã thành công; phát lại hoàn toàn tự động và gọi API OTP
chưa được xác minh. Hai cờ `_pauseSignupGestures`/`_pauseSignupFieldInput`
chỉ còn tác động luồng đăng ký JavaScript cũ.

Luồng đăng ký và đăng nhập dùng tài khoản và mật khẩu hộp thư của
cấu hình đang chọn. Tạo hoặc sửa dữ liệu qua **Quản lý cấu hình** trên
màn **Home**, rồi chọn cấu hình để sử dụng.

**Đăng nhập Android hiện tại:** toàn bộ thao tác UI dùng
`flutter_accessibility_service`, chung cơ chế snapshot, gesture và paste với
đăng ký. App mở Log in → Use phone or email → Email / Username, dán tài khoản
và mật khẩu bằng `ACTION_PASTE`, rồi chạm nút đăng nhập. Khi có xác minh,
app chờ ô Email ổn định 5 giây, chọn Email, chờ màn OTP hoặc xác nhận gửi mã
rồi mới lấy OTP từ API. OTP sáu ô dùng nhấn giữ → menu Paste; OTP một ô dạng
số dùng `ACTION_SET_TEXT` của Accessibility vì WebView không nhận Paste cho
kiểu ô này. Next/Continue cũng
được chạm bằng Accessibility. Tọa độ đăng nhập lưu trong
`assets/login-coordinate-profile.json` và `SharedPreferences`, phát lại trong
cùng khung WebView 400×800 qua ScreenUtil như đăng ký. Đã ghi thực tế 12 điểm,
gồm mở biểu mẫu, focus tài khoản/mật khẩu, Continue, Email xác minh, focus OTP,
Next, Resend code và 2 điểm hỗ trợ quay lại/xóa email khi ghi mẫu. Tài khoản
thứ ba đã xác minh OTP thật và về trang chủ có Messages + Profile.
Lượt này chọn Email tự gửi mã, không có Send code riêng. App lưu điểm của bước chưa có
trước thao tác đầu rồi dùng lại cho các lượt sau. Điểm đã có mà lệch control
sẽ dừng để ghi lại. Xem [ghi mẫu đăng nhập](docs/android-login-coordinate-calibration.md).
Luồng không đọc DOM,
không dùng JavaScript click/fill hay `InputConnection` cho đăng nhập Android.
Mỗi bước gửi chỉ chạm một lần; Dừng, đưa app ra nền, rời TikTok, CAPTCHA hoặc
lỗi biểu mẫu sẽ dừng luồng. Sau khi xác nhận đăng nhập, app vẫn lưu phiên và
tự bật Auto nuôi ngẫu nhiên 2–3 phút. Kiểm thử tự động dùng màn hình mô phỏng; luồng mới
chưa được xác minh trọn vẹn với tài khoản TikTok thật.

Các mô tả thao tác JavaScript/DOM/cache và bộ nhập native bên dưới thuộc
luồng cũ trên các nền tảng khác. Hai luồng tài khoản Android dùng Accessibility
như mô tả ở trên. Auto nuôi Android cũng đã chuyển sang Accessibility: đọc
đồng hồ phát, chuyển video và nhập/gửi bình luận qua plugin, không dùng JS.
Tọa độ nút bình luận được tách theo video dọc/ngang và geometry khung phát trong
[`assets/nurture-coordinate-profile.json`](assets/nurture-coordinate-profile.json).
Đã ghi mẫu mở/đóng bình luận và chuyển bài thật ở cả hai dạng. Xem
[ghi mẫu nuôi tài khoản](docs/android-nurture-coordinate-calibration.md) để biết
giới hạn đồng hồ một giây, cách ghi thêm bố cục và phạm vi kiểm chứng.

Đăng nhập Android gửi lại mã **tối đa 1 lần mỗi lượt** khi API lấy OTP hết
thời gian chờ. App hủy request cũ, chờ Resend code bật rồi chạm tại tọa độ đã
lưu, chờ TikTok hiện đếm ngược mới gọi API lấy mã mới. Nếu lại timeout, app
dừng; lỗi token/hộp thư/kết nối và bản nháp trong ô OTP không kích hoạt gửi lại.
Ở luồng đăng ký cũ, app tự tạo ngày sinh ngẫu nhiên trong khoảng 1960–2004,
bao gồm ngày hợp lệ theo số ngày của từng tháng và năm nhuận.
Luồng **Tự động đăng ký** mở trang chủ TikTok → xem video → bấm tim → mở dialog Login
→ bấm Sign up → Use phone or email → Use Email, rồi tiếp tục điền ngày sinh,
email, mật khẩu và xử lý OTP như trước. Biểu mẫu trong dialog được hỗ trợ cả
khi URL vẫn ở trang chủ.
Sau khi gửi OTP và mật khẩu, nếu xuất hiện màn **Create username**, app chờ
2 giây khi nút **Skip** sẵn sàng rồi bấm một lần để bỏ qua bước tạo tên người
dùng, kể cả khi tên gợi ý không khả dụng. Trên Android, nút Skip dùng
`dispatchGesture()` tại tọa độ hiện tại trong WebView. App tiếp tục chờ xác nhận đăng ký
thành công; nút **Dừng** vẫn hủy được thao tác trong thời gian chờ.
Sau khi TikTok xác nhận đăng ký thành công, app lưu **Đã đăng ký**, giữ màn hiện
tại và chờ ngẫu nhiên **2–4 phút**, rồi mở menu TikTok để **đăng xuất**. Chỉ khi
hai lần kiểm tra liên tiếp xác nhận đã đăng xuất, app mới quay về **Home**.
Home chờ ngẫu nhiên **2–3 phút** rồi mở lại đúng cấu hình để chạy đăng nhập tự động.
Cả hai màn chờ đều có nút hủy. Lịch chỉ tiếp tục khi app ở foreground; quay lại
không bốc thăm lại thời gian. Đóng màn hoặc hủy lịch sẽ dừng chuỗi tự động.
Nếu đăng xuất không thành công hoặc cấu hình thay đổi, app dừng và báo lỗi,
không đăng nhập tài khoản khác. **Auto nuôi** chỉ bật sau khi luồng đăng nhập
tự động xác nhận thành công.

Luồng **Tự động đăng nhập cũ** mở trang chủ TikTok → xem video → bấm tim → mở dialog Login
→ Use phone or email → Username or Email, rồi tiếp tục nhập tài khoản, mật khẩu
và xử lý OTP như trước, kể cả khi dialog giữ nguyên URL trang chủ.
Khi luồng đăng nhập tự động xác nhận thành công (hoặc tài khoản đã đăng nhập), app tự
bật Auto nuôi trong **2–3 phút** (ngẫu nhiên mỗi phiên) tính từ lần xác nhận đó. Khi hết thời gian, app
dừng nuôi, tự quay về **Home** và báo **Đã nuôi xong**; giữ nguyên phiên đăng nhập,
không đăng xuất và không xóa cookie. Tải lại trang hoặc
đưa app ra nền rồi quay lại không đặt lại thời hạn. Có thể bấm nút dừng nuôi
để kết thúc sớm; đóng màn TikTok sẽ hủy phiên nuôi và bộ hẹn giờ.

Nhận diện đăng nhập hỗ trợ cả `nav-messages` của bố cục desktop mới khi
`profile-icon` bị ẩn. App chưa báo thành công nếu còn form đăng nhập/xác minh
hoặc CAPTCHA; avatar của tác giả video và liên kết Profile không đủ để xác nhận.
Nếu luồng tự động dừng để người dùng xử lý OTP/CAPTCHA hoặc nhập thủ công,
app không theo dõi để tự bật Auto nuôi. Cần chạy lại luồng đăng nhập tự động
và được xác nhận thành công mới bật nuôi.

Mô tả watcher cũ dưới đây áp dụng trên các nền tảng dùng JavaScript. Android
giữ quy tắc chọn kế hoạch/bình luận nhưng quan sát đồng hồ Accessibility một giây;
bài ảnh/bố cục không có đồng hồ chưa hỗ trợ sẽ dừng để kiểm tra.

Auto nuôi bốc thăm độc lập cho mỗi video: 50% xem đến hết, 50% lướt sớm sau
khoảng 2–5 giây phát thực tế (clip ngắn hơn sẽ lướt trước khi hết). Không ép
xen kẽ; có thể gặp nhiều video cùng lựa chọn liên tiếp. Kế hoạch của mỗi bài
được giữ khi tạm dừng rồi khởi động lại watcher trong cùng trang.
Video dài hơn 1 phút chỉ xem 1 phút rồi chuyển (vẫn tính là xem hết).
Chỉ video có mục tiêu xem hết mới được bình luận. Android bắt đầu bình luận ở
giây 3 đến tối đa nửa thời gian xem, không muộn hơn giây 20 (nền tảng JavaScript
vẫn chọn trong khoảng 5 giây đến 70% thời lượng video), chuẩn bị ô nhập trước đó và kiểm tra lại
mốc 70% ngay trước khi gửi. Chừa một nhịp kiểm tra 250 ms ở cuối khoảng để bù
độ trễ; video quá ngắn hoặc chưa có thời lượng hợp lệ sẽ bỏ bình luận.
Thời gian video đứng tải/tạm dừng không tính vào thời gian chờ. Nếu đã nhập bản
nháp nhưng quá mốc 70%, app dừng và giữ bản nháp, không gửi muộn. Bài ảnh vẫn
chuyển sau 5 giây và không được bình luận theo quy tắc video này.

Khi hiện **Verify it’s really you**, app chờ 5 giây trước khi chọn ô **Email**.
Trên Android, app dùng vùng bấm đã cache khi còn hợp lệ và dùng `dispatchGesture()` chạm
140 ms, có kiểm tra ô đang hiển thị và không bị che. Sau đó app chờ TikTok
mở bước nhập mã rồi gọi API OTP. Luồng đăng nhập có tối đa 180 giây để mở
biểu mẫu; sau khi gửi mật khẩu, chọn Email hoặc gửi OTP, mỗi bước có thêm
45 giây chờ kết quả để tránh dừng ngay khi hộp xác minh xuất hiện trên mạng chậm.
Nếu bấm tim chưa mở modal, app chờ ít nhất 15 giây giữa các lần thử, tối đa
3 lần, rồi dùng Account dự phòng. Account cũng thử tối đa 3 lần cách nhau ít
nhất 15 giây. Khi modal xuất hiện, app dừng bấm lại ngay; không bấm nút đang
bị che, bị tắt hoặc bỏ thích video đã được thích. Mỗi lần chạy có trạng thái
thử lại riêng. Các nút gửi thông tin tài khoản và gửi OTP vẫn chỉ bấm một lần.
Đăng ký và đăng nhập tự động nghỉ ngẫu nhiên 2–10 giây giữa các thao tác thông thường.
Từ bước yêu cầu/nhập OTP, app kiểm tra mỗi 200–400 ms để nhập mã và bấm tiếp
ngay khi sẵn sàng; không chờ cố định 5 giây trước khi nhập OTP.
Các bước chọn phương thức/email, gửi mã, xác nhận OTP, gửi mật khẩu,
đăng ký và Skip đều có chốt theo bước trong mỗi lần chạy. Trang tạo lại nút DOM
không khiến app bấm lại bước đã thực hiện; cùng một nút vẫn có thể được dùng
ở hai bước khác nhau như gửi mật khẩu rồi xác nhận OTP. Trên Android, Send code
của cả đăng ký và đăng nhập, ô Email xác minh đăng nhập, Sign up sau OTP, Skip tạo username và Continue
trong biểu mẫu đăng nhập dùng
`flutter_accessibility_service 1.2.0` (bản vá cục bộ trong `third_party/`) để
`dispatchGesture()` một cú chạm 140 ms tại tọa độ nút trong WebView, sau khi
kiểm tra nút đang hiển thị, được bật và không bị che. Không cần node Accessibility
để bấm tọa độ; các sự kiện System UI không làm mất mục tiêu. Mỗi bước chỉ yêu cầu một gesture
trong mỗi lượt chạy; cần bật quyền Trợ năng cho Tool TikTok. Các nút còn lại gọi click một lần.
Continue/Tiếp tục và Next/Tiếp theo có chốt riêng cho bước gửi mật khẩu và bước xác nhận OTP,
kể cả khi trang dùng lại cùng một nút. App dùng cache vùng bấm khi chạm và dừng nếu
gesture không hoàn tất.
Cache vùng bấm tách theo luồng và nút (Send code, Email xác minh, Continue mật khẩu,
Continue OTP, Sign up, Skip), lưu tối đa 16 vùng trong trang. Lần dùng lại không đo
DOM nếu vùng cũ vẫn trúng đúng nút hiện tại, kể cả khi trang phát sinh layout,
đổi bước hoặc cuộn nền nhưng modal vẫn đứng yên. Chỉ đo lại khi điểm cũ không
còn trúng nút hoặc kích thước/viewport thực sự thay đổi. Phía Android cũng cache
vị trí, kích thước và vùng hiển thị của WebView; sự kiện layout không đổi hình học
không xoá cache. Khi gesture thất bại hoặc hết thời gian chờ, app bỏ cache của
đúng nút đó để lần chạy sau đo lại; không tự gửi thêm gesture cho bước đang chạy.
Cache nằm trong RAM, tự bỏ khi trang/WebView được tạo lại; không
lưu tọa độ cố định để dùng trên màn hình khác.
Bản vá Trợ năng cho phép Android khởi động dịch vụ trước khi Flutter engine của
overlay sẵn sàng, tránh crash khi hệ thống kết nối lại dịch vụ lúc mở/cài lại app.
Bước Send code đăng nhập cũng
chờ bộ đếm gửi lại hoặc màn OTP xác nhận gửi mã; hết 15 giây không có xác nhận
thì dừng, chưa gọi API lấy OTP và không tự gửi lại mã.

App luôn lấy OTP qua API cho **Đăng nhập** và **Đăng ký**. App chỉ dùng
`otp_api_url` và `otp_api_token` từ Firebase Remote Config cho cả hai luồng;
các giá trị đã lưu trên thiết bị không còn được dùng. Màn Cài đặt không có mục
nhập hoặc xem cấu hình API OTP/CAPTCHA.
URL API chấp nhận cả HTTP và HTTPS. Nếu API chạy trên máy tính, Android Emulator
dùng `10.0.2.2`, iOS Simulator trên cùng máy dùng `127.0.0.1`; điện thoại thật
dùng IP LAN của máy tính hoặc địa chỉ API truy cập được từ thiết bị.
Nhập mật khẩu hộp thư của email trong màn tạo hoặc sửa cấu hình.
Mật khẩu hộp thư là trường riêng với mật khẩu TikTok. App tự lấy mã OTP từ API.

App dùng thư viện `http` để gọi `POST /api/code` sau khi TikTok yêu cầu OTP, với JSON
`{"email":"email|mật khẩu hộp thư","wait":180}` và headers
`X-Reader-Token`, `ngrok-skip-browser-warning: 1`. Khi API trả
`{"ok":true,"code":"012345"}`, app nhập mã bằng bộ nhập native rồi xác nhận.
Trên Android, OTP đăng ký và đăng nhập được sao chép đủ sáu số vào clipboard
rồi dán bằng `InputConnection.performContextMenuAction(android.R.id.paste)`.
App kiểm tra đúng ô đang focus và trạng thái tác vụ trước khi dán; chỉ xác nhận
khi WebView đã nhận đủ mã, kể cả khi trang phân phối mã vào sáu ô riêng.
Email, mật khẩu và bình luận tiếp tục dùng `InputConnection.commitText`,
cùng cơ chế nhập của bàn phím. iOS vẫn dùng clipboard native.
Trong thời gian chờ, app vẫn theo dõi CAPTCHA, lỗi biểu mẫu và nút Dừng.
Ở luồng đăng ký, app chờ 5 giây sau khi nhập xong thông tin và nút Send code
được bật. Nếu nút bị thay thế hoặc tắt, thời gian chờ bắt đầu lại.
Ở luồng đăng ký Android, app bỏ focus khỏi ô vừa nhập và chạm Send code qua
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
có nút **Cấu hình** trở về màn trước và giữ thông tin đã nhập. Toast tự ẩn sau
vài giây, kể cả khi có nút thao tác. Trạng thái auto và nút Dừng nằm trong
overlay nhỏ phía dưới; lỗi tải trang dùng overlay nhỏ có nút **Thử lại**.
Thanh tiến trình cũng nằm đè lên WebView, không thay đổi chiều cao AppBar.
WebView giữ nguyên kích thước khi tải trang, hiện thông báo hoặc mở bàn phím.
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

Tự giải CAPTCHA xoay trên Android: cấu hình String `sadcaptcha_license_key` trong
Firebase Remote Config và bật Trợ năng. Key rỗng trên Remote Config sẽ tắt tự giải.
Cả OTP và CAPTCHA dùng mặc định khai báo tại `RemoteConfigKey.defaultValue` khi
chưa có giá trị trên Firebase; app đăng ký các mặc định này bằng `setDefaults()`.
App fetch và activate khi khởi động; nếu mất mạng sẽ dùng cấu hình Firebase đã
cache hoặc mặc định. Không đọc các giá trị OTP/CAPTCHA cũ trong SharedPreferences.
Bộ theo dõi chỉ chạy khi Auto nuôi đang bật, áp dụng cho cả news feed
và search keyword, trên cả Home/Profile/trang tìm kiếm/video chi tiết;
tắt hoặc kết thúc nuôi sẽ hủy theo dõi và lượt giải đang chờ. App gọi SadCaptcha và kéo bằng
`flutter_accessibility_service`; chỉ tiếp tục khi CAPTCHA biến mất. Xem [hướng dẫn tích hợp](tiktok_rotate_captcha_guide.md#6-tích-hợp-trong-ứng-dụng-flutter-hiện-tại).
