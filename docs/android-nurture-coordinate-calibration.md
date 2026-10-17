# Tọa độ nuôi tài khoản Android

Luồng tự động xem, chuyển video và bình luận dùng `flutter_accessibility_service`,
cùng WebView thật 400×800 và `flutter_screenutil` với đăng ký/đăng nhập.
Không đọc DOM hay gọi JavaScript để thao tác hoặc lấy tiến độ nuôi trên Android.

Profile: [`assets/nurture-coordinate-profile.json`](../assets/nurture-coordinate-profile.json).
App nạp asset và `SharedPreferences` khóa `nurture_coordinate_profile_v1`.
Tọa độ mới được lưu trước lần chạm đầu; tọa độ đã có phải còn nằm trong đúng control.

## Video dọc và ngang

Phân loại bằng tỷ lệ khung phát lấy từ cây Accessibility, không theo hướng
màn hình điện thoại. Khóa `portrait/…` và `landscape/…` tách riêng. Mỗi kích thước
và vị trí khung có thêm khóa geometry vì video 4:5, 9:16, 16:9 cũng có thể đặt
nút ở các hàng khác nhau. Các lần chạy sau dùng lại điểm của đúng bố cục đó.

Đã đo trên Pixel 9, 1080×2424, density 420 ngày 17/10/2026:

| Control | Video dọc | Video ngang |
| --- | --- | --- |
| Mở bình luận (mẫu đã quan sát) | 363.82, 564.57 | 363.82, 387.25 |
| Ô bình luận | 315.28, 783.13 | 315.28, 783.13 |
| Post | 386.50, 783.51 | 386.50, 783.51 |
| Đóng bình luận | 387.44, 12.37 | 387.44, 12.37 |
| Chuyển video | 386.50, 409.56 | 386.50, 409.56 |

Hai bảng bình luận hiện có cùng geometry nhưng vẫn lưu riêng theo dạng video.
Mỗi control trong panel còn có khóa theo bounds để giữ riêng các biến thể hàng
nhập, chẳng hạn vị trí 783 px và 793 px; không ghi đè điểm của mẫu cũ.
Post được ghi geometry khi nút chưa bật; chạy thật chỉ chạm khi nút bật.
Đã mở/đóng bình luận và chuyển video thật bằng Accessibility ở cả hai dạng.
Đã xác minh trên TikTok thật rằng ô bình luận vẫn focus và đồng hồ phát vẫn đọc
được khi IME được ẩn tạm; profile có 17 điểm cho các biến thể đã quan sát.
Chưa kiểm chứng đăng bình luận công khai hoặc chạy đủ phiên 10 phút trên TikTok thật.

## Theo dõi và hủy

Tiến độ lấy từ nhãn thời gian `mm:ss / mm:ss`, độ phân giải một giây.
Không cộng thời gian đứng tải, ra nền hoặc nhảy seek. Mỗi bài giữ lựa chọn
50% xem hết, 50% lướt sớm sau 2–5 giây tiến độ quan sát được. Với clip cực ngắn,
độ phân giải một giây có thể không quan sát đủ để chuyển trước cuối clip.
Chỉ bài có kế hoạch xem hết mới bình luận; bài quá ngắn bỏ bình luận.
Chọn mốc từ 5 giây đến trước 70%, chừa thời gian nhập và kiểm tra lại trước Post.

Nút chuyển video được ưu tiên khi nhận diện được đúng cặp điều hướng lên/xuống.
Bố cục không có cặp nút này dùng gesture vuốt trong khung video, lưu cả hai đầu
trước thao tác. Một lần chuyển phải thấy bài đổi; không tự lặp gesture nếu thất bại.

Bình luận chỉ lấy từ cấu hình, tránh lặp liên tiếp cùng mẫu. Trước khi focus
ô cuối màn hình, Accessibility tạm ẩn bàn phím nhưng giữ focus, tránh IME che
ô nhập trong viewport cố định. Chính sách bàn phím được khôi phục ở `finally`,
khi hủy hoặc khi lease 10 giây hết hạn. Bản nháp có sẵn
được giữ nguyên. Chỉ tính đã gửi khi ô nhập trống và thấy thêm đúng nội dung
bình luận trong cây Accessibility. Post chỉ gửi một lần; kết quả không rõ,
đổi video, mất tiến độ hoặc quá mốc 70% đều dừng, không gửi lại.
Nội dung chứa email/mã sáu số có thể bị bộ che dữ liệu làm mất khả năng xác nhận;
trường hợp này cũng dừng và không gửi lại.

Giới hạn phiên vẫn là 10 phút, giữ hạn qua nền/tải lại, kết thúc về Home và giữ
cookie. Không nhận diện được một video duy nhất hoặc không có đồng hồ phát
(bài ảnh, quảng cáo/bố cục khác chưa hỗ trợ) thì dừng sau 20 giây để kiểm tra.

## Ghi thêm mẫu

Mở bản debug bằng entry `tools/login_calibration_main.dart`, chọn video cần đo:

```sh
python3 tools/nurture_calibrate.py record
python3 tools/nurture_calibrate.py open
python3 tools/nurture_calibrate.py record
python3 tools/nurture_calibrate.py export
```

`open` và `next` chỉ phát một cú chạm đã ghi, không gửi bình luận.
Đóng bảng bình luận trên thiết bị trước khi dùng `next`. Snapshot có che giá trị
ô nhập lưu tại `outputs/nurture-calibration/`. Không chép tài khoản/mật khẩu vào profile.
