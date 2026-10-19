# Hướng dẫn sử dụng Tool TikTok

Cập nhật theo giao diện chức năng ngày **18/10/2026**.

Tool quản lý cấu hình proxy và tài khoản, chạy đăng ký lần lượt, đăng nhập để nuôi tài khoản, theo dõi kết quả và xuất dữ liệu Excel. Hướng dẫn thao tác tự động dưới đây tập trung vào Android, nơi ứng dụng sử dụng quyền Trợ năng.

## 1. Bắt đầu nhanh

1. Mở tool, bấm biểu tượng bánh răng để vào **Cài đặt**.
2. Bật **Quyền Trợ năng** cho Tool TikTok trong phần cài đặt Android, sau đó quay lại tool.
3. Vào **Cấu hình → Quản lý cấu hình → dấu +** để thêm proxy và tài khoản.
4. Nhập email, mật khẩu TikTok, mật khẩu email lấy OTP và kiểm tra **Cấu hình nuôi** trước khi lưu.
5. Với tài khoản chưa đăng ký, vào tab **Đăng ký**. Với tài khoản đã có, bật **Đã đăng ký** khi tạo/sửa rồi vào tab **Nuôi**.
6. Chạm tài khoản muốn **Chạy trước**, sau đó bấm nút chạy ở cuối tab.
7. Theo dõi kết quả; xử lý đăng ký thất bại trong tab **Cấu hình lỗi**.
8. Vào **Cài đặt → Xuất dữ liệu Excel → Xem trước / Xuất Excel** để lưu dữ liệu.

**Nút chạy thực hiện lần lượt các cấu hình đủ điều kiện trong tab.** Chạm một thẻ chỉ chọn cấu hình chạy đầu tiên, không giới hạn lượt chạy vào riêng thẻ đó.

## 2. Chuẩn bị trước khi chạy

Bạn cần có kết nối Internet, dữ liệu tài khoản và proxy nếu sử dụng kết nối qua proxy. Mật khẩu TikTok và mật khẩu hộp thư lấy OTP là **hai trường riêng biệt**.

Trên Android, quyền Trợ năng giúp tool nhập liệu, chạm nút và vuốt video. Công tắc **Quyền Trợ năng** trong tool mở cài đặt của Android; bạn cần bật dịch vụ tại đó. Khi quay lại, tool cập nhật trạng thái quyền. Nếu vừa cài lại ứng dụng, hãy kiểm tra lại quyền này.

Giữ tool ở màn hình trước khi đang chạy tự động để các thao tác Trợ năng thực hiện được. Hạn chế tự bấm vào trang TikTok khi tool đang nhập liệu hoặc chuyển bước.

API lấy OTP, key xử lý CAPTCHA, từ khóa và nội dung bình luận do người quản trị cấu hình qua **Firebase Remote Config**. Màn Cài đặt không có ô nhập URL/token OTP hoặc key CAPTCHA. Nếu tool báo thiếu các giá trị này, nhờ người quản trị kiểm tra theo [hướng dẫn cấu hình Firebase](huong-dan-cau-hinh-firebase.md).

## 3. Các khu vực trên màn Home

| Khu vực | Dùng để làm gì? |
| --- | --- |
| **Cấu hình** | Mở quản lý cấu hình; xem từ khóa tìm kiếm và danh sách bình luận đang dùng. |
| **Đăng ký** | Chạy các cấu hình có tài khoản chưa đăng ký và chưa nằm trong danh sách lỗi đăng ký. |
| **Nuôi** | Chạy tài khoản đã đăng ký và xem thống kê nuôi. |
| **Cấu hình lỗi** | Xem nguyên nhân đăng ký thất bại, chạy lại hoặc bỏ đánh dấu lỗi. |
| **Biểu tượng bánh răng** | Mở Cài đặt: quyền Trợ năng, xem trước/xuất Excel và hướng dẫn trong ứng dụng. |

