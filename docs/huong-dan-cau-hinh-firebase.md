# Các nội dung có thể thay đổi trên Firebase

Bạn có thể thay đổi các nội dung sau mà không cần cài lại ứng dụng:

- **otp_api_url – Địa chỉ lấy mã OTP:** Nhập đường dẫn dịch vụ lấy mã OTP được bàn giao. Dùng chung cho đăng ký và đăng nhập.
- **otp_api_certificate – Chứng chỉ của máy chủ OTP:** Chỉ dùng khi máy chủ OTP dùng chứng chỉ HTTPS tự ký. Dán nguyên nội dung chứng chỉ (từ `-----BEGIN CERTIFICATE-----` đến `-----END CERTIFICATE-----`). Ứng dụng chỉ tin chứng chỉ này cho đúng máy chủ trong `otp_api_url`. Khi đổi địa chỉ hoặc máy chủ cấp lại chứng chỉ, cập nhật trường này cùng lúc với `otp_api_url`. Để trống nếu máy chủ có chứng chỉ hợp lệ (ví dụ Let's Encrypt).
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

## Lấy chứng chỉ cho `otp_api_certificate`

Làm bước này khi đổi địa chỉ máy chủ OTP hoặc khi máy chủ cấp lại chứng chỉ tự ký. Nếu không cập nhật, ứng dụng sẽ báo "Không kết nối được API lấy OTP".

1. Mở Terminal (macOS/Linux) và chạy lệnh dưới đây. Thay `187.77.149.179:2001` bằng địa chỉ và cổng trong `otp_api_url`, bỏ phần `https://` và đường dẫn phía sau:

   ```bash
   echo | openssl s_client -connect 187.77.149.179:2001 2>/dev/null | openssl x509 -outform PEM
   ```

   Nếu máy chủ dùng tên miền, thêm `-servername` với đúng tên miền đó:

   ```bash
   echo | openssl s_client -connect otp.example.com:443 -servername otp.example.com 2>/dev/null | openssl x509 -outform PEM
   ```

2. Sao chép toàn bộ kết quả, gồm cả dòng `-----BEGIN CERTIFICATE-----` và `-----END CERTIFICATE-----`, rồi dán vào giá trị của `otp_api_certificate`.
3. Nếu đổi địa chỉ, sửa `otp_api_url` trong cùng lần xuất bản. Chứng chỉ chỉ được tin cho đúng máy chủ trong `otp_api_url`.
4. Xem ngày hết hạn để biết lần cập nhật tiếp theo:

   ```bash
   echo | openssl s_client -connect 187.77.149.179:2001 2>/dev/null | openssl x509 -noout -enddate
   ```

   Kết quả dạng `notAfter=Oct 27 01:31:41 2026 GMT`. Cần cập nhật chứng chỉ mới lên Firebase trước ngày này.

Nếu máy chủ đã có chứng chỉ hợp lệ (ví dụ Let's Encrypt), để trống `otp_api_certificate`.

Sau khi sửa, bấm **Publish changes** để xuất bản. Dừng phiên nuôi, chờ ít nhất 1 phút, đóng hoàn toàn ứng dụng rồi mở lại khi có Internet để áp dụng cho phiên mới.
