# TV Analytics SDK for V & Velo

SDK phân tích và theo dõi sự kiện (Analytics Client SDK) đa nền tảng dành cho game và ứng dụng viết bằng ngôn ngữ [V](https://vlang.io) và engine [Velo](https://github.com/velo-engine).

Hỗ trợ native:
- **Desktop** (macOS, Windows, Linux) qua HTTP client bất đồng bộ (`net.http`).
- **Android** (tất cả kiến trúc arm64-v8a, armeabi-v7a, x86_64) qua JNI native `HttpURLConnection` (hoạt động độc lập, không cần thêm thư viện Java/Gradle bên ngoài).
- **Web / WebGL** qua C/JavaScript fetch với cơ chế `keepalive` đảm bảo gửi sự kiện ngay cả khi đóng tab.

---

## 1. Cài đặt

### Cách 1: Cài đặt qua Git trong `v.mod` (Khuyến nghị)

Thêm URL repository vào mảng `dependencies` trong file `v.mod` của dự án:

```v
Module {
	name: 'my_game'
	version: '1.0.0'
	dependencies: ['https://github.com/cho-game/tv-analytics-sdk']
}
```

Sau đó chạy lệnh cài đặt:

```bash
v install
```

Hoặc cài trực tiếp bằng CLI:

```bash
v install https://github.com/cho-game/tv-analytics-sdk
```

### Cách 2: Phát triển cục bộ bằng `v link`

Nếu bạn clone source code SDK về máy để chỉnh sửa hoặc phát triển:

```bash
git clone https://github.com/cho-game/tv-analytics-sdk
cd tv-analytics-sdk
v link
```

Lệnh `v link` sẽ tạo symlink `analytics` trong `~/.vmodules/`, cho phép bất kỳ dự án V nào trên máy tính có thể gọi `import analytics`.

### Cách 3: Copy trực tiếp thành local module

Copy toàn bộ thư mục `tv-analytics-sdk` thành thư mục `analytics/` nằm ngay tại thư mục gốc của dự án.

---

## 2. Cấu hình

Module tìm kiếm `server_url` và `api_key` theo thứ tự ưu tiên sau:
1. Tham số `Config` truyền trực tiếp khi gọi `analytics.init(mut store, Config{...})`
2. Biến môi trường hệ thống (`ANALYTICS_SERVER_URL`, `ANALYTICS_API_KEY`)
3. Giá trị đã lưu trong `core.Store` (`'analytics_server_url'`, `'analytics_api_key'`)
4. Cấu hình trong file `velo.toml` tại thư mục gốc dự án (cho Desktop)

### Cấu hình trong `velo.toml`

```toml
[analytics]
server_url = "https://analytics.vinazon.vn/api/events"
api_key = "pk_your_project_api_key_here"
```

### Lưu ý cho Mobile (Android / iOS)

Trên thiết bị di động thật, file `velo.toml` không nằm trong runtime filesystem. Bạn nên sử dụng kỹ thuật compile-time embedding của V (`$embed_file`) để nhúng cấu hình từ `velo.toml` trực tiếp vào binary lúc build:

```v
// src/analytics_config.v
module src

import analytics
import toml
import velo.core

const velo_toml_raw = $embed_file('../velo.toml').to_string()

pub fn init_analytics(mut store core.Store) {
	doc := toml.parse_text(velo_toml_raw) or {
		analytics.init(mut store)
		return
	}
	analytics.init(mut store, analytics.Config{
		server_url: doc.value('analytics.server_url').string()
		api_key:    doc.value('analytics.api_key').string()
	})
}
```

Khi được khởi tạo với `Config`, SDK sẽ tự động lưu lại vào `store` (`analytics_server_url`, `analytics_api_key`), giúp các scene sau đó hoặc các lần mở tiếp theo tự động tái sử dụng.

---

## 3. Cách sử dụng

### 3.1 Khởi tạo và cập nhật vòng lặp Game

Trong component mở đầu (như màn hình loading hoặc menu):

```v
import analytics
import velo.core

pub struct LoadingScreen {
    core.Component
}

pub fn (mut m LoadingScreen) start() {
    mut st := m.scene().store
    analytics.init(mut st) // hoặc gọi hàm init_analytics tùy biến ở trên
}

pub fn (mut m LoadingScreen) update(dt f32) {
    // Gọi mỗi frame để bộ đếm tự động flush theo batch (mặc định 15 giây/lần)
    analytics.update(dt)
}
```

Nếu không sử dụng `core.Store`, có thể gọi hàm khởi tạo tùy biến:

```v
analytics.init_custom(
    'https://analytics.vinazon.vn/api/events',
    'pk_your_api_key',
    'player_123', // hoặc để trống '' để tự động sinh UUID p_<uuid>
    '1.0.0'
)
```

### 3.2 Theo dõi các sự kiện Game

```v
import analytics

// 1. Màn chơi (Level)
analytics.track_level_start(1)
analytics.track_level_complete(1, duration_s, stars, score)
analytics.track_level_fail(1, duration_s, 'timeout')

// 2. Giao dịch mua vật phẩm (IAP)
analytics.track_purchase('gold_pack_medium', 1.99, level)

// 3. Quảng cáo (Ads)
analytics.track_ad_watched('rewarded_double_gold', 'rewarded_video', level)

// 4. Hoàn thành hướng dẫn tân thủ (Tutorial)
analytics.track_tutorial_complete(1)

// 5. Sự kiện tùy biến (Custom Event)
analytics.track_event('shop_buy', level, {
    'item_id':    analytics.PropValue('dynamite')
    'price_gold': analytics.PropValue(200)
    'success':    analytics.PropValue(true)
})
```

### 3.3 Vòng đời ứng dụng (Pause / Resume / Exit)

SDK tự động đăng ký `atexit` để ghi nhận `session_end` và flush đồng bộ khi thoát ứng dụng. Ngoài ra bạn có thể gọi thủ công khi game bị pause/resume:

```v
pub fn on_app_pause() {
    analytics.on_pause()
}

pub fn on_app_resume() {
    analytics.on_resume()
}
```

---

## 4. API Reference

| Hàm | Mô tả |
|---|---|
| `analytics.init(mut store, cfg ...Config)` | Khởi tạo SDK với Store và cấu hình tùy chọn |
| `analytics.init_custom(url, key, pid, ver)` | Khởi tạo trực tiếp không cần Store |
| `analytics.configure(url, key)` | Cập nhật URL server và API key |
| `analytics.update(dt)` | Cập nhật timer và tự động flush batch theo chu kỳ |
| `analytics.track_level_start(level)` | Bắt đầu màn chơi |
| `analytics.track_level_complete(level, duration, stars, score)` | Hoàn thành màn chơi |
| `analytics.track_level_fail(level, duration, reason)` | Thất bại màn chơi |
| `analytics.track_purchase(sku, price_usd, level)` | Mua vật phẩm |
| `analytics.track_ad_watched(placement, ad_type, level)` | Xem quảng cáo |
| `analytics.track_tutorial_complete(step)` | Hoàn thành bước hướng dẫn |
| `analytics.track_event(name, level, props)` | Bắn sự kiện tùy biến với properties map |
| `analytics.flush_sync()` | Gửi ngay lập tức toàn bộ sự kiện đang chờ |

---

## 5. Kiểm thử (Unit Tests)

```bash
v test .
```

---

## License

MIT License.
