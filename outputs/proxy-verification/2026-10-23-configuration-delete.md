# Xóa hẳn dữ liệu cấu hình — 23/10/2026

## Thay đổi

- Nút Xóa xóa hẳn bản ghi cấu hình, kể cả cấu hình đang được chọn; không chuyển bản ghi đó sang `listed = 0` nữa.
- Khi xóa cấu hình đang chọn, trạng thái đăng nhập hiện tại trong database được đặt về false.
- Các phiên/lịch sử nuôi gắn với cấu hình bị xóa được dọn trong cùng transaction; log lỗi đăng ký được xóa qua foreign key cascade.
- Khi tài khoản không còn cấu hình nào khác trong danh sách, dọn các bản sao ẩn cùng tài khoản và toàn bộ lịch sử nuôi của tài khoản đó, kể cả lịch sử cũ không còn configuration ID.
- Cấu hình khác cùng email giữ dữ liệu của riêng nó. Tài khoản khác được giữ nguyên.
- Controller gửi yêu cầu dọn session riêng trước khi xóa database. Nếu lời gọi dọn session báo lỗi, cấu hình vẫn còn để thử lại. API native gửi yêu cầu dọn context của Gecko vẫn không cung cấp xác nhận hoàn tất việc xóa cookie thực tế.

## Xác minh

44 kiểm thử qua trong `configuration_deletion_test.dart`, `proxy_store_test.dart` và `nurture_store_test.dart`. Kiểm thử SQLite dùng `Directory.systemTemp.createTemp`; SharedPreferences và kênh native Gecko được giả lập. Có kiểm tra trực tiếp các hàng trong database sau khi đóng và mở lại, không chỉ kiểm tra danh sách hiển thị.

Các trường hợp kiểm tra gồm tài khoản đăng ký đang được chọn, bản sao ẩn sau sửa cấu hình, lịch sử cũ đã tách khỏi cấu hình, hai cấu hình cùng email, lỗi dọn storage, lặp yêu cầu xóa và log lỗi đăng ký liên quan.

Phân tích tĩnh 5 file Dart sạch. APK release ARM64 build thành công và kiểm tra chữ ký qua tại `build/app/outputs/flutter-apk/app-release.apk`.

Không cài bản sửa lên máy ảo, không dùng ADB và không đọc, sửa hoặc xóa database/cookie thật của người dùng trong lượt sửa này. Không có thao tác tự động dọn dữ liệu khi nâng cấp; bản sửa có tác dụng khi người dùng bấm Xóa cấu hình.
