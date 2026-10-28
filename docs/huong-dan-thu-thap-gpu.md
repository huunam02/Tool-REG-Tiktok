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
  - **Firefox 158** để khớp GeckoView và bộ nhận diện app đang dùng. Kiểm tra
    phiên bản ở Menu ☰ → Trợ giúp → Giới thiệu về Firefox trước khi đo.
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
| 1 | `outputs/firefox-desktop/gpu/gpu-intel-hd400-firefox158-2026-10-28.json` | Intel; Firefox báo nhóm "Intel(R) HD Graphics 400" (card thật: chưa ghi) | chưa ghi | 1920×1080 (thanh tác vụ 48 px; DPR 1) | Đo lại Firefox 158, 8 luồng CPU trình duyệt báo, cửa sổ chưa phóng to (1280×859); WebGPU hết giờ; nguồn: `ket-qua-may-tinh_update.json` |
| 2 | `outputs/firefox-desktop/gpu/gpu-intel-hd-2026-10-28.json` | Intel; Firefox báo nhóm "Intel(R) HD Graphics" (card thật: chưa ghi) | chưa ghi | 1536×864 CSS px (DPR 1.25; vùng làm việc 1536×816) | Firefox 158, 16 luồng CPU trình duyệt báo, cửa sổ chưa phóng to (1280×649); nguồn: `ket-qua-may-tinh 3.json` |
| 3 | `outputs/firefox-desktop/gpu/gpu-intel-hd400-firefox158-touch-2026-10-28.json` | Intel; Firefox báo nhóm "Intel(R) HD Graphics 400" (card thật: chưa ghi) | chưa ghi | 1536×864 CSS px (DPR 1.25; vùng làm việc 1536×816) | Firefox 158, 8 luồng CPU trình duyệt báo, hỗ trợ 5 điểm chạm, cửa sổ chưa phóng to (1280×649); WebGPU đo thành công; nguồn: `ket-qua-may-tinh 4.json` |
| 4 | `outputs/firefox-desktop/gpu/gpu-intel-hd-firefox158-cpu12-2026-10-28.json` | Intel; Firefox báo nhóm "Intel(R) HD Graphics" (card thật: chưa ghi) | chưa ghi | 1536×864 CSS px (DPR 1.25; vùng làm việc 1536×816) | Firefox 158, 12 luồng CPU trình duyệt báo, không cảm ứng, cửa sổ chưa phóng to (1280×649); WebGPU đo thành công; nguồn: `ket-qua-may-tinh 5.json` (có dấu cách trước số 5) |
| 5 | `outputs/firefox-desktop/gpu/gpu-amd-r9-200-firefox158-touch-2026-10-28.json` | AMD; Firefox báo nhóm "Radeon R9 200 Series" (card thật: chưa ghi) | chưa ghi | 1920×1080 (thanh tác vụ 48 px; DPR 1) | Firefox 158, 16 luồng CPU trình duyệt báo, hỗ trợ 1 điểm chạm, cửa sổ chưa phóng to (1280×843); WebGPU đo thành công; nguồn: `ket-qua-may-tinh 6.json` |
| 6 | `outputs/firefox-desktop/gpu/gpu-amd-r9-200-firefox158-cpu12-touch5-2026-10-28.json` | AMD; Firefox báo nhóm "Radeon R9 200 Series" (card thật: chưa ghi) | chưa ghi | 1536×864 CSS px (DPR 1.25; vùng làm việc 1536×816) | Firefox 158, 12 luồng CPU trình duyệt báo, hỗ trợ 5 điểm chạm; lúc đo kích thước cửa sổ trả về 0×0; WebGPU đo thành công; nguồn: `ket-qua-may-tinh 7.json` |
| 7 | `outputs/firefox-desktop/gpu/gpu-amd-r9-200-firefox158-cpu16-no-touch-2026-10-28.json` | AMD; Firefox báo nhóm "Radeon R9 200 Series" (card thật: chưa ghi) | chưa ghi | 1536×864 CSS px (DPR 1.25; vùng làm việc 1536×816) | Firefox 158, 16 luồng CPU trình duyệt báo, không cảm ứng, cửa sổ chưa phóng to (1280×649); WebGPU đo thành công; nguồn: `ket-qua-may-tinh 8.json` |

Xem tên card trên máy: Task Manager (`Ctrl+Shift+Esc`) → Hiệu suất → GPU.

Bộ Intel HD Graphics 400 (`intel-hd-400`) đã được đo lại bằng Firefox 158.
Bản mới ở dòng 1 là dữ liệu tham chiếu chính; bản Firefox 159 cũ vẫn được giữ
tại `outputs/firefox-desktop/gpu/gpu-intel-hd400-2026-10-28.json` để đối chiếu.
Tên GPU, giới hạn, độ chính xác shader và antialias không đổi giữa hai lần đo;
bản 158 không có `EXT_clip_control`, `EXT_texture_mirror_clamp_to_edge` ở cả
WebGL1/WebGL2 và `EXT_texture_norm16` ở WebGL2. Danh sách extension và các giới
hạn đã khai báo trong app khớp bản đo 158, nên giữ nguyên mã `intel-hd-400` và
các thông số đang dùng. Phần `extras.gpuAdapter` của bản ở dòng 1 báo `hết giờ`:
lần đo đó chưa có kết quả WebGPU, không coi đây là kết quả không hỗ trợ.

