# Chuyển video và bỏ đăng xuất tự động — 23/10/2026

## Bằng chứng chạy thật

Máy ảo `emulator-5554`, Android 9/API 28, ARM64; ứng dụng debug `com.brisklane.browser`. Các thời điểm dưới đây theo giờ Việt Nam.

- 16:26:50: runner chạm Next trên video ngang 9 giây. Điểm chạm (1290,7; 1573,3) nằm trong control `[1272,1554,1312,1594]`. Sau khoảng 0,6 giây đã nhận diện bài khác có thời lượng 16 giây.
- 16:27:06: Next trên video dọc 16 giây cũng đổi bài sau khoảng 0,6 giây; bài mới ban đầu có thời lượng 12 giây.
- 16:27:53: runner dừng do không còn đọc được tiến độ.
- Snapshot và ảnh chụp sau đó cho thấy chính vùng video hiện thông báo **We're having trouble playing this video. Please refresh and try again.** Đồng hồ phát của bài hiện tại không còn trong cây Trợ năng. Nút Next đã hoạt động trong hai lần được ghi nhận.

Ảnh bằng chứng: [TikTok không phát được video](2026-10-23-playback-failed.png).

Thông báo cũ `Chưa chuyển được video; đã dừng để kiểm tra tọa độ.` được phát khi không nhận diện được bài khác kèm đồng hồ hợp lệ trong 20 giây. Vì vậy nó gộp lỗi thao tác chuyển và lỗi phát/tải bài tiếp theo. Lượt tìm kiếm 16:09 trước đó không có đủ snapshot tại thời điểm lỗi để khẳng định cũng cùng nguyên nhân. Lượt tái kiểm tra này xác nhận lỗi phát video, không chứng minh proxy hay mạng cụ thể là nguyên nhân phía dưới.

## Thay đổi

- Nhận diện thông báo lỗi phát TikTok trong vùng media hiện tại và báo đúng `TikTok không phát được video này; đã dừng nuôi. Hãy tải lại trang hoặc kiểm tra kết nối.`
- Không nhận diện nhầm câu này nếu nằm trong bình luận hoặc metadata ẩn.
- Tách thông báo hết 20 giây: không đọc được tiến độ sau thao tác chuyển, hoặc chưa xác nhận video mới. Không còn kết luận sai rằng cần sửa tọa độ.
- Thêm log điểm chạm Next, trạng thái đổi bài và các đồng hồ phát để chẩn đoán lần sau. Không thêm thao tác bấm lặp hoặc thay đổi khoảng chờ 20 giây.
- Theo yêu cầu mới: xóa luồng đăng xuất tự động, timer giữ màn 1–2 phút, countdown, tùy chọn `logoutAfterNurture`, kết quả route đăng xuất, script và debug hook đăng xuất. Hoàn tất đăng ký/nuôi tiếp tục giữ phiên đăng nhập và trả về Home/chuyển cấu hình theo luồng đang có.
- Cập nhật hướng dẫn sử dụng. Khoảng chờ đọc CAPTCHA vẫn là **15 giây**.

## Kiểm tra

- 64 kiểm thử qua: runner nuôi, tạm dừng xác minh, thời lượng cấu hình và giữ phiên.
- Hai ca giữ phiên kiểm tra lượt đơn và hàng đợi: hết thời gian trả `nurtureCompleted` đúng một lần; sau một giờ giả lập vẫn đăng nhập, không gọi luồng đăng xuất hoặc điều hướng lại.
- Ca lỗi phát video tái hiện thông báo TikTok sau một lần chuyển; runner báo lỗi phát, không bấm lại và không cộng lượt xem chưa xác nhận.
- Các ca tải bài chậm và thao tác chuyển không đổi bài xác nhận hai thông báo khác nhau.
- Phân tích tĩnh các file Dart thay đổi liên quan sạch; `git diff --check` qua.
- APK debug ARM64 build và cài đè thành công, giữ dữ liệu. Không xác nhận một phiên nuôi thực tế hoàn tất ở lượt trên vì TikTok gặp lỗi phát video.

Bốn lỗi kiểm thử Home/cấu hình đã ghi trong báo cáo trước không thuộc thay đổi này và chưa được xử lý.
