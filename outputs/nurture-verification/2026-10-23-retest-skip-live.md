# Chạy lại luồng nuôi và bỏ qua LIVE — 23/10/2026

## Lượt kiểm tra thực tế trước khi bổ sung bỏ qua phòng LIVE

Thiết bị `emulator-5554`, Android 9/API 28, ARM64. Giờ Việt Nam.

- Chạy tài khoản được chọn trong tab Nuôi; không chạy cả danh sách.
- 16:33:19–16:33:46: tìm kiếm Coffee theo thứ tự `open → paste → view-all → videos-tab → result`. Có CAPTCHA xuất hiện và được đóng trước khi mở video kết quả.
- Bốn lần Next đã nhận diện video khác: 16:34:08, 16:34:24, 16:34:57 và 16:35:08. Lần đầu đồng hồ trống ngắn rồi xuất hiện lại, runner tiếp tục bình thường.
- Hai lần thả tim được xác nhận; không có bình luận được gửi trong mẫu quan sát.
- 16:35:21: controller có `_flowFinished=true`, `_isClosed=true`, `autoWatchEnabled=false`, `loginConfirmed=true`; không có lỗi nuôi trong log của lượt này.
- Mẫu cuối trước khi đóng ghi nhận 80 giây xem, 4 video xem hết, 2 thả tim, 0 bình luận. Đây là mẫu lấy mỗi 3 giây, chưa bao gồm tối đa vài giây trước khi đóng.
- Thống kê Home đọc sau đó qua VM: tài khoản cấu hình 8 có 7 lần nuôi, 11 video, 3 thả tim, 0 bình luận, trạng thái `completed`. So với giao diện trước lượt thử: tăng 1 lần nuôi, 4 video và 2 thả tim. Phiên đăng nhập vẫn được giữ.

Metadata quan sát: [retest-events.json](2026-10-23-retest-events.json). Log đã lọc: `2026-10-23-retest.log`.

## Trường hợp LIVE người dùng báo tiếp theo

Sau lượt trên, quan sát một phiên khác tìm Home decor đã mở phòng livestream. Đến 16:37:34 runner cũ báo không mở được video tìm kiếm vì phòng LIVE không có đồng hồ của video thường.

Snapshot thật cho thấy tiêu đề WebView dạng `… is LIVE - TikTok LIVE`, thanh điều hướng LIVE, nút `Back` và `Go to TikTok For You feed`. Nút Back của giao diện này mở thanh điều hướng, không thoát phòng. Đã thử nút For You bằng Trợ năng và xác nhận trở lại feed.

## Bản sửa bỏ qua LIVE

- Giữ bỏ qua preview LIVE trong feed bằng nút Next.
- Nhận diện phòng LIVE riêng bằng tiêu đề WebView, không nhầm với nút LIVE trên sidebar của feed thường.
- Không đọc metadata video thường còn sót dưới phòng LIVE, không cộng thời gian xem LIVE.
- Nếu tìm kiếm hoặc Next mở sang phòng LIVE, chạm đúng nút For You và tiếp tục video thường. Không tương tác với bình luận, Follow hay quà tặng trong phòng LIVE.
- Lọc cả nhãn LIVE là node cạnh thẻ tìm kiếm nhưng có vị trí nằm trong thumbnail. Đây là ca hồi quy bổ sung; chưa có snapshot grid trước khi mở phòng để khẳng định đó là nguyên nhân của lần mở LIVE thật.
- Chỉ gửi một thao tác thoát; nếu không rời được phòng trong 10 giây thì dừng với thông báo rõ ràng.

## Xác minh và giới hạn

- 65 kiểm thử runner qua, gồm fixture phòng LIVE lấy từ thiết bị và đã thay tên tài khoản bằng dữ liệu giả. Các ca mới kiểm tra LIVE khi bắt đầu ở feed, trong tìm kiếm, sau Next, thoát không thành công và nhãn LIVE nằm cạnh thumbnail.
- 5 kiểm thử controller giữ phiên, thời lượng nuôi và tạm dừng xác minh qua. Tổng 70 ca liên quan đều qua.
- Phân tích tĩnh hai file thay đổi sạch; `git diff --check` qua.
- Build debug ARM64 và cài đè lên máy ảo thành công, giữ dữ liệu.
- Thao tác For You trên LIVE thật đã được xác minh trước khi cài. Chưa xác nhận đủ một phiên nuôi thực tế mới với toàn bộ bản sửa LIVE sau khi cài.
- Giữ thời gian chờ đọc CAPTCHA 15 giây và giữ thay đổi bỏ đăng xuất tự động.
