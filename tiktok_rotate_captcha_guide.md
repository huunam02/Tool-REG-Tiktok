# Hướng Dẫn Tích Hợp API Giải TikTok Rotate Captcha (SadCaptcha)

Tài liệu này hướng dẫn cách gọi API của SadCaptcha để giải mã dạng **TikTok Rotate Captcha** (Captcha xoay hình) và quy trình phát hiện / xử lý tự động trong các script tự động hóa trình duyệt.

---
 đay
## 1. Tổng Quan về API

API nhận dữ liệu 2 bức ảnh (ảnh nền bên ngoài và ảnh hình tròn bên trong) dạng Base64, sau đó trả về **góc xoay** ($a$) cần thiết từ $0^\circ$ đến $360^\circ$ để xoay hình về đúng vị trí.

* **Endpoint:** `POST https://www.sadcaptcha.com/api/v1/rotate`
* **Query Parameter:** `licenseKey` (string, bắt buộc)
* **Request Body:** `application/json`
  * `outerImageB64`: Chuỗi Base64 của ảnh vòng ngoài (`outer_tt.png`)
  * `innerImageB64`: Chuỗi Base64 của ảnh vòng trong (`inner_tt.png`)
* **Response Status:**
  * `200`: Thành công, trả về góc xoay.
  * `400`: Request không hợp lệ / Thiếu tham số.

---

## 2. Câu Lệnh `curl`

Do chuỗi Base64 của ảnh rất dài, cách tốt nhất là lưu JSON payload vào một file rồi truyền qua `curl`.

### Bước 1: Tạo file `payload.json`
```json
{
  "outerImageB64": "iVBORw0KGgoAAAANSUhEUgAA...",
  "innerImageB64": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

### Bước 2: Thực thi lệnh `curl`
```bash
curl -X POST "https://www.sadcaptcha.com/api/v1/rotate?licenseKey=YOUR_API_KEY_HERE" \
     -H "Content-Type: application/json" \
     -d @payload.json
```

---

## 3. Cách Quy Đổi Góc Xoay Ra Khoảng Cách Kéo (Pixel)

Sau khi nhận được góc $a$ (từ $0$ đến $360$), cần chuyển đổi thành khoảng cách trượt $d$ (đơn vị pixel) trên thanh slider bằng công thức:

$$d = \frac{(l_s - l_i) \times a}{360}$$

**Trong đó:**
* $l_s$: Chiều dài tổng cộng của thanh trượt (CSS Selector: `.captcha_verify_slide--slidebar`).
* $l_i$: Chiều dài của nút kéo slider (CSS Selector: `.secsdk-captcha-drag-icon`).
* $a$: Góc xoay do SadCaptcha trả về.

---

## 4. Giải Pháp Xử Lý Khi Captcha Xuất Hiện Bất Ngờ (Auto Detect & Solve)

Vì Captcha xuất hiện ngẫu nhiên tùy thuộc vào tương tác trên session, bạn nên tạo một cơ chế kiểm tra (Polling / Waiting) trong code điều khiển trình duyệt.

### Quy Trình Xử Lý Chi Tiết (Workflow):

```
[Thực hiện thao tác người dùng]
               │
               ▼
   [Kiểm tra DOM xem Captcha có xuất hiện không?]
         │                      │
       (Không)                (Có)
         │                      │
         ▼                      ▼
  [Bỏ qua / Tiếp tục]   1. Lấy URL/Base64 của 2 ảnh (Inner & Outer)
                        2. Lấy kích thước l_s (thanh trượt) và l_i (nút kéo)
                        3. Gửi 2 ảnh lên API SadCaptcha ──► Nhận góc xoay (a)
                        4. Tính d = ((l_s - l_i) * a) / 360
                        5. Thực hiện kéo nút trượt đúng khoảng cách d
                        6. Chờ captcha biến mất & tiếp tục thao tác
```

---

## 5. Đoạn Mã Python Mẫu (Dùng Selenium)

Dưới đây là đoạn mã ví dụ về việc xử lý linh hoạt: Kiểm tra sự tồn tại của Captcha trước khi gọi API giải.

```python
import time
import requests
import base64
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.action_chains import ActionChains

API_KEY = "YOUR_SADCAPTCHA_LICENSE_KEY"

def is_captcha_present(driver):
    """Kiểm tra xem Captcha xoay có đang xuất hiện trên màn hình không."""
    elements = driver.find_elements(By.CSS_SELECTOR, '.captcha_verify_slide--slidebar')
    return len(elements) > 0 and elements[0].is_displayed()

