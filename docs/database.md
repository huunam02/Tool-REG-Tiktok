# Dữ liệu cục bộ — schema 10

SQLite vẫn dùng file `proxies.db`. Nâng cấp schema 9 → 10 là giao dịch của
sqflite: giữ nguyên `configurations`, tạo ba bảng mới và khởi tạo danh sách
tài khoản từ email của cấu hình. Các migration cũ tiếp tục chạy trước bước này.

| Bảng | Khóa | Dữ liệu |
| --- | --- | --- |
| `configurations` | `id` | Cấu hình, proxy, UA, thông tin đăng nhập, trạng thái đăng ký, cấu hình hiện tại. Giữ nguyên cột cũ. |
| `nurture_accounts` | `account_key` | Email đã trim/lowercase làm khóa; email hiển thị và thời điểm tạo/cập nhật. Không sao chép mật khẩu. |
| `nurture_sessions` | `id` | Tài khoản, cấu hình tham chiếu, chế độ `feed`/`search`, keyword, trạng thái, các bộ đếm tích lũy, revision và thời điểm. |
| `app_settings` | `key` | Giữ dữ liệu danh sách cũ (`home_comments`, `nurture_keywords`) và cờ migration. Home không còn đọc/ghi các danh sách này. |

Danh sách từ khóa và bình luận hiện chỉ lấy từ Firebase Remote Config qua hai
tham số `search_keywords` và `auto_comments` (kiểu String, nội dung là JSON array các chuỗi). Hai ô nhập
trên Home đã được bỏ. Các danh sách trong `lib/core/config.dart` chỉ là mặc định
của Remote Config khi thiếu tham số hoặc JSON sai định dạng. Không đổi schema
hoặc xóa dữ liệu cũ trong `app_settings`.

`nurture_sessions.account_key` tham chiếu tài khoản.
`configuration_id` tham chiếu cấu hình với `ON DELETE SET NULL`: xóa cấu hình
vẫn giữ lịch sử. Chỉ mục `(account_key, updated_at)` phục vụ cộng dồn và lấy
phiên mới nhất. Bật `PRAGMA foreign_keys = ON` khi mở DB.

Mỗi phiên xem thủ công có một ID riêng; mỗi document WebView có một segment.
JavaScript chỉ quan sát, không phát video, lướt, nhập liệu hoặc gửi bình luận.
Snapshot tích lũy trong segment gồm `watch_ms`, `videos`, `full_videos`,
`skipped_videos`, `comments` và sequence. Dart chỉ chấp nhận session/segment
đã đăng ký, sequence mới và số liệu không giảm. Tổng của các segment được ghi
bằng revision tăng dần để callback trùng hoặc đến muộn không cộng hai lần.

`watch_ms` là thời gian video thực sự phát, không phải thời gian mở màn hình.
Một video được tính một lần cho mỗi lượt xem của document khi kết thúc,
chuyển sang video khác hoặc đóng phiên. Reload tạo document/lượt xem mới.
`full_videos` ghi nhận `ended`; các lượt còn lại ghi vào `skipped_videos`.
Hai số cộng lại bằng `videos`. Bình luận cần phản hồi publish/post/create
cùng origin, `status_code = 0`, có ID bình luận chưa ghi trong document;
không lưu nội dung bình luận, URL request hoặc thông tin xác thực vào bảng phiên.

Trạng thái: `running`, `paused`, `stopped`, `error`; schema cũng dành sẵn
`waiting`, `completed`. Khi mở lại DB sau khi tiến trình kết thúc, các phiên
`waiting`/`running`/`paused` chuyển thành `stopped`, giữ nguyên bộ đếm.
Không tự khởi động lại phiên. Snapshot lưu khoảng hai giây/lần; đóng màn hình
chờ chốt dữ liệu trước khi trở về Home. Force stop/crash có thể mất phần chưa lưu.

Tab **Nuôi acc** hiển thị thống kê đã lưu; nút mở xem thủ công đã được bỏ.
Dữ liệu phiên xem thủ công vẫn được giữ. Không có backfill lượt xem/bình luận
trước nâng cấp hoặc từ các luồng tự động cũ.

Kiểm thử: `test/nurture_store_test.dart` kiểm tra migration, aggregation,
reopen, snapshot trùng/cũ và xóa cấu hình; `test/manual_viewing_session_test.dart`
kiểm tra callback/segment; `test/manual_viewing_script_test.js` kiểm tra đo thời
gian và phản hồi bình luận; `test/home_nurture_test.dart` kiểm tra tab/cài đặt.