File gửi thêm `ket-qua-may-tinh5.json` trùng toàn bộ byte với bản ở dòng 1
(nguồn `ket-qua-may-tinh_update.json`), cùng `measuredAt` là
`2026-10-28T06:44:53.937Z`. Đây là cùng một kết quả được gửi lại, nên dùng
chung file đã lưu, không thêm dòng đo hoặc bộ GPU mới. Người gửi xác nhận
đã gửi nhầm bản cũ này; file số 5 đúng là `ket-qua-may-tinh 5.json` ở dòng 4.

Bản bổ sung ở dòng 3 có toàn bộ dữ liệu `webgl` và `webgl2` giống dòng 1,
nên cùng dùng bộ `intel-hd-400`, không thêm một bộ GPU trùng. WebGPU ở dòng 3
đo thành công: 13 feature, `maxTex = 16384`, vendor và architecture là chuỗi
rỗng; dữ liệu adapter giống bộ AMD và Intel HD Graphics đã lưu. Kết quả này
bổ sung phép đo WebGPU thành công cho nhóm HD400 trên Firefox 158, không thay
thế trạng thái hết giờ của bản ở dòng 1. File dòng 3 báo `maxTouchPoints = 5`
và có `TouchEvent`, nên không dùng nó làm mẫu cho phần thiết bị không cảm ứng
của app. Giữ nguyên file đo; chỉ dùng dữ liệu GPU để đối chiếu bộ hiện tại.

Bộ Intel HD Graphics ở dòng 2 đã được thêm vào app với mã `intel-hd`, khác
bộ `intel-hd-400` ở dòng 1. WebGL/WebGL2 có cùng danh sách extension và độ
chính xác shader với bộ AMD Firefox 158; `MAX_SAMPLES` của WebGL2 là 16.
Cấu hình mới chọn ngẫu nhiên trong ba bộ AMD, Intel HD Graphics 400 và Intel
HD Graphics, rồi lưu cố định. CPU và màn hình trong file đo chỉ để đối chiếu;
app vẫn giữ số luồng CPU native và màn hình 1920×1080 như trước.

Bản ở dòng 4 là kết quả mới (`measuredAt = 2026-10-28T06:58:23.987Z`),
khác file `ket-qua-may-tinh5.json` không có dấu cách đã gửi trước. Máy báo
12 luồng CPU thay vì 16 ở dòng 2; toàn bộ dữ liệu `webgl`, `webgl2` và
`extras.gpuAdapter` giống dòng 2. WebGPU có 13 feature và `maxTex = 16384`.
Vì vậy dòng 4 bổ sung dữ liệu tham chiếu cho bộ `intel-hd`, không thêm bộ GPU
thứ tư. Giữ riêng file đo; không lấy số luồng CPU 12 để áp dụng vào app.

Bản ở dòng 5 (`measuredAt = 2026-10-28T07:44:46.415Z`) bổ sung dữ liệu
tham chiếu cho bộ AMD `amd-r9-200`. Toàn bộ dữ liệu `webgl`, `webgl2` và
`extras.gpuAdapter` giống bản AMD gốc `khach-firefox-v2-2026-10-27.json`;
`MAX_SAMPLES` của WebGL2 là 8, WebGPU có 13 feature và `maxTex = 16384`.
Máy báo 16 luồng CPU, `maxTouchPoints = 1` và có `TouchEvent`. Giữ nguyên
file đo để đối chiếu GPU; không áp dụng phần cảm ứng vào bộ desktop của app.
Không thêm bộ GPU mới hoặc thay đổi các cấu hình đã lưu.

Bản ở dòng 6 (`measuredAt = 2026-10-28T08:34:29.962Z`) là lần đo mới của
cùng bộ AMD `amd-r9-200`. Toàn bộ dữ liệu `webgl`, `webgl2` và
`extras.gpuAdapter` trùng bản AMD gốc và dòng 5: WebGL2 `MAX_SAMPLES = 8`,
WebGPU có 13 feature và `maxTex = 16384`. Máy báo 12 luồng CPU,
`maxTouchPoints = 5`, màn hình 1536×864 CSS px ở DPR 1.25. Các trường kích
thước cửa sổ và document đều bằng 0 trong lần đo này, nên không dùng chúng
làm mẫu viewport. File được giữ riêng làm dữ liệu tham chiếu; không thêm bộ
GPU mới, không đổi cấu hình `amd-r9-200` và không áp dụng CPU/cảm ứng vào app.

Bản ở dòng 7 (`measuredAt = 2026-10-28T08:39:52.241Z`) tiếp tục xác nhận bộ
AMD `amd-r9-200`: toàn bộ `webgl`, `webgl2` và `extras.gpuAdapter` trùng bản
AMD gốc cùng các dòng 5–6. Máy báo 16 luồng CPU, không cảm ứng; màn hình
1536×864 CSS px ở DPR 1.25 và viewport 1280×649 hợp lệ. WebGPU đo thành công
với 13 feature và `maxTex = 16384`; phép liệt kê thiết bị cũng thành công với
một audio input và một video input. Đây là dữ liệu tham chiếu bổ sung gần với
mẫu AMD desktop gốc, không tạo thêm bộ GPU và không yêu cầu sửa mã ứng dụng.

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
