module analytics

$if android {
	#flag -I @DIR
	#include "@DIR/analytics_android.h"

	fn C.velo_android_http_post(&char, &char, &char) int

	fn send_android_http_post(url string, api_key string, json_body string) bool {
		res := C.velo_android_http_post(&char(url.str), &char(api_key.str), &char(json_body.str))
		return res == 1
	}
} $else {
	fn send_android_http_post(url string, api_key string, json_body string) bool {
		return false
	}
}