Ở các tab **Đăng ký**, **Nuôi** và **Cấu hình lỗi**, kéo danh sách xuống để làm mới dữ liệu.

## 4. Thêm một cấu hình

Vào **Cấu hình → Quản lý cấu hình**, bấm **dấu +** ở góc trên để mở màn **Tạo cấu hình**.

### 4.1. Proxy và thông tin trình duyệt

| Trường | Cách nhập hoặc sử dụng |
| --- | --- |
| **Địa chỉ proxy** | Nhập địa chỉ và cổng, ví dụ `http://192.0.2.10:8080`. Thay bằng proxy thực tế được cấp. |
| **Tên đăng nhập proxy** | Nhập nếu nhà cung cấp proxy yêu cầu xác thực. |
| **Mật khẩu proxy** | Nhập tương ứng với tên đăng nhập proxy; khác với mật khẩu tài khoản TikTok. |
| **User-Agent** | Có sẵn khi tạo mới. Bấm **Đổi User-Agent** để tạo mẫu khác, hoặc dùng các nút chọn mẫu trình duyệt có trên form. |
| **Múi giờ WebView** | Bấm **Tra theo proxy**, nhập mã IANA như `America/New_York`, hoặc để trống để tự tra khi mở WebView. |
| **Thiết bị (GPU)** | Tool chọn ngẫu nhiên một hồ sơ GPU và giữ cho cấu hình đó. Bấm **Đổi** nếu muốn chọn hồ sơ khác. |

Trên Android, chế độ tự động mặc định dùng nhận diện Chrome desktop theo phiên bản WebView đang cài. Vì vậy User-Agent thực tế khi chạy tự động có thể khác mẫu được lưu trong form. Mục **Thiết bị (GPU)** là hồ sơ GPU trang web nhận được, không thay đổi điện thoại vật lý.

### 4.2. Tài khoản và trạng thái

1. Nhập **Email đăng ký**.
2. Kiểm tra **Mật khẩu TikTok**. Form mới tạo sẵn mật khẩu; nút đổi ở ô này tạo mật khẩu khác. Với tài khoản đã có, nhập đúng mật khẩu của tài khoản đó.
3. Nhập **Mật khẩu email lấy OTP** để dịch vụ OTP truy cập đúng hộp thư.
4. Đặt công tắc **Đã đăng ký**:
   - **Tắt:** tài khoản chờ đăng ký, xuất hiện ở tab Đăng ký nếu chưa có lỗi đăng ký.
   - **Bật:** tài khoản đã tồn tại, xuất hiện ở tab Nuôi để đăng nhập và nuôi.
5. Chọn **Nuôi sau khi đăng ký** nếu muốn tài khoản mới được nuôi ngay sau khi đăng ký thành công.
6. Kiểm tra phần Cấu hình nuôi, rồi bấm **Tạo cấu hình** ở cuối màn hình.

Bật **Đã đăng ký** chỉ cập nhật trạng thái quản lý trong tool; thao tác này không tạo tài khoản TikTok. Khi tool đăng ký thành công, trạng thái của cấu hình được cập nhật tự động.

### 4.3. Cấu hình nuôi

Mỗi cấu hình có bộ thông số nuôi riêng:

| Thông số | Mặc định | Ý nghĩa |
| --- | --- | --- |
| **Thả tim** | 30% | Tỷ lệ chọn video để thả tim. |
| **Bình luận** | 20% | Tỷ lệ chọn video để bình luận bằng nội dung trong danh sách. |
| **Tỷ lệ xem lâu (không vuốt ngay)** | 50% | Áp dụng cho các video còn lại không được chọn thả tim hoặc bình luận. |
| **Nuôi tối thiểu** | 2 phút | Cận dưới thời gian nuôi một phiên. |
| **Nuôi tối đa** | 3 phút | Cận trên thời gian nuôi một phiên. |

