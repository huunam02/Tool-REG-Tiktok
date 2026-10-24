# Kiểm tra chạy nuôi lần lượt bằng ADB — 23/10/2026

Đã bấm nút **Chạy nuôi lần lượt các tài khoản** qua ADB và để hàng đợi chạy đủ 3 tài khoản. Thời gian phiên theo SQLite: 20:34:49–20:43:17, giờ Việt Nam. Mẫu cuối từ Flutter VM lúc 20:43:21 xác nhận `running=false`, `done=3`, `succeeded=3`, `failed=0`. Đã trở về Home/tab Nuôi.

Thiết bị: `emulator-5554`, Android 9/API 28, ARM64, màn hình 1440×2960. Không có điện thoại vật lý trong danh sách ADB. Giữ cấu hình nuôi, proxy, phiên đăng nhập và các tỷ lệ tương tác hiện có. Lượt chạy thực sự đã gửi tim và bình luận. Không thay đổi mã ứng dụng, không hot reload, không cài lại hoặc xóa dữ liệu trong lượt kiểm tra này. Các thay đổi mã có sẵn trước lượt kiểm tra vẫn được giữ nguyên.

## Số liệu phiên vừa chạy

Số liệu đọc trực tiếp từ `nurture_sessions`, không lấy tổng tích lũy trên thẻ tài khoản.

| Thứ tự | ID cấu hình | Chế độ ban đầu | Bắt đầu–kết thúc | Thời gian xem ghi nhận | Video | Tim | Bình luận | Phase lưu |
|---|---:|---|---|---:|---:|---:|---:|---|
| 1 | 4 | Feed | 20:34:49–20:37:19 | 114 giây | 3 | 1 | 0 | completed |
| 2 | 1 | Feed | 20:37:39–20:40:31 | 156 giây | 2 | 1 | 1 | completed |
| 3 | 5 | Search, sau lỗi trở về Feed | 20:40:59–20:43:17 | 72 giây | 5 | 1 | 0 | completed |
| Tổng | | | | **342 giây** | **10** | **3** | **1** | |

Thời gian tìm kiếm, chờ CAPTCHA, tải trang và mất tiến độ không đồng nghĩa với thời gian xem video. Số video là số runner đã ghi nhận hoàn tất/bỏ qua, không phải số bài từng xuất hiện trên màn hình. Một lượt ngắn trên máy ảo chưa đủ xác nhận độ ổn định dài hạn hay khả năng chạy trên điện thoại thật.

## Các lỗi và phương án sửa

### 1. Ưu tiên cao: lỗi giữ bản nháp bị xử lý thành tải lại trang

- **Đã tái hiện:** 20:42:32.592, cấu hình 5 ở trình phát Search báo `Không gửi được bình luận; đã dừng và giữ bản nháp.` Thông báo lặp lại ngay 1 ms sau đó.
- Mẫu VM kế tiếp cho thấy `navigation` từ 2 lên 4 và `restarts=2`; sau đó runner mới có số liệu từ 0, chạy Feed và tiếp tục xem/thả tim. Phiên cuối vẫn là `completed`.
- **Nguyên nhân trong mã:** `tiktok_controller.dart:984` xử lý mọi lỗi không phải `NurturePlaybackUnavailable` bằng tải lại khi còn thời gian. Nó không phân biệt lỗi có bản nháp hoặc trạng thái gửi chưa chắc chắn. Nhánh bảo vệ editor chỉ nằm trong `_recoverNurturePlayback`, nên không áp dụng cho lỗi gửi bình luận.
- **Tác động:** hành vi trái với thông báo giữ bản nháp; nguy cơ mất nội dung khi reload. Không chụp được editor có nội dung ngay trước reload, nên chưa khẳng định trực tiếp rằng nội dung nháp đã mất hoặc TikTok đã nhận bài gửi hay chưa. Bộ đếm phiên Search không xác nhận được bình luận thành công.
- **Sửa đề xuất:** dùng loại lỗi riêng cho bản nháp/trạng thái gửi không chắc chắn; chặn tự reload và tự chuyển tài khoản ở trường hợp này. Giữ màn hình để xử lý, hoặc lưu nháp được xác nhận trước khi rời trang. Không tự gửi lại khi chưa biết lần gửi trước có được nhận không. Chỉ tự phục hồi lỗi tải/phát video khi snapshot xác nhận không có nháp.
- **Nghiệm thu:** test automatic mode có draft và lỗi submit; không gọi `loadUrl`, giữ editor, không báo gửi thành công; kiểm tra lại bằng ADB.

### 2. Ưu tiên cao: cùng lỗi bị xử lý nhiều lần

