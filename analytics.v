module analytics

import math
import os
import rand
import sync
import time
import toml
import velo.core
import x.json2

// PropValue represents custom property values supported in analytics events.
pub type PropValue = bool | f64 | int | string

// AnalyticsEvent holds an individual analytics record conforming to the ingest API.
pub struct AnalyticsEvent {
pub mut:
	player_id   string
	session_id  string
	name        string
	ts          string
	platform    string
	app_version string
	country     string
	level       int = -1 // -1 means omitted
	properties  map[string]PropValue
}

fn to_json_any(v PropValue) json2.Any {
	return match v {
		int { json2.Any(v) }
		f64 { json2.Any(v) }
		bool { json2.Any(v) }
		string { json2.Any(v) }
	}
}

pub fn build_batch_json(events []AnalyticsEvent) string {
	mut ev_list := []json2.Any{cap: events.len}
	for e in events {
		mut item := map[string]json2.Any{}
		item['player_id'] = json2.Any(e.player_id)
		item['name'] = json2.Any(e.name)
		if e.session_id != '' {
			item['session_id'] = json2.Any(e.session_id)
		}
		if e.ts != '' {
			item['ts'] = json2.Any(e.ts)
		}
		if e.platform != '' {
			item['platform'] = json2.Any(e.platform)
		}
		if e.app_version != '' {
			item['app_version'] = json2.Any(e.app_version)
		}
		if e.country != '' {
			item['country'] = json2.Any(e.country)
		}
		if e.level >= 0 {
			item['level'] = json2.Any(e.level)
		}
		mut props := map[string]json2.Any{}
		for k, v in e.properties {
			props[k] = to_json_any(v)
		}
		item['properties'] = json2.Any(props)
		ev_list << json2.Any(item)
	}
	mut root := map[string]json2.Any{}
	root['events'] = json2.Any(ev_list)
	return json2.encode(root)
}

// AnalyticsManager manages event queuing, background batch flushing, and lifecycle tracking.
@[heap]
pub struct AnalyticsManager {
pub mut:
	server_url         string = 'https://analytics.vinazon.vn/api/events'
	api_key            string = 'YOUR_PROJECT_API_KEY'
	player_id          string
	session_id         string
	session_start_time i64
	platform           string
	app_version        string = '1.0.0'
	country            string
	flush_interval     f32    = 15.0
	max_batch_size     int    = 50
	max_queue_size     int    = 1000
	flush_timer        f32
	queue              []AnalyticsEvent
	is_sending         bool
	is_inited          bool
	has_exited         bool
	mu                 &sync.Mutex = sync.new_mutex()
}

const default_analytics = &AnalyticsManager{}

// get returns the shared AnalyticsManager singleton.
pub fn get() &AnalyticsManager {
	return default_analytics
}

// analytics returns the shared AnalyticsManager singleton.
pub fn analytics() &AnalyticsManager {
	return default_analytics
}

// init initializes analytics using settings from env, Store, or velo.toml.
pub fn init(mut store core.Store) {
	mut a := get()
	a.ensure_inited(mut store)
}

// analytics_init is an alias for init.
pub fn analytics_init(mut store core.Store) {
	init(mut store)
}

// init_custom allows initializing without a core.Store instance.
pub fn init_custom(url string, api_key string, player_id string, app_version string) {
	mut a := get()
	a.init_custom(url, api_key, player_id, app_version)
}

// update advances flush timer and flushes queued events when interval elapses.
pub fn update(dt f32) {
	mut a := get()
	a.update(dt)
}

// analytics_update is an alias for update.
pub fn analytics_update(dt f32) {
	update(dt)
}

pub fn track_event(name string, level int, properties map[string]PropValue) {
	mut a := get()
	a.track_event(name, level, properties)
}

pub fn track_level_start(level int) {
	mut a := get()
	a.track_level_start(level)
}

pub fn track_level_complete(level int, duration_s int, stars int, score int) {
	mut a := get()
	a.track_level_complete(level, duration_s, stars, score)
}

pub fn track_level_fail(level int, duration_s int, reason string) {
	mut a := get()
	a.track_level_fail(level, duration_s, reason)
}

