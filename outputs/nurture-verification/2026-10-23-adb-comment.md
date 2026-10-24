# Kiểm tra lỗi bình luận bằng ADB — 23/10/2026

Thiết bị kết nối: `emulator-5554`, AVD Galaxy_S8_API_28, Android 9/API 28, ARM64. Không có điện thoại vật lý trong danh sách ADB. Giờ dưới đây là giờ Việt Nam.

Đã hot reload bản sửa vào phiên Flutter debug đang chạy, không cài lại hay xóa dữ liệu app. Phiên thử dùng tài khoản đang chọn (cấu hình 1), proxy và cookie hiện có. Chỉ thay cấu hình trong bộ nhớ của màn hình thử: tỷ lệ tim/bình luận/xem lâu bằng 0, danh sách bình luận và từ khóa tìm kiếm trống. Không lưu các thiết lập thử này vào cấu hình tài khoản.

## Đã xác minh

- 19:32:21: gọi bước bình luận của runner với cú chạm mở được cố ý đặt vào vùng trống. Snapshot và cử chỉ đều dùng Trợ năng trên thiết bị thật đang kết nối. Sau 8.700 ms, runner phát thông báo “Bình luận chưa sẵn sàng ở bước mở khung bình luận (bàn phím ẩn, ô nhập 0). Bỏ qua bình luận này và tiếp tục nuôi.” Phương thức hoàn tất bình thường, cùng video, số bình luận gửi bằng 0, ô nhập còn lại có độ dài 0. Điều này xác minh nhánh xử lý timeout; không xác minh chuỗi gửi bình luận.
- 19:35:20: kiểm tra trên khung bình luận đã mở. Chạm ô nhập theo bounds Trợ năng, xác nhận `focused=true`, `length=0`, `keyboardVisible=false`, cùng video. Sau đó đóng khung trống và khôi phục chính sách bàn phím. Không nhập nội dung hoặc nhấn Post.
- Khi kết thúc: Auto nuôi đã tắt, trạng thái đăng nhập vẫn được xác nhận, đã trở về Home/tab Nuôi. Không có tim hay bình luận nào được gửi trong phiên thử.

## Vấn đề còn quan sát được

Sau khi feed chuyển qua nhiều video, tọa độ Trợ năng có lúc lệch so với ảnh màn hình. Ví dụ nút bình luận được báo ở y=2608–2708 pixel trong khi biểu tượng hiển thị ở khoảng y=1450–1550 pixel. Một lần chạm theo bounds không mở được ô nhập trong 10 giây; snapshot chỉ còn ô Search trống. Chưa xác định lỗi thuộc bộ nhớ đệm Trợ năng, phép chuyển đổi tọa độ của Gecko hay trạng thái cuộn của trang.

Lượt xem riêng sau khi đã đóng khung bình luận giữ Auto nuôi bật qua bốn mẫu ở khoảng 4,5 / 8,6 / 12,8 / 16,9 giây. Sau thao tác Next, cả bốn mẫu đều không đọc được `NurtureVideo`; tổng xem/video không tăng trong mẫu này. Đã chủ động dừng lượt thử. Vì vậy chưa xác nhận được toàn bộ luồng nuôi hoạt động ổn định sau nhiều lần Next.

Một lượt xem trước đó có thao tác kiểm tra bình luận xen vào khi runner đang chạy, nên không dùng lỗi Next của lượt đó để kết luận về hành vi độc lập của runner.

## Phạm vi kết luận

Bản sửa đã xử lý đúng trường hợp dừng sai khi khung bình luận không mở và chưa nhập nội dung. Ô nhập có thể nhận focus với bàn phím ẩn khi khung đã mở. Chưa xác minh gửi bình luận và chưa sửa vấn đề tọa độ/metadata sau chuyển video; không coi lần kiểm tra này là xác nhận toàn bộ luồng đã hết lỗi.
