# Kiểm tra nuôi lần lượt qua ADB — 24/10/2026

Đã bấm **Chạy nuôi lần lượt các tài khoản** trên giao diện qua ADB và để chạy hết 3 tài khoản, thứ tự **1 → 5 → 4**. Mẫu VM lúc 09:48:00 xác nhận `autoRun=null`, `autoRunSucceeded=3`, `autoRunFailed=0`, không còn TikTokController đang hoạt động. Đã trở về Home/tab Nuôi; không thấy AndroidRuntime fatal trong log thu được. Giờ trong báo cáo là giờ Việt Nam.

Thiết bị `emulator-5554`, AVD Galaxy_S8_API_28, Android 9/API 28, ARM64, 1440×2960. Ứng dụng `com.brisklane.browser`. Gắn Flutter attach vào phiên debug đã mở; hot restart tại Home trước khi chạy để nạp chắc chắn mã mới. Đã đọc source đang nạp trong Dart VM và xác nhận `_commentDeadlineRatio = .5`. Không cài lại, không xóa dữ liệu, không sửa tỷ lệ hoặc thời lượng đã lưu. Không hot reload/restart hoặc thao tác thủ công trên trang trong khi hàng đợi đang chạy; chỉ đọc trạng thái VM/Trợ năng và chụp ảnh.

## Kết quả từng phiên

Số liệu đọc từ `nurture_sessions` sau khi kết thúc, không lấy tổng tích lũy trên thẻ tài khoản.

| Thứ tự | ID cấu hình | Chế độ | Bắt đầu–kết thúc | Xem (giây) | Video | Tim | Bình luận | Phase |
|---|---|---|---|---:|---:|---:|---:|---|
| 1 | 1 | search | 09:38:48–09:41:34 | 132 | 4 | 0 | 0 | completed |
| 2 | 5 | feed | 09:41:51–09:44:47 | 99 | 4 | 0 | 0 | completed |
| 3 | 4 | feed | 09:45:09–09:47:51 | 95 | 3 | 0 | 0 | completed |
| Tổng | | | | 326 | 11 | 0 | 0 | |

Cả ba cấu hình đặt thời lượng 2–3 phút, tim 30%, xem lâu 50%. Bình luận cấu hình 1 là 40%, cấu hình 5 và 4 là 20%. Thời gian tải, tìm kiếm, CAPTCHA, chờ Next và phục hồi không đồng nghĩa với thời gian xem. Các tỷ lệ là xác suất; số tim bằng 0 trong một lượt này chưa đủ kết luận riêng rằng chức năng thả tim hỏng.

## Vấn đề tái hiện

### 1. Gửi bình luận Search vẫn thất bại trước mốc 50%

- Cấu hình 1 tìm kiếm từ khóa `Painting`. CAPTCHA xuất hiện lúc 09:39:00; sau đó app mở được trình phát và tiếp tục xem/chuyển video.
- 09:40:17.927: đã chuyển sang video 27 giây. 09:40:25.104: báo `Không gửi được bình luận; đã dừng và giữ bản nháp. Tiếp tục xem, không gửi lại bình luận.` Mốc lỗi chỉ khoảng giây 7–8, trước nửa video 13,5 giây.
- Nhánh Search gọi `accessibility.submitComment()` trả false; lỗi này khác lỗi hết thời điểm gửi. Snapshot sau lỗi vẫn có editor dài 38 ký tự. Nút Post ở `(1497,2719)–(1538,2760)`, ngoài mép phải WebView `1348`.
- Native bridge chỉ thử `ACTION_IME_ENTER` từ API 30; máy API 28 dùng `ACTION_CLICK` trên Post. Bố cục bị cắt và cách dispatch là hướng điều tra trực tiếp; giá trị false hiện chưa cho biết có tìm thấy Post hay click bị từ chối.
- **Kết luận:** đổi 70% xuống 50% đã giúp dành thời gian sớm hơn nhưng không giải quyết lỗi gửi Search trên máy này. Chưa có bình luận thành công được xác nhận trong lượt chạy.
- **Ưu tiên sửa:** đưa Post vào vùng truy cập được trước khi paste; trả lý do có cấu trúc từ native; chỉ gửi một lần rồi kiểm tra kết quả, không tự gửi lại khi chưa rõ.

### 2. Sau lỗi gửi, có một lần Next trước khi nhận lại bản nháp