pub fn track_purchase(sku string, price_usd f64, level int) {
	mut a := get()
	a.track_purchase(sku, price_usd, level)
}

pub fn track_ad_watched(placement string, ad_type string, level int) {
	mut a := get()
	a.track_ad_watched(placement, ad_type, level)
}

pub fn track_tutorial_complete(step int) {
	mut a := get()
	a.track_tutorial_complete(step)
}

pub fn on_pause() {
	mut a := get()
	a.on_pause()
}

pub fn on_resume() {
	mut a := get()
	a.on_resume()
}

pub fn on_app_exit() {
	mut a := get()
	a.on_app_exit()
}

pub fn flush_sync() {
	mut a := get()
	a.flush_sync()
}

pub fn trigger_flush() {
	mut a := get()
	a.trigger_flush()
}

fn C.atexit(cb fn ()) int

fn on_app_exit_callback() {
	mut a := get()
	a.on_app_exit()
}

fn current_platform() string {
	$if android {
		return 'android'
	} $else $if ios {
		return 'ios'
	} $else $if emscripten ? {
		return 'web'
	} $else $if macos {
		return 'macos'
	} $else $if windows {
		return 'windows'
	} $else $if linux {
		return 'linux'
	} $else {
		return 'desktop'
	}
}

fn read_velo_toml_setting(key string) string {
	for p in [
		'velo.toml',
		os.join_path(os.dir(@DIR), 'velo.toml'),
		os.join_path(os.dir(os.executable()), 'velo.toml'),
	] {
		if os.is_file(p) {
			doc := toml.parse_file(p) or { continue }
			val := doc.value(key).string()
			if val != '' {
				return val
			}
		}
	}
	return ''
}

// ensure_inited initializes AnalyticsManager if it hasn't been initialized yet.
pub fn (mut a AnalyticsManager) ensure_inited(mut store core.Store) {
	a.mu.lock()
	if a.is_inited {
		a.mu.unlock()
		return
	}
	a.mu.unlock()
	a.init(mut store)
}

// init loads configuration, identifies or creates persistent player_id, and fires install / session_start.
pub fn (mut a AnalyticsManager) init(mut store core.Store) {
	a.mu.lock()
	if a.is_inited {
		a.mu.unlock()
		return
	}
	a.mu.unlock()

	// 1. Determine Server URL
	mut url := os.getenv('ANALYTICS_SERVER_URL')
	if url == '' {
		url = store.get_string('analytics_server_url', '')
	}
	if url == '' {
		url = read_velo_toml_setting('analytics.server_url')
	}
	if url == '' {
		url = 'https://analytics.vinazon.vn/api/events'
	}

	// 2. Determine API Key
	mut key := os.getenv('ANALYTICS_API_KEY')
	if key == '' {
		key = store.get_string('analytics_api_key', '')
	}
	if key == '' {
		key = read_velo_toml_setting('analytics.api_key')
	}
	if key == '' {
		key = 'YOUR_PROJECT_API_KEY'
	}

	// 3. Platform & App Version
	plat := current_platform()
	mut ver := read_velo_toml_setting('app.version')
	if ver == '' {
		ver = '1.0.0'
	}

	// 4. Persistent Player ID
	mut pid := store.get_string('analytics_player_id', '')
	mut is_new := false
	if pid == '' {
		pid = 'p_' + rand.uuid_v4().replace('-', '')
		store.set_string('analytics_player_id', pid)
		store.save() or {}
		is_new = true
	}

	// 5. Session ID and start time
	sid := 's_' + rand.uuid_v4().replace('-', '')
	now_unix := time.now().unix()

	a.mu.lock()
	a.server_url = url
	a.api_key = key
	a.platform = plat
	a.app_version = ver
	a.player_id = pid
	a.session_id = sid
	a.session_start_time = now_unix
	a.is_inited = true
	a.mu.unlock()

	// Hook exit handler
	$if !emscripten ? {
		C.atexit(on_app_exit_callback)
	}

	// 6. Track initial install if first open
	if is_new {
		a.track_install()
	}

	// 7. Track session start
	a.track_session_start()
}

