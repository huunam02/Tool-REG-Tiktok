# Kiểm tra lại nuôi sau sửa delay — 24/10/2026

**Kết luận: hàng đợi chạy hết và đã có tương tác thành công, nhưng vẫn còn lỗi; chưa thể coi toàn bộ luồng đã ổn định.**

## Cách kiểm tra

- Máy ảo `emulator-5554`, Galaxy_S8_API_28, Android 9/API 28, ARM64, 1440×2960. Ứng dụng `com.brisklane.browser`.
- Trước cập nhật, dừng app ở Home để sao lưu toàn bộ dữ liệu vào thư mục riêng quyền 0700, tệp backup 0600 trong `/tmp/nurture-retest-20261024-100605/`. Đã đọc và kiểm tra `PRAGMA integrity_check` của DB sao lưu: OK. Không đưa backup chứa cookie/thông tin đăng nhập vào repo.
- Build debug từ mã hiện tại, cập nhật bằng `adb install -r`, mở Home. Không chạy connected instrumentation, không uninstall, không xóa dữ liệu hoặc load snapshot. Sau install đã bật lại dịch vụ Trợ năng trước khi chạy.
- Đọc source đang nạp trong Dart VM, xác nhận có delay 1,2 giây, chờ Next 30 giây, trạng thái bảo vệ nháp và kiểm tra Post trước paste.
- Bấm nút **Chạy nuôi lần lượt các tài khoản** qua ADB; thứ tự **4 → 5 → 1**. Không thay tỷ lệ, thời lượng, proxy, nội dung bình luận hoặc từ khóa để ép ca kiểm tra. Không hot reload hoặc thao tác thủ công trên trang trong lúc chạy. Chỉ đọc VM/snapshot và chụp ảnh.
- Theo giờ máy thu nhận +07:00, hàng đợi bắt đầu khoảng **10:07:19**, mẫu cuối **10:15:18** xác nhận `autoRun=null`, `autoRunSucceeded=3`, `autoRunFailed=0`, không còn TikTokController hoạt động. App còn chạy ở Home/tab Nuôi, dịch vụ Trợ năng vẫn bật.

**Lưu ý thời gian:** Android sau snapshot vẫn báo ngày 23/10 khoảng 22 giờ, lệch với thời gian thực tế Việt Nam ngày 24/10. Không sửa đồng hồ trong lúc chạy để tránh ảnh hưởng deadline. Các timestamp ADB/SQLite bên dưới là giờ thô của Android, không phải thời điểm thực tế; mẫu VM có trường `time` là giờ thu nhận đúng +07:00. Chọn phiên mới bằng ID chưa có trong baseline, không lọc theo `MAX(created_at)`; vì các phiên phục hồi trước đó có thời gian tương lai so với đồng hồ Android hiện tại. Đồng hồ lệch cũng là một giới hạn khi đánh giá lỗi máy chủ/cookie của lần chạy.

## Test tự động

- **117 test Dart đạt**: runner nuôi, controller phục hồi, Trợ năng, tạm dừng xác minh, giữ phiên và thiết lập nuôi.
- **56 test JavaScript đạt**: auto watch/bình luận.
- Analyze 5 file liên quan: **No issues found**.
- Debug APK ARM64 build thành công. Không chạy lại native instrumentation trên dữ liệu đang dùng.

## Kết quả SQLite của đúng lượt này

| Thứ tự | ID | Chế độ khởi đầu | Thời lượng phiên (giây) | Xem ghi nhận (giây) | Video | Tim | Bình luận | Phase |
|---|---|---|---:|---:|---:|---:|---:|---|
| 1 | 4 | Feed | 134.0 | 79 | 2 | 0 | 1 | completed |
| 2 | 5 | Search | 139.1 | 69 | 2 | 2 | 0 | completed |
| 3 | 1 | Search | 159.0 | 74 | 1 | 0 | 0 | completed |
| Tổng | | | | 222 | 5 | 2 | 1 | |