Các tỷ lệ nhận số nguyên từ **0–100%**, không cần cộng lại thành 100%. Thời gian nuôi nhận số nguyên từ **1–120 phút**, tối thiểu không được lớn hơn tối đa. Tool chọn thời lượng ngẫu nhiên trong khoảng đã nhập.

Video được chọn thả tim hoặc bình luận sẽ được xem hết theo luồng nuôi. Các video còn lại được xem lâu theo tỷ lệ đã đặt; nếu không, tool vuốt sau vài giây. Tỷ lệ là lựa chọn ngẫu nhiên, không phải cam kết số hành động chính xác trong mỗi phiên ngắn.

Bấm **Mặc định** để điền lại các giá trị mặc định trong form; bấm nút tạo/lưu để lưu thay đổi.

## 5. Import nhiều cấu hình

Trong màn **Tạo cấu hình**, bấm **Import data** và chọn **Từ file** hoặc **Dán từ clipboard**.

### 5.1. TXT hoặc clipboard

Mỗi cấu hình nằm trên một dòng, theo mẫu:

```text
host:port:username:password|email|mật_khẩu_TikTok|mật_khẩu_email_OTP|trạng_thái
```

Ví dụ minh họa, cần thay toàn bộ bằng dữ liệu thực tế:

```text
192.0.2.10:8080:proxy_user:proxy_pass|account01@example.com|SamplePass12|mail_pass_01|0
192.0.2.11:8080:proxy_user:proxy_pass|account02@example.com|SamplePass34|mail_pass_02|1
```

- Dấu `|` ngăn cách các trường; không thêm dấu này vào nội dung mật khẩu.
- Trạng thái `0` là **Chưa đăng ký**, `1` là **Đã đăng ký**.
- Có thể bỏ trường trạng thái; khi đó tool dùng **Chưa đăng ký**, kể cả khi công tắc trên form trước đó đang bật.
- Nếu để trống mật khẩu TikTok giữa hai dấu `|`, tool tạo mật khẩu mới. Chỉ dùng cách này cho tài khoản cần tạo mới; với tài khoản đã có phải nhập mật khẩu đúng.
- Dòng trống được bỏ qua. File TXT dùng UTF-8 hoặc Unicode UTF-16.

Bạn cũng có thể dán nội dung vào ô import trên form rồi bấm **dấu ✓** để đọc dữ liệu. Muốn đọc file, dùng **Từ file**; dán tên hoặc đường dẫn file vào ô sẽ không đọc được nội dung file.

### 5.2. File Excel

Chọn **Import data → Từ file** và chọn Excel `.xlsx` hoặc `.xls`. Nên dùng `.xlsx`; nếu file `.xls` không đọc được, mở bằng phần mềm bảng tính và lưu lại thành `.xlsx`.

Một dòng tương ứng một cấu hình. Cách dễ kiểm tra nhất là dùng các cột sau:

| Proxy | Email | Password | Mail Password | Status |
| --- | --- | --- | --- | --- |
| `192.0.2.10:8080:proxy_user:proxy_pass` | `account01@example.com` | `SamplePass12` | `mail_pass_01` | `0` |

Cột trạng thái có thể bỏ. Tool cũng đọc được một ô chứa cả dòng dữ liệu như mẫu TXT, hoặc hai cột gồm proxy và chuỗi `email|mật khẩu TikTok|mật khẩu email OTP`. Có thể đặt tiêu đề `Proxy` hoặc `Data` ở dòng đầu.

### 5.3. Kiểm tra và lưu danh sách đã import

1. Sau khi đọc dữ liệu, mỗi dòng xuất hiện thành một mục **Thông tin cấu hình** riêng.
2. Kiểm tra proxy, email, hai loại mật khẩu và trạng thái của từng mục.
3. Chỉnh User-Agent, múi giờ, GPU và cấu hình nuôi nếu cần.
4. Bấm **Tạo N cấu hình** để lưu cả danh sách.

