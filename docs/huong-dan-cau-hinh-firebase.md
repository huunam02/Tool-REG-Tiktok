# Các nội dung có thể thay đổi trên Firebase

Bạn có thể thay đổi các nội dung sau mà không cần cài lại ứng dụng:

- **otp_api_url – Địa chỉ lấy mã OTP:** Nhập đường dẫn dịch vụ lấy mã OTP được bàn giao. Dùng chung cho đăng ký và đăng nhập.
- **otp_api_token – Mã truy cập dịch vụ OTP:** Nhập token được bàn giao để ứng dụng lấy mã OTP.
- **sadcaptcha_license_key – Key giải CAPTCHA:** Nhập key SadCaptcha để ứng dụng xử lý CAPTCHA khi đang nuôi tài khoản. Để trống nếu muốn tắt tính năng này.
- **search_keywords – Từ khóa tìm kiếm:** Danh sách các chủ đề ứng dụng có thể chọn để tìm video khi nuôi tài khoản, ví dụ du lịch, ẩm thực, cà phê.
- **auto_comments – Nội dung bình luận:** Danh sách các câu ứng dụng có thể chọn để bình luận khi nuôi tài khoản.

Trên Firebase Remote Config, giữ đúng tên trường và chọn kiểu **String** cho cả 5 trường.

Với hai danh sách, thay nội dung trong dấu nháy kép theo mẫu dưới đây và giữ nguyên các dấu còn lại.

Từ khóa tìm kiếm (`search_keywords`):

```text
["Du lịch","Ẩm thực","Cà phê"]
```

Nội dung bình luận (`auto_comments`):

```text
["Video hay quá!","Cảm ơn bạn đã chia sẻ!"]
```

Sao chép nguyên mẫu vào ô giá trị, không thêm dấu nháy bên ngoài hoặc dấu gạch chéo `\`. Muốn chỉ nuôi news feed, đặt `search_keywords` thành `[]`. Muốn nuôi mà không tự bình luận, đặt `auto_comments` thành `[]`.

Sau khi sửa, bấm **Publish changes** để xuất bản. Dừng phiên nuôi, chờ ít nhất 1 phút, đóng hoàn toàn ứng dụng rồi mở lại khi có Internet để áp dụng cho phiên mới.