- Ảnh `2026-10-24-account-1.png` sau lỗi cho thấy bàn phím đã hiện lại. Trong các mẫu VM 09:40:30–09:41:05, `_commentsBlocked=true` nhưng `_draftReported=false`.
- 09:40:45.898: runner vẫn chạm Next. 09:40:47.631: cùng video; 09:41:07.449: timeout xác nhận chuyển sau 20 giây. 09:41:15.096 mới báo giữ bản nháp và tiếp tục xem đến hết hạn.
- Snapshot sau đó xác nhận vẫn còn nháp dài 38 ký tự; không có bằng chứng mất nháp hoặc gửi trùng trong lượt này. Navigation vẫn bằng 3, `_nurtureRestarts=0`, hạn vẫn 09:41:34.003737.
- **Ưu tiên sửa:** giữ trạng thái có thể còn nháp sau lỗi paste/submit, chặn Next ngay cả khi cây Trợ năng tạm không lộ editor; xử lý bàn phím mở lại trong nhánh khôi phục chính sách bàn phím.

### 3. Feed mất metadata sau Next, phải tải lại nhiều lần

- Cấu hình 5: 09:42:47.650 và 09:44:31.122 timeout đọc tiến độ sau Next; tổng hai lần phục hồi, hạn giữ nguyên 09:44:47.446840.
- Cấu hình 4: 09:45:54.748 và 09:47:30.467 timeout đọc tiến độ sau Next; tổng hai lần phục hồi, hạn giữ nguyên 09:47:51.950974.
- Sau Next, log nhiều lần thấy các clock `00:00 / 00:00`; runner chờ 20 giây rồi controller chờ phục hồi và tải lại Feed. Các đoạn chưa đọc được tiến độ không được cộng thêm thời gian xem.
- Phục hồi hoạt động và hàng đợi không treo, nhưng làm giảm thời gian xem hữu ích. Chưa xác định nguyên nhân gốc là metadata TikTok/Gecko hay cây Trợ năng sau cuộn; không đủ bằng chứng để quy lỗi hoàn toàn cho tọa độ.

### 4. Timeout mở khung bình luận Feed

09:43:30.468, cấu hình 5 báo timeout `mở khung bình luận`, bàn phím ẩn, ô nhập 0. App bỏ qua lúc 09:43:30.684 và tiếp tục xem, không kết thúc sớm. Không xác minh được gửi bình luận Feed trong lượt này. Có lưu ảnh và snapshot sau timeout để đối chiếu bounds nút bình luận; chưa đủ bằng chứng kết luận lỗi gốc của lần chạm mở.

### 5. Lỗi Gecko khi đóng trang và kết quả tổng thiếu cảnh báo

- Khi kết thúc các phiên có `TypeError: can't access property "WindowEventDispatcher", win is null` trong `GeckoViewSessionStore.sys.mjs:149`. Không có crash trong log đã thu; hàng đợi vẫn chuyển đủ tài khoản.
- Home báo 3 xong/0 lỗi vì cả ba phiên trả kết quả hoàn tất theo thời lượng. Bình luận thất bại, bỏ qua bình luận và phục hồi không được tổng hợp thành cảnh báo phiên. Nên lưu và hiển thị riêng các thông tin này để người dùng đánh giá chất lượng lượt nuôi.

## Bằng chứng và giới hạn

- `2026-10-24-sequential-events.jsonl`: mẫu VM mỗi khoảng 10–12 giây, có thời gian +07:00, deadline và bộ đếm runner. Bộ đếm runner về 0 khi tạo runner mới; bảng kết quả dùng tổng phiên trong SQLite.
- `2026-10-24-sequential-sessions.json`: số liệu cuối và thiết lập nuôi; không có mật khẩu/cookie.
- `2026-10-24-sequential-adb.log`: log mới thu từ trước khi bấm chạy, đã bỏ các dòng địa chỉ proxy/Remote Config.
- `2026-10-24-account-1.png`, `2026-10-24-search-after-submit-error.png` và `.json`: bằng chứng Search/nháp/Post bị cắt.
- `2026-10-24-account-5.png`, `2026-10-24-feed-after-comment-timeout.json`, `2026-10-24-account-4.png`: bằng chứng Feed đang chạy.
- `2026-10-24-sequential-final.png`: đã về Home; hàng đợi đã dừng.

Đây là một lượt chạy thật trên máy ảo, không tiêm lỗi giả, không thay cấu hình để ép bình luận. Chưa thử trên điện thoại thật hoặc chạy dài hạn; không coi 3 phiên `completed` là xác nhận toàn bộ luồng tương tác đã ổn định. Lượt này chỉ kiểm tra và ghi báo cáo, không sửa mã ứng dụng.