Cấu hình 1 đặt bình luận 40%, cấu hình 4 và 5 là 20%; cả ba tim 30%, xem lâu 50%, nuôi 2–3 phút. Đối chiếu trước/sau xác nhận các tỷ lệ và thời lượng giữ nguyên. Phase completed chỉ cho biết chạy tới hạn; không có nghĩa mọi thao tác thành công. Số video là số runner ghi nhận hoàn tất/bỏ qua, không phải mọi bài từng hiển thị. Thời gian tìm kiếm/CAPTCHA/tải trang hoặc thiếu clock không được tính thành thời gian xem.

## Các điểm đã xác nhận hoạt động

1. Cả ba tài khoản đều nhận lại trạng thái đăng nhập; không bị yêu cầu nhập lại thông tin trong lượt này. Hàng đợi tự chuyển đủ tài khoản.
2. Cấu hình 4 sau một lần phục hồi Feed đã xác nhận gửi **1 bình luận**, ADB thô `22:13:06.361`; SQLite lưu comments=1. Bình luận được xác nhận bằng editor rỗng và nội dung xuất hiện thêm theo runner. Không phát hiện gửi lặp trong log/bộ đếm của lượt này.
3. Cấu hình 5 chạy Search từ khóa `Street food`, qua CAPTCHA, chuyển video và ghi **2 tim** cuối phiên; `_nurtureRestarts=0`.
4. Cấu hình 4 và 1 mỗi tài khoản phục hồi một lần, deadline mỗi phiên chỉ có một giá trị trong mẫu VM, không bắt đầu lại thời lượng.

## Vấn đề vẫn tái hiện

### 1. Mất metadata/geometry Feed sau Next — tăng delay chưa xử lý gốc

- Cấu hình 4: ADB `22:12:07` chạm Next, `22:12:09` có clock mới `00:01 / 00:28` nhưng runner đọc trạng thái unreadable. Sau đủ 30 giây, `22:12:39.121` báo lỗi và tự tải lại để phục hồi.
- Snapshot ở thời điểm thu nhận `10:08:48` có WebView `(92,280)–(1348,2792)`. Clock video 28 giây ở y=3433–3479 và nút bình luận `28 comments` ở y=3165–3265, ngoài WebView, trong khi ảnh màn hình hiển thị đúng video và số bình luận 28. Nút bình luận nằm thấp hơn vị trí ảnh khoảng một chiều cao WebView (2512 px).
- **Đã có bằng chứng geometry Trợ năng lệch sau cuộn.** Chưa đủ để phân biệt nguyên nhân chính xác nằm ở cache Android, Gecko hay cách chuyển tọa độ trang. Không nên tiếp tục tăng timeout chỉ vì lỗi này: metadata sai kéo dài hơn 30 giây.
- Các Next khác có thể thành công; cấu hình 1 cuối phiên cũng có trạng thái unreadable gần hạn, timer vẫn kết thúc phiên bình thường. Không khẳng định mọi Next đều lỗi.

### 2. Feed mở/focus bình luận vẫn timeout

- Cấu hình 4, ADB `22:11:58.802`: timeout mở khung bình luận, bàn phím ẩn, ô nhập 0; bỏ qua trước paste và tiếp tục xem.
- Cấu hình 1 sau Search lỗi đã về Feed, ADB `22:18:06.132`: timeout đặt con trỏ, snapshot báo ô nhập `0/0/0`. App chặn bình luận tiếp trong runner đó và tiếp tục xem tới hạn; SQLite comments=0.
- Thông báo ở ca focus nói “giữ bản nháp” dù mẫu VM `_pendingCommentDraft=false` và chưa có bằng chứng nội dung được nhập. Thông báo này còn gây hiểu nhầm; không coi đây là bằng chứng có nháp hoặc bảo vệ nháp đã được thử trên thiết bị.

