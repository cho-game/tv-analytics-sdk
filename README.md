# Analytics Module for V / Velo

Module phân tích (Analytics tracking) đa nền tảng cho game và ứng dụng Velo / V (hỗ trợ macOS, Windows, Linux, Android qua JNI HTTP native, và WebGL qua keepalive fetch).

---

## 1. Cách copy sang dự án khác

Chỉ cần copy toàn bộ thư mục `analytics/` vào thư mục gốc của dự án mới:

```bash
# Giả sử bạn đang ở thư mục gốc của dự án mới:
cp -r /path/to/gold-digger/analytics ./analytics
```

Cấu trúc thư mục dự án mới sau khi copy:
```
my-game/
├── v.mod
├── velo.toml
├── main.v
├── src/
│   ├── ...
└── analytics/              <-- Thư mục module được copy vào đây
    ├── v.mod
    ├── analytics.v
    ├── analytics_http.v
    ├── analytics_android.c.v
    ├── analytics_android.h
    ├── analytics_test.v
    └── README.md
```

---

## 2. Cấu hình

Module tự động tìm kiếm cấu hình theo thứ tự ưu tiên:
1. Biến môi trường (`ANALYTICS_SERVER_URL`, `ANALYTICS_API_KEY`)
2. Giá trị lưu trong `core.Store` (`analytics_server_url`, `analytics_api_key`)
3. File cấu hình `velo.toml` trong thư mục dự án

Ví dụ thêm vào `velo.toml` của dự án:

```toml
[analytics]
server_url = "https://analytics.vinazon.vn/api/events"
api_key = "pk_your_project_api_key_here"
```

---

## 3. Cách sử dụng

### Khởi tạo & Cập nhật vòng lặp game

Trong màn hình khởi động (như `loading.v` hoặc `menu.v`):

```v
import analytics
import velo.core

// Khởi tạo trong fn start() của component
pub fn (mut m MyScreen) start() {
    mut st := m.scene().store
    analytics.init(mut st)
}

// Cập nhật bộ đếm flush theo chu kỳ trong update(dt)
pub fn (mut m MyScreen) update(dt f32) {
    analytics.update(dt)
}
```

Nếu không sử dụng `core.Store`, có thể gọi hàm khởi tạo tùy biến:

```v
analytics.init_custom(
    'https://analytics.vinazon.vn/api/events',
    'pk_your_api_key',
    'player_123', // hoặc để trống '' để tự động sinh UUID
    '1.0.0'
)
```

### Theo dõi sự kiện Game

```v
import analytics

// Bắt đầu màn chơi
analytics.track_level_start(level)

// Hoàn thành màn chơi
analytics.track_level_complete(level, duration_s, stars, score)

// Thua / thất bại màn chơi
analytics.track_level_fail(level, duration_s, 'out_of_time')

// Xem quảng cáo
analytics.track_ad_watched('rewarded_double_gold', 'rewarded_video', level)

// Giao dịch mua vật phẩm
analytics.track_purchase('gold_pack_large', 4.99, level)

// Hoàn thành hướng dẫn
analytics.track_tutorial_complete(step)

// Sự kiện tùy biến
analytics.track_event('shop_buy', level, {
    'item_id':    analytics.PropValue('dynamite')
    'price_gold': analytics.PropValue(200)
    'success':    analytics.PropValue(true)
})
```

---

## 4. Chạy kiểm thử (Unit tests)

Chạy test cho riêng module analytics:

```bash
v test analytics/
```