Import vào form chưa đồng nghĩa đã lưu. Nếu có dòng không hợp lệ, tool báo số dòng; với Excel có thêm tên sheet. Sửa dữ liệu rồi import lại. Thao tác lưu nhiều cấu hình được thực hiện cùng một giao dịch để tránh lưu dở một phần khi có lỗi.

## 6. Tìm, sửa, xóa và kiểm tra IP

Vào **Cấu hình → Quản lý cấu hình**:

- Dùng ô tìm kiếm để tìm theo tên, địa chỉ proxy hoặc email.
- Dùng bộ lọc **Tất cả**, **Chưa dùng**, **Đã dùng** để thu gọn danh sách.
- Mở menu **⋮** của cấu hình để chọn **Sửa**, **Xóa** hoặc **Kiểm tra IP**.

**Sửa:** cập nhật các trường cần đổi rồi lưu ở cuối màn hình. Dùng thao tác này để bổ sung mật khẩu, đổi trạng thái đã đăng ký hoặc chỉnh thông số nuôi.

**Xóa:** tool hỏi xác nhận trước khi bỏ cấu hình khỏi danh sách.

**Kiểm tra IP:** tool xóa phiên WebView cũ, nạp cấu hình và mở WhatIsMyBrowser. Đối chiếu IP công khai mà trang hiển thị với IP đầu ra do nhà cung cấp proxy cung cấp. IP đầu ra có thể khác hostname/địa chỉ máy chủ proxy. Thao tác kiểm tra này không đánh dấu cấu hình là Đã dùng.

**Chưa dùng / Đã dùng** là trạng thái sử dụng cấu hình, độc lập với **Chưa đăng ký / Đã đăng ký** của tài khoản.

## 7. Xem từ khóa và danh sách bình luận

Trong tab **Cấu hình**, có hai khối:

- **Keyword search:** danh sách từ khóa có thể được chọn khi nuôi bằng tìm kiếm.
- **Danh sách comment:** nội dung có thể được chọn khi tự bình luận.

Mỗi khối chỉ hiện **3 mục đầu**; số trong tiêu đề là tổng số mục. Bấm **Xem tất cả** để mở màn danh sách đầy đủ và cuộn xem các mục còn lại. Bấm quay lại để về Home.

Các danh sách chỉ để xem trong tool. Người quản trị sửa trên Firebase Remote Config. Nếu danh sách từ khóa là `[]`, tool chỉ nuôi news feed; nếu danh sách bình luận là `[]`, tool không tự bình luận.

## 8. Chạy đăng ký lần lượt

1. Mở tab **Đăng ký**.
2. Kiểm tra danh sách chờ đăng ký. Nếu trống, thêm cấu hình chưa đăng ký hoặc xem tab Cấu hình lỗi.
3. Chạm cấu hình muốn chạy đầu tiên; thẻ đó có nhãn **Chạy trước**.
4. Bấm **Chạy đăng ký lần lượt tài khoản**.
5. Theo dõi trạng thái trên màn TikTok trong khi tool xử lý biểu mẫu và lấy OTP qua API.

Với mỗi cấu hình, tool bắt đầu bằng phiên WebView sạch và nạp proxy cùng thông tin tương ứng. Khi đăng ký thành công, tài khoản được đánh dấu Đã đăng ký. Nếu đã chọn **Nuôi sau khi đăng ký**, tool tiếp tục nuôi theo thông số của cấu hình đó.

Khi kết thúc, tool giữ màn hình ngẫu nhiên **1–2 phút** trước khi đăng xuất. Giữa hai cấu hình có khoảng nghỉ ngẫu nhiên **5–15 giây**, sau đó tiếp tục theo thứ tự danh sách. Thời gian chờ này là một phần của lượt chạy.

Cấu hình đăng ký thất bại được đưa vào tab **Cấu hình lỗi**. Lượt đăng ký thông thường bỏ qua các cấu hình đang bị đánh dấu lỗi.