def solve_tiktok_rotate(driver):
    """Hàm giải Captcha Rotate khi phát hiện."""
    print("Detected TikTok Rotate Captcha. Solving...")
    
    # 1. Lấy phần tử hình ảnh & thanh trượt
    outer_img_elem = driver.find_element(By.CSS_SELECTOR, 'img.captcha_verify_img_outer')
    inner_img_elem = driver.find_element(By.CSS_SELECTOR, 'img.captcha_verify_img_inner')
    slidebar_elem = driver.find_element(By.CSS_SELECTOR, '.captcha_verify_slide--slidebar')
    drag_icon_elem = driver.find_element(By.CSS_SELECTOR, '.secsdk-captcha-drag-icon')

    # 2. Lấy kích thước thực tế trên giao diện
    l_s = slidebar_elem.size['width']
    l_i = drag_icon_elem.size['width']

    # 3. Chuyển ảnh sang Base64
    outer_b64 = outer_img_elem.get_attribute('src').split(',')[1]
    inner_b64 = inner_img_elem.get_attribute('src').split(',')[1]

    # 4. Gọi SadCaptcha API
    url = f"https://www.sadcaptcha.com/api/v1/rotate?licenseKey={API_KEY}"
    payload = {
        "outerImageB64": outer_b64,
        "innerImageB64": inner_b64
    }
    
    res = requests.post(url, json=payload).json()
    angle = res.get('angle', 0)

    # 5. Tính khoảng cách trượt d
    d = ((l_s - l_i) * angle) / 360

    # 6. Kéo thả thanh trượt
    action = ActionChains(driver)
    action.click_and_hold(drag_icon_elem).perform()
    
    # Trượt sang phải d pixel
    action.move_by_offset(d, 0).perform()
    time.sleep(0.5)
    action.release().perform()
    
    print(f"Solved! Rotated {angle} degrees, dragged {d} px.")
    time.sleep(2)

# === SỬ DỤNG TRONG LUỒNG CHÍNH ===
# driver = webdriver.Chrome()
# driver.get("https://tiktok.com/...")

if is_captcha_present(driver):
    solve_tiktok_rotate(driver)
else:
    print("No captcha detected, continue working...")
