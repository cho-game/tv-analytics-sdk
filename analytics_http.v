module analytics

$if !android {
import net.http

fn send_desktop_http_post(url string, api_key string, json_body string) bool {
	mut req := http.Request{
		method: .post
		url:    url
		data:   json_body
	}
	req.add_custom_header('Content-Type', 'application/json') or { return false }
	req.add_custom_header('X-API-Key', api_key) or { return false }
	resp := req.do() or {
		eprintln('[Analytics] Network error: ${err}')
		return false
	}
	if resp.status_code == 200 {
		return true
	}
	eprintln('[Analytics] Server returned HTTP ${resp.status_code}: ${resp.body}')
	return false
}
} $else {
fn send_desktop_http_post(url string, api_key string, json_body string) bool {
	return false
}
}