- **Đã tái hiện:** cấu hình 4 có log phục hồi `attempt 1/2` lúc 20:35:46.509 và `attempt 2/2` lúc 20:35:46.677. Cấu hình 5 có hai thông báo lỗi submit cách nhau 1 ms và hai lần navigation.
- **Nguyên nhân phù hợp với mã:** `_startAutoWatch` gắn `runner.start().catchError(...)` mỗi lần được gọi (`tiktok_controller.dart:965`). `NurtureAccessibilityRunner.start()` trả cùng `_done` khi đang chạy (`nurture_accessibility_runner.dart:547`). Nhiều caller vì vậy có thể gắn nhiều handler lên cùng Future lỗi. `handlePageLoadComplete` còn gọi `startAutoWatch` sau `runInitialAction`, trong khi initial action có thể đã bật runner.
- **Sửa đề xuất:** mỗi lần thực thi runner chỉ có một Future được controller theo dõi và một handler lỗi; khóa quá trình phục hồi trước điểm `await`; kiểm tra lại runner/navigation sau snapshot. Làm mới phần theo dõi khi runner thật sự dừng rồi được chạy lại sau resume, không chỉ dựa vào identity đối tượng.
- **Nghiệm thu:** gọi start đồng thời và gọi lặp từ load/lifecycle; một lỗi chỉ tăng một lần bộ đếm và chỉ reload một lần. Một lần lỗi không được dùng hết hai lượt phục hồi.

### 3. Ưu tiên cao: nhánh hết phục hồi mất tiến độ có thể giữ hàng đợi chờ watchdog

- **Phát hiện qua đọc mã, chưa xảy ra trong lượt 3 tài khoản này:** sau khi `_recoverNurturePlayback` trả false, `NurturePlaybackUnavailable` không vào nhánh `autoAdvance` ở dòng 984; thay vào đó hủy timer/deadline và tắt Auto nuôi ở dòng 997–999, nhưng không trả `TikTokFlowResult`.
- **Sửa đề xuất:** định nghĩa kết quả kết thúc khi không thể phục hồi; dừng/lưu thống kê và trả lỗi cho Home đúng một lần khi không có nháp cần giữ. Với nháp, dùng trạng thái cần xử lý riêng theo mục 1. Không để queue phụ thuộc watchdog.
- **Nghiệm thu:** automatic mode, lỗi liên tiếp vượt giới hạn và lỗi trong 30 giây cuối; Home nhận kết quả trong thời gian ngắn, thống kê không bị đánh dấu hoàn tất thành công sai.

### 4. Ưu tiên trung bình: submit bình luận trong Search thất bại trên API 28

- **Đã tái hiện:** lỗi ở mục 1 xuất phát từ `accessibility.submitComment()` trả false (`nurture_accessibility_runner.dart:1577`).
- Snapshot trước đó có editor Search ở bounds `(893,2725)-(1365,2754)`, vượt mép WebView phải `1348`; ảnh màn hình cho thấy panel Search bị cắt ngang ở mép phải.
- Native bridge `SignupAccessibilityBridge.java:654` tìm Post quanh editor; chỉ thử `ACTION_IME_ENTER` khi SDK >=30, sau đó dùng `ACTION_CLICK`. Thiết bị đang thử là SDK 28. Chưa có mã lý do chi tiết để phân biệt không tìm thấy Post với click bị từ chối; chưa kết luận chính xác nguyên nhân native.
- **Sửa đề xuất:** trả kết quả có cấu trúc: editor/Post có tìm thấy không, enabled/bounds, hành động nào được gọi, kết quả dispatch. Điều chỉnh bố cục hoặc cuộn panel để nút Post truy cập được trên API 28; chỉ submit một lần rồi xác minh nội dung và editor rỗng. Nếu chưa có đích gửi đáng tin cậy, bỏ qua trước bước paste. Kết hợp bảo vệ nháp ở mục 1.
- **Nghiệm thu:** gửi trong Search trên API 28, nút Post bị cắt, mất focus, video ngắn và lỗi dispatch; không mất nháp hoặc gửi trùng.

### 5. Ưu tiên trung bình: mất metadata sau Next, timeout mở bình luận

- Cấu hình 4 phải tải lại Feed sau Next; clock chuyển thành `00:00 / 00:00`. Phục hồi sau đó có hiệu quả và phiên kết thúc.
- Cấu hình 1 lúc 20:40:15.413 timeout mở khung bình luận (`bàn phím ẩn, ô nhập 0`). App bỏ qua, tiếp tục tăng thời gian xem và kết thúc đúng hạn. Không phải mọi `unreadable` tạm thời đều là lỗi: nhiều Next sau đó đọc được video mới bình thường.
- **Sửa đề xuất:** ghi snapshot trước/sau chuyển bài và mở bình luận; đối chiếu card đang hiển thị, tọa độ sau scroll và cây Trợ năng mới; chỉ tăng timeout khi có bằng chứng đang tải. Giữ cơ chế bỏ qua bình luận trước paste và phục hồi có giới hạn. Chưa xác định chắc lỗi gốc thuộc TikTok, Gecko hay phép đọc snapshot.
- **Nghiệm thu:** ADB chạy liên tục nhiều video dọc/ngang/Search/LIVE; không tăng video hoặc thời gian xem khi chưa xác nhận metadata và playback.