pub fn (mut a AnalyticsManager) init_custom(url string, api_key string, player_id string, app_version string) {
	a.mu.lock()
	if a.is_inited {
		a.mu.unlock()
		return
	}
	a.mu.unlock()

	plat := current_platform()
	sid := 's_' + rand.uuid_v4().replace('-', '')
	now_unix := time.now().unix()
	pid := if player_id != '' { player_id } else { 'p_' + rand.uuid_v4().replace('-', '') }
	ver := if app_version != '' { app_version } else { '1.0.0' }

	a.mu.lock()
	a.server_url = if url != '' { url } else { 'https://analytics.vinazon.vn/api/events' }
	a.api_key = if api_key != '' { api_key } else { 'YOUR_PROJECT_API_KEY' }
	a.platform = plat
	a.app_version = ver
	a.player_id = pid
	a.session_id = sid
	a.session_start_time = now_unix
	a.is_inited = true
	a.mu.unlock()

	$if !emscripten ? {
		C.atexit(on_app_exit_callback)
	}

	a.track_session_start()
}

// update advances the flush timer and flushes queued events when interval elapses.
pub fn (mut a AnalyticsManager) update(dt f32) {
	if !a.is_inited {
		return
	}
	a.flush_timer += dt
	if a.flush_timer >= a.flush_interval {
		a.flush_timer = 0
		a.trigger_flush()
	}
}

// track_event queues an event for batch ingestion.
pub fn (mut a AnalyticsManager) track_event(name string, level int, properties map[string]PropValue) {
	if !a.is_inited {
		return
	}
	ev := AnalyticsEvent{
		player_id:   a.player_id
		session_id:  a.session_id
		name:        name
		ts:          time.utc().format_rfc3339()
		platform:    a.platform
		app_version: a.app_version
		country:     a.country
		level:       level
		properties:  properties.clone()
	}

	a.mu.lock()
	a.queue << ev
	if a.queue.len > a.max_queue_size {
		a.queue.delete_many(0, a.queue.len - a.max_queue_size)
	}
	should_flush := a.queue.len >= a.max_batch_size
	a.mu.unlock()

	if should_flush {
		a.trigger_flush()
	}
}

// track_install records the first open of the game on this device.
pub fn (mut a AnalyticsManager) track_install() {
	mut props := map[string]PropValue{}
	props['first_open'] = PropValue(true)
	a.track_event('install', -1, props)
}

// track_session_start records game launch or foregrounding.
pub fn (mut a AnalyticsManager) track_session_start() {
	a.track_event('session_start', -1, map[string]PropValue{})
}

// track_session_end records session completion with elapsed duration.
pub fn (mut a AnalyticsManager) track_session_end(duration_s int) {
	mut props := map[string]PropValue{}
	props['duration_s'] = PropValue(math.max(0, duration_s))
	a.track_event('session_end', -1, props)
}

// track_level_start records player attempt start on a level.
pub fn (mut a AnalyticsManager) track_level_start(level int) {
	a.track_event('level_start', level, map[string]PropValue{})
}

// track_level_complete records successful completion of a level.
pub fn (mut a AnalyticsManager) track_level_complete(level int, duration_s int, stars int, score int) {
	mut props := map[string]PropValue{}
	props['duration_s'] = PropValue(math.max(0, duration_s))
	props['stars'] = PropValue(stars)
	if score > 0 {
		props['score'] = PropValue(score)
	}
	a.track_event('level_complete', level, props)
}

// track_level_fail records failed attempt or timeout on a level.
pub fn (mut a AnalyticsManager) track_level_fail(level int, duration_s int, reason string) {
	mut props := map[string]PropValue{}
	props['duration_s'] = PropValue(math.max(0, duration_s))
	props['reason'] = PropValue(reason)
	a.track_event('level_fail', level, props)
}

// track_purchase records an in-app purchase transaction.
pub fn (mut a AnalyticsManager) track_purchase(sku string, price_usd f64, level int) {
	mut props := map[string]PropValue{}
	props['sku'] = PropValue(sku)
	props['price_usd'] = PropValue(price_usd)
	a.track_event('purchase', level, props)
}

// track_ad_watched records an advertisement impression.
pub fn (mut a AnalyticsManager) track_ad_watched(placement string, ad_type string, level int) {
	mut props := map[string]PropValue{}
	props['placement'] = PropValue(placement)
	props['ad_type'] = PropValue(ad_type)
	a.track_event('ad_watched', level, props)
}

