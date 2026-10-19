# Kiểm tra cách ly phiên khi đổi cấu hình

Kiểm tra mã app và bản plugin đang cài: `flutter_inappwebview 6.1.5`, Android
`1.1.3`, iOS `1.1.2`. Đây là kiểm tra mã nguồn và kiểm thử giả lập API;
chưa kiểm chứng dữ liệu trình duyệt thật sau một lần chuyển cấu hình.

## Luồng hiện tại

`ProxyManagementController.use()` đọc cấu hình hiện tại và so sánh `sameProfile`.
Khi chọn cấu hình có proxy/credentials proxy, UA, múi giờ hoặc thông tin tài khoản
khác, nó chờ `clearAppSession()` trước `store.useSaved()`. Trong lúc chờ, nút chọn
bị khóa. Nếu API ném lỗi, cấu hình đang dùng được giữ và app báo lỗi.

`clearAppSession()` lần lượt gọi:

1. `CookieManager.deleteAllCookies()`.
2. Android: `WebStorageManager.deleteAllData()`; iOS/macOS:
   `removeDataModifiedSince(WebsiteDataType.ALL, epoch)`.
3. `InAppWebViewController.clearAllCache()` với cache trên đĩa được bật.

Trên Android, plugin chờ callback xóa cookie. `false` từ callback có thể có
nghĩa không có cookie để xóa, không được tự coi là lỗi. Plugin gọi
`android.webkit.WebStorage.deleteAllData()` rồi trả kết quả ngay; không có
callback hoàn tất thao tác storage. Xóa cache dùng một WebView tạm và
`clearCache(true)`, sau đó hủy WebView đó.

Trên iOS, plugin dùng `WKWebsiteDataStore.default()` và chờ completion callback.
`WebsiteDataType.ALL` của bản plugin này gồm cookies, local/session storage,
IndexedDB, service worker registrations, fetch cache và các loại cache khác.

## Các giới hạn đã thấy

- Chọn lại cùng `sameProfile` giữ phiên, dù ID/tên/trạng thái đăng ký khác.
- **Bỏ chọn cấu hình** đi qua `entry == null`, giữ cookie/phiên theo thiết kế cũ.
- Android chưa sử dụng API xóa dữ liệu duyệt web đầy đủ có callback hoàn tất.
  Chưa có bằng chứng runtime rằng service workers/Cache Storage được xóa hết
  trước khi trang của cấu hình kế tiếp bắt đầu tải.
- WebView chính và các WebView IP/múi giờ dùng kho dữ liệu mặc định chung.
  Các probe có hủy/dispose trong `finally`. Khi rời màn TikTok, controller hủy
  tác vụ OTP/IP và widget giải phóng WebView. Luồng đổi cấu hình không có bước
  xác nhận tập trung rằng mọi WebView/request cũ đã dừng trước khi xóa dữ liệu.

Vì vậy chưa thể kết luận “đã xóa triệt để”. Việc gọi đủ ba API không phải bằng
chứng mọi loại dữ liệu đã biến mất. AndroidX cung cấp
[`WebStorageCompat.deleteBrowsingData`](https://developer.android.com/reference/androidx/webkit/WebStorageCompat#deleteBrowsingData(android.webkit.WebStorage,java.lang.Runnable))
để xóa network cache, cookies và storage mà JavaScript có thể đọc, với callback
hoàn tất; API cần kiểm tra hỗ trợ `DELETE_BROWSING_DATA` trên WebView thực tế.

## Kiểm thử và đối chiếu chế độ TikTok

`test/proxy_management_test.dart` kiểm tra thứ tự chờ cookie/storage/cache,
giữ cấu hình khi xóa lỗi, chọn lại giữ phiên và bỏ chọn giữ phiên.
`test/configuration_preview_test.dart` kiểm tra đổi tài khoản trên cùng proxy
vẫn gọi xóa phiên. `test/app_session_test.dart` kiểm tra Apple gọi xóa mọi loại
dữ liệu website và cache. Các test này dùng platform giả, không chứng minh
IndexedDB/service workers/cookies của WebView thật đã được xóa.

Các nút TikTok từ Home tạo `TikTokPage` với `useInstalledEngine = true` mặc định;
chế độ Tương thích cũng dùng engine đó nếu chưa chọn profile UA thủ công.
UA/Client Hints mặc định dựa trên Chromium đang cài, dùng CPU/RAM/GPU gốc và
chặn WebRTC. Tuy nhiên Home có các script/thao tác tự động và áp dụng múi giờ
proxy đã lưu; Tương thích `useNativeWebView = true` tắt các thao tác đó và dùng
múi giờ thiết bị. Hai chế độ chưa giống mọi thiết lập/hành vi.

Kiểm tra này không đổi logic xóa phiên và không xóa cookie/dữ liệu tài khoản thật.