### 6. Báo cáo cuối thiếu thông tin lỗi đã phục hồi

- Home báo `Đã tự nuôi 3 cấu hình: 3 xong, 0 lỗi.` dù cấu hình 5 có lỗi gửi bình luận và reload. Đây là số kết quả cấp cấu hình, không phải tổng lỗi thao tác; hiện UI không cho người dùng thấy sự khác biệt này.
- **Sửa đề xuất:** lưu lý do lỗi, số lần phục hồi, bình luận bỏ qua và kết quả gửi chưa xác nhận cho từng phiên. Có trạng thái hoàn tất kèm cảnh báo; lỗi có nháp không được âm thầm biến thành hoàn tất sạch. Trình bày ngắn gọn trên Home và cho xem chi tiết.

### 7. Lỗi Gecko lúc đóng session

- Có `TypeError: can't access property "WindowEventDispatcher", win is null` trong `GeckoViewSessionStore.sys.mjs` khi quay về Home. Không thấy AndroidRuntime fatal trong log đã quan sát; hàng đợi vẫn chuyển tài khoản và kết thúc.
- **Sửa đề xuất:** kiểm tra thứ tự đóng GeckoSession/listener và callback muộn. Chỉ đổi phiên bản Gecko khi đã có ca tái hiện độc lập; chưa đủ bằng chứng lỗi này làm mất cookie hoặc gây crash.

## Kiểm thử mã

- `nurture_accessibility_runner_test.dart` + `tiktok_nurture_recovery_test.dart`: **78 test đạt**. Kết quả trong `2026-10-23-sequential-tests.log`. Các test hiện có chưa bao phủ đủ lỗi gắn nhiều handler và lỗi draft trong automatic mode.
- Khi chạy thêm `home_nurture_test.dart`: **80 đạt, 1 thất bại**. Test thất bại: `Home uses remote lists for signup and login and ignores saved lists`, mong 2 cấu hình nhưng nhận 0.
- Chẩn đoán trên bản sao tạm: Home còn `busy=true`, `account=null` do bước đọc session dùng SharedPreferences chưa được mock. Thêm `SharedPreferences.setMockInitialValues({})` vào setup của bản sao giúp chính test đó đạt. Chưa áp dụng thay đổi này vào test gốc. Log trước/sau: `2026-10-23-home-diagnostic.log`, `2026-10-23-home-diagnostic-with-prefs.log`.
- Analyze `home_controller.dart`, `tiktok_controller.dart`, `nurture_accessibility_runner.dart`: **No issues found**. Kết quả trong `2026-10-23-sequential-analyze.log`.

## Bằng chứng và giới hạn

- `2026-10-23-sequential-events.jsonl`: mẫu VM/hàng đợi và stdout; trường `time` là thời gian máy thu nhận, UTC. Khi mở stream, DDS phát lại một số log cũ, nên các dòng `kind=log` đầu mỗi lần kết nối không được dùng như thời điểm sự kiện chính xác. Dùng timestamp ADB cho các mốc lỗi ghi trên.
- `2026-10-23-sequential-adb.log`: phần log ADB còn trong ring buffer lúc trích xuất, chủ yếu từ 20:41:42; không phải toàn bộ log từ đầu lượt. Mốc ADB sớm hơn trong báo cáo được quan sát trực tiếp trong phiên logcat trực tiếp của lần kiểm tra.
- `2026-10-23-sequential-sessions.txt`: truy vấn SQLite sau khi kết thúc, chỉ các cột thống kê phiên, không gồm mật khẩu/cookie.
- `2026-10-23-sequential-account-1.png`, `2026-10-23-sequential-account-5.png`: ảnh ADB lúc đang chạy; `2026-10-23-sequential-final.png`: đã về Home.

Thứ tự triển khai đề xuất: **bảo vệ nháp → một handler/phục hồi cho mỗi lượt runner → trả kết quả khi phục hồi thất bại → submit Search API 28 → lưu cảnh báo phiên → cải thiện metadata/tọa độ → kiểm tra đóng Gecko**. Sau sửa, bổ sung các ca hồi quy nêu trên và chạy lại toàn bộ hàng đợi qua ADB.