```
---

## 6. Tích hợp trong ứng dụng Flutter hiện tại

Đã tích hợp đọc ảnh/thanh kéo trong `lib/core/scripts/rotate_captcha_script.dart`,
gọi API trong `lib/core/rotate_captcha.dart` và nối vào `TikTokController`.
Bộ theo dõi CAPTCHA riêng chỉ được kích hoạt khi **Auto nuôi đang bật**.
Trong phiên nuôi, app kiểm tra định kỳ và kiểm tra trước thao tác Accessibility.
Khi chưa bật Auto nuôi, đang đăng nhập/đăng ký hoặc xem thủ công, bộ theo dõi
không đọc DOM CAPTCHA và không gọi API giải.

### Cấu hình API key

Cấu hình tham số String **`sadcaptcha_license_key`** trong Firebase Remote Config
và publish. App fetch và activate khi khởi động. Nếu chưa có giá trị trên Firebase,
app dùng mặc định trong `RemoteConfigKey.defaultValue`, đã đăng ký bằng `setDefaults()`.
Nếu fetch thất bại, app vẫn đọc giá trị Firebase đã cache hoặc mặc định.

Ứng dụng không có màn nhập hoặc xem cấu hình API OTP/CAPTCHA. App chỉ dùng
Remote Config và không đọc key cũ lưu trên thiết bị.
Đặt key rỗng trong Remote Config để tắt tự giải CAPTCHA. API key không truyền
vào JavaScript và không ghi vào log của tính năng CAPTCHA.

### Vuốt bằng `flutter_accessibility_service`

Bật Trợ năng cho **Tool TikTok** trên Android. Dependency đã trỏ tới bản bundled
`third_party/flutter_accessibility_service`, không cần thêm package khác.
`SignupAccessibility.swipeScreen()` sử dụng `FlutterAccessibilityService.dispatchGesture()`
với một stroke liên tục, chờ Android báo hoàn tất thao tác.

DOM chỉ cung cấp URL ảnh (HTTPS hoặc data URI) và hình học thanh kéo. App tải ảnh,
gửi `outerImageB64` / `innerImageB64` đến SadCaptcha, kiểm tra trường `angle` là số
hữu hạn trong `[0, 360]`, rồi tính khoảng kéo theo công thức ở mục 3.
Tọa độ CSS được đổi trực tiếp sang pixel màn hình bằng tỷ lệ chiều rộng WebView
thật / chiều rộng visual viewport và cộng vị trí WebView từ Accessibility.
Không nhân trực tiếp với `devicePixelRatio` vì bố cục desktop có thể thu nhỏ;
điểm kéo phải nằm trong bounds WebView hiện tại.

Trước khi kéo, app đọc lại ảnh và hình học, kiểm tra WebView còn nguyên vị trí,
đúng TikTok, ứng dụng ở foreground và màn TikTok vẫn đang hiển thị. Sau cú kéo, app
chờ tối đa 12 giây cho CAPTCHA biến mất. Gesture hoàn tất chưa được xem là giải
thành công. Không lặp gọi API/kéo cùng CAPTCHA khi xác minh thất bại.

Chỉ hỗ trợ CAPTCHA xoay với các selector ở tài liệu này trong document chính.
CAPTCHA trong iframe khác origin, dạng puzzle/chọn hình, ảnh `blob:`, ảnh bị chặn
hoặc markup khác cần xử lý thủ công. Khi ảnh đang tải, app chờ tối đa 5 giây.
Lỗi mạng/API, góc sai, thay đổi CAPTCHA hoặc chưa xác nhận kết quả sẽ dừng luồng
để giữ màn hiện tại. Chưa kiểm chứng với một CAPTCHA TikTok thật trên thiết bị.

Tham chiếu hợp đồng API: [SadCaptcha chính thức](https://www.sadcaptcha.com/api/v1/swagger-ui/index.html).

## 7. Chỉ bật bộ theo dõi CAPTCHA trong phiên Auto nuôi

Khi đã cấu hình API key và bật Trợ năng trên Android, bộ theo dõi tự chạy lúc
**Auto nuôi được bật**, áp dụng cho cả **Nuôi news feed** và **Nuôi search keyword**.
Hai loại nuôi dùng chung bộ theo dõi, không tạo hai timer song song. Trong suốt
phiên nuôi, CAPTCHA xoay có thể xuất hiện ở Home, trang tìm kiếm, video chi tiết, Profile (`/@username`) hoặc bất kỳ trang TikTok nào và đều được kiểm tra.
Không cần biết trước thời điểm CAPTCHA xuất hiện.

App kiểm tra **mỗi 1 giây sau khi lần kiểm tra trước hoàn tất** và kiểm tra thêm
trước thao tác nuôi. Khi phát hiện CAPTCHA xoay được hỗ trợ, app chờ thao tác
native đang thực hiện hoàn tất, tạm giữ thao tác tiếp theo, gọi API và kéo thanh
bằng Accessibility. Các yêu cầu đồng thời cùng chờ một lượt giải. CAPTCHA biến
mất hai lần liên tiếp thì luồng nuôi tiếp tục.

Tắt Auto nuôi, hết thời gian nuôi hoặc dừng phiên sẽ hủy timer và yêu cầu API
đang chờ. Không kéo CAPTCHA hoặc thực hiện thao tác nuôi chờ sẵn sau khi dừng.
Nếu đưa ứng dụng ra nền hoặc TikTok bị màn khác che, bộ theo dõi cũng tạm dừng;
khi quay lại chỉ chạy tiếp nếu Auto nuôi vẫn đang bật.

Khi chưa bật Auto nuôi, đang đăng nhập/đăng ký, xem thủ công hoặc ở Native WebView,
bộ theo dõi không chạy và không gọi API giải. Nếu giải lỗi hoặc thiếu Trợ năng,
app dừng phiên nuôi và thông báo để kiểm tra; không tự thử lại CAPTCHA đó.
Muốn chạy tiếp cần bật lại Auto nuôi. App không tự chuyển từ Profile về Home.

Tính năng chỉ tự giải dạng **xoay hình** đã mô tả; puzzle/chọn hình hoặc CAPTCHA
trong iframe khác origin vẫn cần xử lý thủ công.

## 8. Hộp CAPTCHA nhỏ trên trang TikTok desktop như ảnh minh họa

Ảnh được cung cấp cho thấy hộp CAPTCHA xoay nổi phía trên trang TikTok và cột
bình luận, với ảnh tròn ở giữa và nút mũi tên ở đầu thanh kéo bên dưới. Không lấy
tọa độ cố định từ ảnh chụp: cùng hộp này có thể đổi vị trí/kích thước theo màn
hình và mức thu nhỏ của WebView.

Bộ đọc hỗ trợ markup legacy trong hướng dẫn ban đầu, V1 có
`data-testid="whirl-inner-img"` / `whirl-outer-img`, và V2 nằm trong
`.captcha-verify-container` với ảnh trong `.cap-absolute`, thanh `.cap-rounded-full`
và nút kéo `div[draggable="true"]`. Selector V1/V2 được đối chiếu với
[client SadCaptcha chính thức](https://github.com/gbiz123/tiktok-captcha-solver/blob/master/src/tiktok_captcha_solver/selectors.py).
Ảnh chụp không cho biết DOM thực tế, nên chưa thể xác nhận phiên bản nào đang
hiển thị trên thiết bị chỉ từ ảnh.

App đo ảnh và thanh kéo trong đúng hộp đang hiện, lấy tâm nút mũi tên làm điểm
bắt đầu. `getBoundingClientRect()` đã tính CSS transform; sau đó app đổi qua
visual viewport và bounds WebView thật để Accessibility kéo đúng vị trí. Không
chọn nút draggable của video nền hoặc đóng/làm mới hộp CAPTCHA khi đang đọc.
Bộ tạm dừng nuôi và kiểm tra xác minh cũng nhận cả wrapper V1 lẫn V2.

Đã kiểm tra bằng DOM/CSS thật trong Chrome headless với hộp desktop thu nhỏ,
CSS transform, phần tử cũ bị ẩn và thanh kéo ngoài vùng nhìn thấy; kiểm thử
Flutter xác nhận đổi tọa độ CSS sang một WebView 318×636 pixel. Đây là kiểm thử
mô phỏng bố cục, chưa phải một lượt giải thành công trên CAPTCHA TikTok thật.