## 9. Chạy nuôi tài khoản

1. Mở tab **Nuôi**.
2. Nếu tài khoản đã có chưa xuất hiện, vào Quản lý cấu hình, sửa và bật **Đã đăng ký**, sau đó lưu.
3. Chạm tài khoản muốn nuôi đầu tiên để đặt **Chạy trước**.
4. Bấm **Chạy nuôi lần lượt các tài khoản**.
5. Tool đăng nhập từng cấu hình, nuôi trong khoảng thời gian đã đặt, giữ màn hình 1–2 phút rồi đăng xuất và chuyển tài khoản tiếp theo.

Mỗi phiên chọn ngẫu nhiên giữa news feed và tìm kiếm từ khóa; khi chọn tìm kiếm, từ khóa được chọn ngẫu nhiên trong danh sách đang dùng. Các thao tác thả tim, bình luận và thời gian xem tuân theo cấu hình nuôi của tài khoản.

Trên màn TikTok, nút **Auto nuôi** bật/tắt phần tự xem và tương tác khi đủ điều kiện đăng nhập. Nút **Tải lại** mở lại trang hiện tại.

### Đọc thống kê

Thẻ tài khoản hiển thị thời điểm tạo tài khoản nếu có, số lần nuôi, lần nuôi cuối, thời gian xem video, số video đã xem, số lượt thả tim và bình luận. Số lần nuôi ghi nhận các phiên đã xem ít nhất một video.

Thống kê được gộp theo email, không phân biệt chữ hoa/chữ thường. Vì vậy nhiều cấu hình dùng cùng email có thể cùng tham chiếu thống kê của tài khoản đó. Kéo xuống để tải lại số liệu sau lượt chạy.

## 10. Dừng tác vụ và xử lý cấu hình lỗi

### Dừng tác vụ

- Khi đang ở màn TikTok, bấm **Dừng** trong khung trạng thái tự động để dừng luồng đang chạy.
- Trên Home, thanh tiến độ hiển thị số cấu hình đã xử lý, số xong/lỗi và nút **Dừng** để dừng chuỗi tự chạy.
- Đóng màn TikTok bằng thao tác quay lại cũng kết thúc chuỗi tự chạy; tool không tự mở cấu hình tiếp theo từ thao tác đóng màn đó.

Một cấu hình quá thời gian cho phép sẽ bị dừng để chuỗi tiếp tục. Giới hạn mặc định là **15 phút**; nếu thời gian nuôi tối đa dài hơn, giới hạn được tăng thành thời gian nuôi tối đa cộng **12 phút** khi giá trị này lớn hơn 15 phút.

### Đọc lỗi và chạy lại

1. Mở tab **Cấu hình lỗi**.
2. Xem lý do, bước xảy ra lỗi và nhật ký các lần thất bại.
3. Sửa dữ liệu hoặc khắc phục kết nối/quyền/dịch vụ tương ứng trước khi chạy lại.
4. Chạm cấu hình muốn chạy lại trước, rồi bấm **Chạy đăng ký lần lượt lại tài khoản** để chạy các cấu hình lỗi.

Nút **Bỏ khỏi danh sách lỗi** chỉ bỏ đánh dấu lỗi để cấu hình chưa đăng ký trở lại tab Đăng ký; không xóa cấu hình và không tạo tài khoản.

## 11. Xem trước và xuất Excel

1. Từ Home, mở **Cài đặt** bằng biểu tượng bánh răng.
2. Tìm mục **Xuất dữ liệu Excel**.
3. Bấm **Xem trước** để kiểm tra bảng dữ liệu; kéo ngang để xem các cột bên phải.
4. Bấm **Xuất Excel** trong màn xem trước hoặc ngay ở Cài đặt.
5. Chọn nơi lưu file `.xlsx` theo hộp thoại của thiết bị.

