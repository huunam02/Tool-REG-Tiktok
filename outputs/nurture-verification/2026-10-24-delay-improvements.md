# Cải thiện chờ thao tác nuôi — 24/10/2026

Đã cập nhật mã và cài APK debug mới vào máy ảo bằng `adb install -r` sau khi phục hồi dữ liệu.

- Sau Next chờ 1,2 giây; xác nhận video mới qua nhiều snapshot ổn định ít nhất 800 ms và clock thay đổi. Chờ tải tối đa 30 giây thay cho 20 giây. Không tự bấm Next lần nữa khi chưa xác nhận chuyển.
- Kiểm tra lại vị trí Next và nút mở bình luận trước dispatch. Giữ nguyên hạn thời gian nuôi, kể cả khi cần phục hồi.
- Giữ trạng thái có thể còn nháp sau paste hoặc gửi chưa xác nhận. Chặn Next và reload cả khi cây Trợ năng không thấy editor; chỉ bỏ bảo vệ khi xác nhận gửi hoặc native xác nhận không nhập nội dung.
- Search: truyền ID và bounds editor đã xác minh sang native; kiểm tra lại editor rỗng, thử ACTION_SHOW_ON_SCREEN trên Post cùng hàng nhập, rồi đọc lại bounds. Chỉ paste khi Post đã ở trong WebView; gửi bằng chạm Post đang hiển thị, kiểm tra lại giới hạn trước 50% ngay trước gửi. Không thể đưa Post vào khung thì bỏ qua trước nhập. Điều này chưa bảo đảm Gecko hỗ trợ cuộn vào khung ở mọi bố cục.
- Thông báo lỗi tự động nêu lý do và bước phục hồi thay cho thông báo chung.

## Kiểm chứng

115 test Dart đạt, gồm runner, controller phục hồi, Trợ năng, tạm dừng xác minh và giữ phiên đăng nhập. Ca mới: video tải 25 giây; một frame được nạp trước không đủ xác nhận Next; editor biến mất sau gửi không gây Next; Post không hiện không được paste; Post hiện thì chỉ gửi một lần. Analyze không có lỗi.

1 test instrumentation đạt trên Android 9/API 28 với HTML cục bộ: tìm đúng editor theo ID/bounds và nhận Post đang disabled mà không nhập hoặc click gửi. Build native đạt. Không có bình luận TikTok nào được gửi bởi test cục bộ. Chưa chạy lại toàn bộ hàng đợi thật sau bản sửa; không dùng lượt ADB 09:38–09:48 trước sửa để chứng minh hiệu quả bản mới.

## Sự cố kiểm thử và khôi phục

Bộ chạy connectedDebugAndroidTest mặc định đã gỡ target app sau test, làm mất dữ liệu hiện tại trên máy ảo. Đây là sai sót trong bước chuẩn bị test. Sau khi nhận ra, đã dừng các test và khôi phục snapshot `default_boot` tối 23/10/2026 lúc 22:02:37. Trước khi load snapshot, đã lưu riêng trạng thái máy ảo hiện tại thành `codex_20261024_before_restore`.

Sau khi load snapshot, đã sao lưu toàn bộ thư mục app riêng ở `/tmp/codex_nurture_recovery_20261024/app-data-before-update.tar` (thư mục 0700, tệp 0600). Tệp có dữ liệu riêng tư nên không đưa vào báo cáo hoặc repo. Cấu hình của 3 tài khoản khớp toàn bộ các tỷ lệ và thời lượng trong báo cáo trước test. Bản snapshot có 49 phiên; đã bổ sung lại 3 phiên hoàn tất của lượt ADB 09:38–09:48 từ số liệu đã lưu, giữ thời gian và thống kê, tạo lại ID phiên. Tổng 3 phiên vẫn là 326 giây, 11 video, 0 tim, 0 bình luận xác nhận. Chi tiết khôi phục không chứa thông tin đăng nhập ở `2026-10-24-recovery.json`.

Dữ liệu/cookie được phục hồi theo snapshot tối 23/10, không phải bản sao chính xác ngay trước instrumentation; những thay đổi khác sau snapshot mà không có trong báo cáo không thể xác nhận phục hồi. Chưa kiểm tra lại đăng nhập thực tế cả 3 tài khoản. Đã bật lại dịch vụ Trợ năng, giữ Home/tab Nuôi và không để hàng đợi chạy.

Đã đặt `android.injected.androidTest.leaveApksInstalledAfterRun=true` trong `android/gradle.properties` để AGP giữ APK sau các lần connected test tiếp theo. Tên tùy chọn được đối chiếu trong BooleanOption của AGP 9.1.1 cục bộ; chưa chạy thêm connected test trên bộ dữ liệu đã phục hồi để thử tùy chọn.
