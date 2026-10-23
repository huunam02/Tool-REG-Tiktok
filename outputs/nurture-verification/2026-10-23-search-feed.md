# Lỗi nuôi tìm kiếm chọn nhầm video feed — 23/10/2026

## Chẩn đoán chỉ đọc trên máy ảo

- Ứng dụng debug đang ở trang For You, Auto nuôi đã tắt; video vẫn phát, tiến độ Accessibility tăng từ `00:04 / 00:12` lên `00:07 / 00:12`.
- Không có ô bình luận hoặc bản nháp mở.
- Đọc lỗi Future cuối cùng của runner qua Dart VM Service: `StateError: Không tìm kiếm được "Fashion" (bước result); đã dừng nuôi.`
- Runner đã dừng, bộ đếm bình luận và thả tim bằng 0. Lỗi lần này nằm ở bước mở kết quả tìm kiếm.

## Nguyên nhân và bản sửa

Trang For You cũng có nút Accessibility `Watch in full screen`. Bộ chọn kết quả cũ ưu tiên nút này trước ô tìm kiếm, nên coi video feed là kết quả ngay cả khi chưa mở hoặc gửi tìm kiếm. Sau hai lần bấm không mở được trình phát kết quả, runner báo lỗi ở bước `result`.

- Mở ô tìm kiếm và gửi từ khóa trước khi cho phép chọn kết quả.
- Sau khi gửi, tiếp tục loại các thẻ feed có hàng nút `Read or add comments` trong lúc chờ điều hướng tải kết quả.
- Không cộng thời gian xem của feed phía sau ô tìm kiếm vào thống kê nuôi tìm kiếm.
- Giữ các kiểm tra tránh LIVE và không bấm xuyên qua dialog/player.

## Kiểm thử

Hai ca mới dùng Accessibility giả lập có video feed với nút fullscreen, gồm kết quả tải ngay và tải chậm 5 giây. Trên mã cũ, cả hai tái hiện bước `result` xuất hiện trước bước mở tìm kiếm và thời gian feed bị cộng nhầm. Sau sửa, cả hai chọn đúng thứ tự `open → paste → view-all → videos-tab → result → next`.

Toàn bộ 57 kiểm thử runner nuôi đều qua trong lượt chẩn đoán ban đầu, sử dụng dữ liệu giả.

Phân tích tĩnh hai file Dart liên quan sạch. APK release ARM64 chứa bản sửa tìm kiếm build thành công (217,6 MB), kiểm tra chữ ký qua, tại `build/app/outputs/flutter-apk/app-release.apk`.

## Chạy lại trên máy ảo theo yêu cầu

Đã build và cài đè APK debug ARM64, giữ dữ liệu. Lượt kiểm tra lúc 15:51 dùng từ khóa được chọn là `Travel in Vietnam`. Log xác nhận đúng thứ tự `open → paste → view-all → videos-tab`, không còn chọn fullscreen của feed trước khi mở tìm kiếm. Thời gian xem, lượt thả tim và bình luận trong mẫu quan sát đều bằng 0.

Lượt này bị chặn tiếp bởi lỗi đọc CAPTCHA lúc 15:51:59: thông báo cũ gộp “chưa sẵn sàng hoặc không phải dạng xoay được hỗ trợ”. Vì vậy chưa xác nhận được mở video kết quả hoặc hoàn tất một phiên nuôi. Người dùng xác nhận CAPTCHA tải chậm. Mã có khoảng chờ 5 giây cho giai đoạn đọc challenge, nhưng không có đủ bằng chứng để kết luận nguyên nhân tải chậm ở mạng, proxy hay phía trang. Khoảng chờ này không phải toàn bộ thời gian từ khi mở trang tới khi báo lỗi.

## Xử lý lỗi chờ CAPTCHA

- Khi kiểm tra CAPTCHA lỗi, tạm dừng tác vụ và giữ nguyên trang/phiên; hủy bộ hẹn giờ kết thúc nuôi, chuyển cấu hình và đăng xuất.
- Các bên cùng chờ kết quả kiểm tra nhận tín hiệu hủy, tránh runner tự tải lại feed do cùng lỗi.
- Hiện thông báo tạm dừng trên trang. Theo yêu cầu cuối, không có nút “Đã xác minh” hoặc hướng dẫn giải thủ công.
- Thông báo lỗi đọc chỉ nói chưa đọc được sau thời gian chờ, không suy đoán sai dạng CAPTCHA.
- Không thay thuật toán giải CAPTCHA, API, thao tác kéo hay tăng thời gian chờ để tự giải.

62 kiểm thử liên quan qua, gồm fixture hai bên đồng thời nhận lỗi sau thời gian chờ, giữ trạng thái đăng nhập, không điều hướng/tải lại và không tự trả về Home sau một giờ đồng hồ giả lập. Các kiểm thử này dùng mock, không tác động dữ liệu tài khoản thật. Chưa xác nhận CAPTCHA thật tải thành công với bản xử lý lỗi mới.

Phân tích tĩnh bốn file thay đổi liên quan sạch. Bản debug ARM64 cuối đã build thành công và cài đè lên `emulator-5554` bằng `adb install -r` (Success), giữ dữ liệu. Không chạy tiếp giải CAPTCHA trên tài khoản thật để xác nhận thành công.
