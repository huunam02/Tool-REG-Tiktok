# Chính sách lỗi khi chạy nuôi lần lượt — 23/10/2026

Áp dụng theo yêu cầu mới: lỗi nghiêm trọng bỏ qua cấu hình; lỗi thao tác thông thường giữ nguyên thời hạn nuôi. Chính sách này thay thế đề xuất dừng cả phiên để giữ bản nháp trong báo cáo kiểm tra trước.

| Tình huống | Xử lý khi chạy lần lượt |
|---|---|
| CAPTCHA không giải được | Solver dùng tối đa 3 lần thử. Khi xử lý thất bại, dừng phiên lỗi và trả kết quả failed để chuyển cấu hình. |
| Proxy không kết nối, xác thực/tunnel lỗi; lỗi kết nối trang chính | Dừng thao tác, lưu phiên lỗi, chuyển cấu hình. |
| Dịch vụ tra IP chưa trả kết quả | Hiển thị cảnh báo; không tự kết luận proxy hỏng. |
| Mất tiến độ video, đọc snapshot lỗi, lỗi tìm kiếm, HTTP không thuộc lỗi kết nối | Chờ 5 giây rồi thử phục hồi; không hủy hoặc đặt lại hạn giờ. |
| Bình luận không gửi hoặc chưa xác nhận được | Không gửi lại; tiếp tục nuôi. Nếu có nháp, giữ ô nhập và tiếp tục xem video hiện tại đến hết giờ. |

Lỗi nghiêm trọng sử dụng thời gian thông báo có sẵn 15 giây trước khi trả kết quả cho Home; giữa hai cấu hình Home tiếp tục nghỉ 5–15 giây như trước. Với phiên đơn lẻ, CAPTCHA thất bại vẫn giữ trang để xử lý thủ công.

Controller chỉ theo dõi một Future lỗi cho mỗi lượt chạy runner, tránh xử lý một lỗi nhiều lần. Lỗi CAPTCHA từ dịch vụ/đọc dữ liệu cũng được thử lại trong giới hạn 3 lần; việc người dùng dừng, đổi trang hoặc chuyển nền vẫn hủy công việc cũ.

## Kiểm chứng tự động

- Bộ liên quan gồm runner, controller phục hồi, CAPTCHA, phiên đăng nhập và thời lượng: **113 test đạt** trong `2026-10-23-error-policy-tests.log`.
- Sau khi bổ sung hai trường hợp proxy warning/IP lookup, chạy lại toàn bộ file controller phục hồi: **12 test đạt**, log `2026-10-23-error-policy-proxy-tests.log`.
- Analyze 7 file mã/test thay đổi: **No issues found**, log `2026-10-23-error-policy-analyze.log`.
- Kiểm chứng giới hạn CAPTCHA bằng dịch vụ giả lập trả HTTP 503: đúng 3 yêu cầu, không kéo CAPTCHA, không phát sinh lần thử thứ tư.
- Kiểm chứng deadline giả lập 10 phút: lỗi playback/snapshot/HTTP/draft không kết thúc sớm; đúng hạn chỉ trả `nurtureCompleted` một lần. Lỗi proxy trả `failed` sau thời gian thông báo, không đợi đủ 10 phút.
- Kiểm chứng draft và gửi chưa xác nhận: không gửi trùng, không tăng số bình luận chưa xác nhận, vẫn tăng thời gian xem tới hết hạn.

## Kiểm chứng trên máy ảo qua ADB và Flutter VM

Thiết bị `emulator-5554`, Android 9/API 28. Hot reload bản sửa vào phiên debug hiện có; không cài lại hoặc đổi thông tin proxy đã lưu. Các giờ dưới đây là giờ Việt Nam. Hai tình huống lỗi HTTP/proxy được gọi có chủ đích vào controller qua Flutter VM trên ứng dụng đang hiển thị bằng ADB; đây không phải bằng chứng máy chủ trả HTTP 503 thật hoặc proxy thật bị hỏng.

- Bắt đầu hàng đợi 3 tài khoản, thứ tự ID 1 → 5 → 4.
- 20:59:57 (giờ thu nhận VM): gọi `showPageFailure(WebViewFailure.http(503))` trên ID 1. Deadline trước/sau đều `21:00:52.956595`; `enabled=true`, `failing=false`. Sau đó app thực hiện phục hồi.
- 21:00:04: app báo xử lý CAPTCHA thất bại và bắt đầu chuyển cấu hình. Đến 21:00:23, Home ghi nhận `failed=1`; 21:00:33 đã mở ID 5. Log thiết bị hiện có chưa ghi chi tiết số lượt solver cho sự kiện này; giới hạn đúng 3 được xác minh riêng bằng test.
- 21:00:59: gọi `showPageFailure(WebViewFailure.proxyAuth)` trên ID 5. Kết quả tức thời: `enabled=false`, `failing=true`, deadline bị hủy. 21:01:14 Home ghi nhận `failed=2`, trước hạn cũ `21:02:58.732900` của ID 5.
- 21:01:34: đã mở ID 4. Auto nuôi bắt đầu với deadline `21:04:32.454974`. Trong Search, app xem và chuyển video; khi bình luận có vấn đề, báo giữ nháp và tiếp tục xem, không kết thúc sớm.
- 21:04:27: ID 4 vẫn `enabled=true`, deadline gốc không thay đổi, ghi nhận 123 giây xem và 4 video. 21:04:37: đã trở về Home, `running=false`, `done=3`, `succeeded=1`, `failed=2`. Hai kết quả lỗi tương ứng với CAPTCHA thất bại và lỗi proxy được gọi có chủ đích; không dùng kết quả thử này để kết luận proxy thật bị hỏng.

Ảnh kết thúc: `2026-10-23-error-policy-final.png`. Ứng dụng đã dừng hàng đợi; không còn lượt kiểm tra đang chạy. Chưa tạo APK mới; bản sửa đã được hot reload vào phiên debug trên máy ảo.

Mẫu VM trong `2026-10-23-error-policy-events.jsonl`; `time` là thời điểm thu nhận UTC, cộng 7 giờ để đối chiếu giờ Việt Nam. Các dòng stdout cũ được DDS phát lại khi mở stream không được dùng làm timestamp sự kiện mới. Log ADB là bản trích ring buffer, không bảo đảm giữ toàn bộ đầu lượt.
