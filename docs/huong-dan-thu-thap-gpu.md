# Thu thập thông tin GPU từ máy tính thật

Mục tiêu: lấy bộ nhận diện của **Firefox trên vài máy Windows thật** có card đồ
họa khác nhau. Mỗi file thu được sẽ thành một "máy" để gán cố định cho từng cấu
hình trong app, thay vì mọi cấu hình cùng dùng một GPU như hiện nay.

Không tự nghĩ ra hay sửa tay thông tin GPU. Trên trình duyệt thật, tên GPU đi
kèm cả bộ thông số WebGL, extension, độ chính xác shader, WebGPU và số nhân CPU.
Chỉ đổi tên GPU mà giữ thông số cũ sẽ thành dấu hiệu giả. Vì vậy mọi số liệu
phải đo trực tiếp trên máy thật.

## Cần chuẩn bị

- File trang dò: `outputs/firefox-desktop/do-dau-hieu-thiet-bi-v2.html`. Chép
  sang máy cần đo qua USB, Zalo, Google Drive…
- Mỗi máy đo cần:
  - Windows 10 hoặc 11, dùng bình thường (không phải máy ảo, không Remote Desktop).
  - **Firefox** cập nhật bản mới nhất (Menu ☰ → Trợ giúp → Giới thiệu về
    Firefox). App đang giả lập Firefox 158.
  - Tăng tốc phần cứng đang bật (Cài đặt → Chung → Hiệu suất: để mặc định).

## Nên đo những máy nào

Ưu tiên các loại phổ biến. Mỗi dòng dưới đây được 1–2 máy là đủ.

| Nhóm | Ví dụ thường gặp |
| --- | --- |
| Laptop Intel (card tích hợp) | Intel UHD Graphics, Iris Xe |
| Laptop / PC AMD (card tích hợp) | Ryzen có Radeon Graphics |
| PC / laptop NVIDIA | GTX 1050–1660, RTX 2060–4060 |
| PC AMD card rời | RX 570/580, RX 6600… |

Có 4–8 máy khác nhau là tốt. Hai máy cùng một card thì chỉ cần một.

## Các bước trên mỗi máy (khoảng 2 phút)

1. Đóng các tab Firefox đang mở cho nhẹ máy.
2. **Tắt tạm tiện ích chống theo dõi hoặc đổi vân tay** nếu có (CanvasBlocker,
   uBlock ở chế độ nâng cao, Privacy Badger, User-Agent Switcher…): Menu ☰ →
   Tiện ích và chủ đề → tắt. Đo xong bật lại.
3. **Không dùng cửa sổ riêng tư.** Không đổi cài đặt `about:config` nào.
4. Mở file trang dò bằng Firefox: kéo file vào cửa sổ Firefox, hoặc nhấn
   `Ctrl+O` rồi chọn file.
5. Phóng to cửa sổ Firefox (nút □), để zoom trang 100% (`Ctrl+0`).
6. Đợi khoảng 5 giây đến khi dòng trạng thái báo **Xong**. Không bấm gì trong
   lúc đo.
7. Bấm **Tải file kết quả**. Firefox lưu file `ket-qua-may-tinh.json` vào thư
   mục Tải xuống.
8. **Đổi tên file** theo mẫu `gpu-<hãng>-<tên card>-<tên máy>.json`, ví dụ
   `gpu-nvidia-gtx1650-laptop-lan.json`, `gpu-intel-uhd620-pc-ketoan.json`.
9. Ghi một dòng vào bảng ở cuối file này.

Nếu không tải được file: bấm **Copy**, dán vào Notepad và lưu thành `.json` với
tên như bước 8.

## Kiểm tra nhanh trước khi gửi

Mở file JSON (bằng Notepad) và tìm `UNMASKED_RENDERER`. Giá trị phải là tên
card thật, dạng `ANGLE (NVIDIA, NVIDIA GeForce ... Direct3D11 ...), or similar`.
- Nếu ra `Generic Renderer`, `llvmpipe`, `Microsoft Basic Render Driver` hoặc
  trống: máy đang tắt tăng tốc phần cứng, hoặc thiếu driver card. Không dùng file này.
- Nếu `userAgent` không chứa `Windows NT 10.0` và `Firefox/`: mở nhầm trình
  duyệt. Đo lại bằng Firefox.

File chỉ chứa thông tin trình duyệt và phần cứng: GPU, số nhân CPU, độ phân
giải, font, giọng đọc, ngôn ngữ, múi giờ. Không có mật khẩu, lịch sử hay tài khoản.

## Gửi lại

Gom các file `.json` vào một thư mục (hoặc nén zip) rồi gửi kèm bảng dưới đây.

| # | Tên file | Hãng / tên card (theo máy) | Laptop hay PC | Độ phân giải màn hình | Ghi chú |
| --- | --- | --- | --- | --- | --- |
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |
| 6 | | | | | |

Xem tên card trên máy: Task Manager (`Ctrl+Shift+Esc`) → Hiệu suất → GPU.

## Sau khi có file

1. Kiểm tra từng file: Firefox trên Windows, GPU thật, không dính tiện ích đổi vân tay.
2. Dựng mỗi file thành một bộ nhận diện trọn vẹn: tên GPU (vendor/renderer), các
   giới hạn và extension WebGL/WebGL2, độ chính xác shader, MSAA, WebGPU và số
   nhân CPU đi kèm. Bộ AMD hiện tại (đo từ máy của khách,
   `khach-firefox-v2-2026-10-27.json`) vẫn là một trong các bộ.
3. Mỗi cấu hình được gán một bộ **cố định**. Cấu hình đang có giữ bộ AMD hiện tại
   để không đổi "máy" giữa chừng với tài khoản đã đăng ký. Cột "Thiết bị (GPU)"
   trong app và file Excel hiện đúng máy được gán.
4. Kiểm chứng trên giả lập: trang WhatIsMyBrowser và trang dò phải báo đúng bộ đã
   gán. Đăng ký và nuôi thử để chắc TikTok không hiện lại "Continue on app".

## Giới hạn cần biết

- **Chữ ký hình vẽ canvas/WebGL không đổi theo bộ được.** Hình do chip đồ họa của
  điện thoại vẽ ra, nên mọi cấu hình vẫn có chung chữ ký này. Thêm nhiễu vào hình
  cũng tự nó là dấu hiệu bị phát hiện, nên không làm.
- Độ phân giải trang trong app vẫn là 1920×1080 cho mọi cấu hình, kể cả khi máy
  đo có màn hình khác. Đây là màn hình phổ biến nhất, đã kiểm chứng ngày 27/10.
- Font và giọng đọc vẫn theo bộ Windows chuẩn hiện tại. File đo chỉ dùng để đối
  chiếu, không bắt buộc khớp từng máy.