### 3. Search có thể trả trang lỗi

- Cấu hình 1 dùng `Book recommendations`, trang hiển thị **Something went wrong / Sorry, something wrong with the server, please try again**. Sau 60 giây tìm kiếm, ADB `22:17:29.513` báo không mở được video.
- App phục hồi về Feed (`_nurtureRestarts=1`) và xem tiếp, ghi nhận 74 giây xem, kết thúc đúng hạn. Không xác định được HTTP status hoặc nguyên nhân mạng/máy chủ từ riêng ảnh này; không kết luận proxy hỏng.

### 4. Gecko báo lỗi khi đóng session

`TypeError: can't access property "WindowEventDispatcher", win is null` trong GeckoViewSessionStore vẫn xuất hiện khi đóng các trang. Không thấy AndroidRuntime fatal trong log đã thu; app và hàng đợi không crash.

### 5. Tổng kết hàng đợi thiếu cảnh báo thao tác

Home vẫn báo 3 xong/0 lỗi vì cả ba trả nurtureCompleted. Bình luận bỏ qua, lỗi tìm kiếm và phục hồi chưa được cộng thành cảnh báo chất lượng phiên. Kết quả tổng này không chứng minh luồng hết lỗi.

## Chưa được kiểm chứng trong lần này

- **Gửi bình luận Search sau bước reveal Post:** chưa có bình luận Search thành công hoặc log gọi reveal Post được ghi nhận. Video Search được chọn trong cấu hình 5 không phát sinh ca bình luận được quan sát; cấu hình 1 gặp lỗi Search và chuyển về Feed. Không dùng 1 bình luận Feed thành công để kết luận Search đã sửa xong.
- **Bảo vệ nháp khi editor biến mất:** không có mẫu `_pendingCommentDraft=true` trong lượt thực tế. Test Dart bao phủ ca này; vẫn cần tái hiện thiết bị riêng nếu muốn xác nhận thực tế.
- Chỉ một hàng đợi ngắn trên máy ảo, chưa chạy dài hạn hoặc điện thoại vật lý. Đồng hồ Android lệch chưa được chỉnh trong lượt này.

## Hướng sửa tiếp từ bằng chứng

Ưu tiên xử lý geometry Trợ năng sau cuộn: thu cây trước/sau Next, so khung host/scroll và node đang phát với ảnh, làm mới cache hoặc sửa chuyển đổi tọa độ theo nguồn dữ liệu xác minh được. Tiếp theo xử lý ô nhập/focus và nhận diện trang Search lỗi sớm; thử độc lập reveal Post trong Search. Bổ sung cảnh báo phiên và sửa thông báo “giữ nháp” khi chưa paste. Tăng delay đơn thuần không đủ cho geometry sai hoặc nút nằm ngoài viewport.

## Bằng chứng

- `2026-10-24-retest-delay-events.jsonl`: mẫu VM có giờ thu nhận +07:00.
- `2026-10-24-retest-delay-sessions.json`: số liệu cuối, không chứa thông tin đăng nhập.
- `2026-10-24-retest-delay-adb.log`: log mới của lượt này, đã loại dòng Remote Config và địa chỉ proxy.
- `2026-10-24-retest-feed-snapshot.json`, `2026-10-24-retest-account-4.png`: đối chiếu clock/nút bình luận ngoài khung với video đang hiện.
- `2026-10-24-retest-account-5.png`: Search/thả tim; `2026-10-24-retest-account-1.png`: Search lỗi; `2026-10-24-retest-focus-error.png`: sau lỗi focus.
- `2026-10-24-retest-delay-final.png`: kết thúc ở Home.
- Log test/analyze/build có tiền tố `2026-10-24-retest-delay-`.

Lượt này chỉ build/cài debug, chạy test và ghi báo cáo; không sửa mã ứng dụng, không chạy instrumentation hoặc phục hồi dữ liệu từ snapshot.