// track_tutorial_complete records tutorial progression.
pub fn (mut a AnalyticsManager) track_tutorial_complete(step int) {
	mut props := map[string]PropValue{}
	props['step'] = PropValue(step)
	a.track_event('tutorial_complete', -1, props)
}

// trigger_flush asynchronously flushes a batch of queued events in the background.
pub fn (mut a AnalyticsManager) trigger_flush() {
	a.mu.lock()
	if a.is_sending || a.queue.len == 0 {
		a.mu.unlock()
		return
	}
	a.is_sending = true
	count := if a.queue.len < a.max_batch_size { a.queue.len } else { a.max_batch_size }
	batch := a.queue[..count].clone()
	url := a.server_url
	key := a.api_key
	a.mu.unlock()

	$if emscripten ? {
		payload := build_batch_json(batch)
		send_web_event(url, key, payload)
		a.mu.lock()
		if a.queue.len >= count {
			a.queue.delete_many(0, count)
		}
		a.is_sending = false
		a.mu.unlock()
	} $else {
		spawn send_worker(mut a, batch, count, url, key)
	}
}

fn send_worker(mut mgr AnalyticsManager, batch []AnalyticsEvent, count int, url string, key string) {
	payload := build_batch_json(batch)
	ok := send_http_post(url, key, payload)
	mgr.mu.lock()
	if ok {
		if mgr.queue.len >= count {
			mgr.queue.delete_many(0, count)
		}
	} else {
		eprintln('[Analytics] Flush failed, ${count} events will retry on next interval')
	}
	mgr.is_sending = false
	mgr.mu.unlock()
}

// flush_sync synchronously flushes queued events (used on quit or pause).
pub fn (mut a AnalyticsManager) flush_sync() {
	a.mu.lock()
	if a.queue.len == 0 {
		a.mu.unlock()
		return
	}
	count := if a.queue.len < a.max_batch_size { a.queue.len } else { a.max_batch_size }
	batch := a.queue[..count].clone()
	url := a.server_url
	key := a.api_key
	a.mu.unlock()

	payload := build_batch_json(batch)
	$if emscripten ? {
		send_web_event(url, key, payload)
	} $else $if android {
		spawn send_worker(mut a, batch, count, url, key)
	} $else {
		ok := send_http_post(url, key, payload)
		if ok {
			a.mu.lock()
			if a.queue.len >= count {
				a.queue.delete_many(0, count)
			}
			a.mu.unlock()
		}
	}
}

// on_pause handles game suspension: records session duration and triggers a flush.
pub fn (mut a AnalyticsManager) on_pause() {
	if !a.is_inited {
		return
	}
	duration := int(time.now().unix() - a.session_start_time)
	a.track_session_end(duration)
	a.flush_sync()
}

// on_resume handles game foregrounding: starts a new session ID.
pub fn (mut a AnalyticsManager) on_resume() {
	if !a.is_inited {
		return
	}
	sid := 's_' + rand.uuid_v4().replace('-', '')
	a.mu.lock()
	a.session_id = sid
	a.session_start_time = time.now().unix()
	a.mu.unlock()
	a.track_session_start()
}

// on_app_exit records session_end and performs a synchronous flush.
pub fn (mut a AnalyticsManager) on_app_exit() {
	a.mu.lock()
	if !a.is_inited || a.has_exited {
		a.mu.unlock()
		return
	}
	a.has_exited = true
	a.mu.unlock()

	duration := int(time.now().unix() - a.session_start_time)
	a.track_session_end(duration)
	a.flush_sync()
}

fn send_http_post(url string, api_key string, json_body string) bool {
	$if android {
		return send_android_http_post(url, api_key, json_body)
	} $else {
		return send_desktop_http_post(url, api_key, json_body)
	}
}

fn send_web_event(url string, api_key string, json_body string) {
	$if emscripten ? {
		// For web builds, fetch with keepalive ensures events are sent even during tab dismiss
		C.velo_analytics_post(&char(url.str), &char(api_key.str), &char(json_body.str))
	}
}
