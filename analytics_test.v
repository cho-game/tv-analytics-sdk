module analytics

import velo.core
import x.json2

fn test_build_batch_json_serialization() {
	events := [
		AnalyticsEvent{
			player_id:   'p_test123'
			session_id:  's_test456'
			name:        'level_complete'
			level:       1
			ts:          '2026-10-26T08:00:00.000Z'
			platform:    'macos'
			app_version: '1.0.0'
			country:     'VN'
			properties:  {
				'duration_s': PropValue(45)
				'stars':      PropValue(3)
				'score':      PropValue(1500)
			}
		},
		AnalyticsEvent{
			player_id:   'p_test123'
			session_id:  's_test456'
			name:        'level_fail'
			level:       2
			ts:          '2026-10-26T08:02:00.000Z'
			platform:    'macos'
			app_version: '1.0.0'
			properties:  {
				'duration_s': PropValue(30)
				'reason':     PropValue('timeout')
			}
		},
	]

	raw_json := build_batch_json(events)
	assert raw_json.contains('"events":')
	assert raw_json.contains('"name":"level_complete"')
	assert raw_json.contains('"player_id":"p_test123"')
	assert raw_json.contains('"level":1')
	assert raw_json.contains('"stars":3')
	assert raw_json.contains('"score":1500')
	assert raw_json.contains('"name":"level_fail"')
	assert raw_json.contains('"reason":"timeout"')

	// Parse JSON to verify valid format
	doc := json2.decode[json2.Any](raw_json) or { panic(err) }
	m := doc.as_map()
	evs := m['events'] or { panic('missing events') }.as_array()
	assert evs.len == 2
}

fn test_analytics_manager_init_and_queuing() {
	mut st := &core.Store{}
	mut a := get()

	a.init(mut st)
	assert a.is_inited == true
	assert a.player_id.starts_with('p_')
	assert a.session_id.starts_with('s_')
	assert st.get_string('analytics_player_id', '') == a.player_id

	// Verify install and session_start were queued
	a.mu.lock()
	initial_count := a.queue.len
	a.mu.unlock()
	assert initial_count >= 2

	// Track level start
	a.track_level_start(1)
	a.mu.lock()
	last_ev := a.queue.last()
	a.mu.unlock()
	assert last_ev.name == 'level_start'
	assert last_ev.level == 1

	// Track level complete
	a.track_level_complete(1, 42, 3, 1200)
	a.mu.lock()
	comp_ev := a.queue.last()
	a.mu.unlock()
	assert comp_ev.name == 'level_complete'
	assert comp_ev.level == 1
	stars_val := comp_ev.properties['stars'] or { PropValue(0) }
	assert stars_val == PropValue(3)
	dur_val := comp_ev.properties['duration_s'] or { PropValue(0) }
	assert dur_val == PropValue(42)

	// Track level fail
	a.track_level_fail(2, 35, 'timeout')
	a.mu.lock()
	fail_ev := a.queue.last()
	a.mu.unlock()
	assert fail_ev.name == 'level_fail'
	assert fail_ev.level == 2
	reason_val := fail_ev.properties['reason'] or { PropValue('') }
	assert reason_val == PropValue('timeout')
}
