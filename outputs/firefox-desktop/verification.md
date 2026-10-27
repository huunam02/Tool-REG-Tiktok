# Kiểm tra WhatIsMyBrowser — 26/10/2026

Đã mở https://www.whatismybrowser.com/ trực tiếp trong GeckoView của ứng dụng trên emulator-5554 (Android 9/API 28). 25/25 mục nhận diện/cài đặt đối chiếu với bản người dùng cung cấp đều khớp.

| Mục | Giá trị thực tế | Khớp mẫu |
| --- | --- | --- |
| Software Type | Web Browser | Có |
| Hardware Type | Computer | Có |
| Browser version (full) | 158.0 | Có |
| Operating System version (full) | NT 10.0 | Có |
| Hardware Architecture | 64-bit processor (AMD) | Có |
| Layout Engine | Gecko | Có |
| Gecko version | 20100101 | Có |
| Configured Languages | Tiếng Việt (Vietnamese), English | Có |
| Device Pixel Ratio | 1 | Có |
| Browser GMT Offset | +07:00 | Có |
| Navigator Platform | Windows (32-Bit) | Có |
| OS / CPU | Windows NT 10.0; Win64; x64 | Có |
| No. of logical CPU cores | 16 | Có |
| Maximum Touch Points | 0 | Có |
| WebGL Vendor | Google Inc. (AMD) | Có |
| WebGL Renderer | ANGLE (AMD, Radeon R9 200 Series Direct3D11 vs_5_0 ps_5_0), or similar | Có |
| ECMA Version | 11 (ES2020) | Có |
| User-Agent | Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:158.0) Gecko/20100101 Firefox/158.0 | Có |
| Screen | 1536 x 864 / 24 bit | Có |
| Window | 1550 x 830 | Có |
| JavaScript enabled | True | Có |
| Cookies enabled | True | Có |
| Third-party cookies enabled | True | Có |
| Local IP blocked | True | Có |
| Browser name | Firefox 158 on Windows 10 | Có |

Referrer trống vì mở trực tiếp; mẫu truy cập từ Google. IP/ISP/vị trí hiện cũng trùng mẫu (VNPT, Hà Nội), nhưng phụ thuộc kết nối mạng. Không giả referrer hay thông tin mạng.

Kết quả này xác nhận các mục trang WhatIsMyBrowser hiển thị, không chứng minh mọi fingerprint đều giống Firefox Windows thật. Engine vẫn là GeckoView Android; các giới hạn worker và thời điểm chạy script múi giờ đã nêu trong README vẫn áp dụng.

Bằng chứng: [ảnh đầu trang](whatismybrowser-top.png), [ảnh chi tiết](whatismybrowser-details.png), [JSON](whatismybrowser-2026-10-26.json).

Không phát hiện sai lệch mới cần sửa mã nguồn trong lần đối chiếu này.