File có sheet **Data**, mỗi cấu hình một hàng. Nội dung gồm proxy, email, mật khẩu TikTok, mật khẩu email, trạng thái đăng ký, User-Agent, múi giờ, trạng thái đã sử dụng, thiết bị GPU, thông số nuôi và các cột thống kê nuôi được hỗ trợ.

Có thể import lại file này qua **Import data → Từ file** để tạo cấu hình, khôi phục thông tin tài khoản, trạng thái đăng ký, cấu hình nuôi và GPU. **Import không khôi phục toàn bộ lịch sử chạy hoặc thống kê nuôi.** User-Agent, múi giờ và trạng thái đã dùng trong file xuất hiện tại cũng không được bộ import phục hồi; kiểm tra lại các trường này trên form trước khi lưu.

File Excel chứa mật khẩu dưới dạng đọc được, giống các trường hiển thị trực tiếp trong ứng dụng. Lưu file ở nơi riêng tư; khi gửi ảnh hoặc dữ liệu để hỗ trợ, che mật khẩu, token và mã OTP.

## 12. Một số tình huống thường gặp

| Hiện tượng | Cách kiểm tra và xử lý |
| --- | --- |
| Nút chạy bị mờ | Kiểm tra có cấu hình đủ điều kiện trong tab, dữ liệu đã tải xong và không có tác vụ khác đang chạy. |
| Tab Đăng ký không có tài khoản | Kiểm tra trạng thái Chưa đăng ký, dữ liệu tài khoản và tab Cấu hình lỗi. |
| Tab Nuôi không có tài khoản | Bật Đã đăng ký cho tài khoản đã tồn tại, lưu lại rồi kéo xuống làm mới. |
| Tool không bấm hoặc không nhập liệu | Kiểm tra Quyền Trợ năng trong cài đặt Android, quay lại tool và giữ ứng dụng ở màn hình trước. |
| Không tải trang hoặc kiểm tra IP thất bại | Kiểm tra mạng, địa chỉ/cổng proxy và thông tin xác thực; dùng Kiểm tra IP để xác nhận kết nối trước khi chạy tài khoản. |
| Không lấy được OTP | Kiểm tra email và mật khẩu email lấy OTP; nhờ người quản trị kiểm tra URL, token và tình trạng dịch vụ OTP. |
| TikTok báo “Maximum number of attempts reached” | Xem thông báo và nhật ký lỗi, dừng lượt đang gặp lỗi để kiểm tra. Tool không tự gỡ giới hạn hoặc xác định được thời gian chờ do TikTok áp dụng. |
| CAPTCHA không được xử lý | Kiểm tra Trợ năng, kết nối và key dịch vụ với người quản trị. Tự xử lý phụ thuộc loại CAPTCHA và luồng được hỗ trợ; xem thông báo trên màn hiện tại. |
| Từ khóa/bình luận chưa đổi | Nhờ quản trị kiểm tra đã xuất bản Remote Config; dừng phiên, chờ ít nhất một phút rồi đóng hoàn toàn và mở lại tool khi có mạng. |
| Import báo lỗi dòng hoặc sheet | Sửa đúng vị trí được báo; kiểm tra dấu phân cách, đủ mật khẩu email và trạng thái chỉ là 0 hoặc 1. |
| Mở ứng dụng lại nhưng danh sách cấu hình không tải | Dùng Tải lại cấu hình hoặc Thử lại trên màn tương ứng. |

Để mở bản hướng dẫn ngắn ngay trong ứng dụng: **Cài đặt → Hướng dẫn sử dụng → Mở hướng dẫn sử dụng**.

## 13. Tài liệu cho người quản trị

- [Cấu hình Firebase Remote Config](huong-dan-cau-hinh-firebase.md): dịch vụ OTP, key CAPTCHA, từ khóa và bình luận.
- [README dự án](../README.md): thông tin kỹ thuật và cách chạy/build ứng dụng.
