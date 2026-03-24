module core

pub enum ActivityKind {
	keyboard
	mouse
	cpu
	process
	memory
	system
	network
}

pub enum CpuBucket {
	idle
	active
	busy
}

pub struct ActivitySample {
pub:
	kind       ActivityKind
	intensity  f32
	timestamp  i64
	source     string
	cpu_bucket CpuBucket = .idle
}

pub struct SoundEvent {
pub:
	motif       string
	gain        f32
	duration_ms int
	reason      string
	timestamp   i64
}

pub struct EngineConfig {
pub:
	keyboard_threshold        f32 = 0.25
	mouse_threshold           f32 = 0.20
	keyboard_yip_intensity    f32 = 0.72
	keyboard_yip_chance       f32 = 0.38
	keyboard_chirp_chance     f32 = 0.20
	mouse_flick_intensity     f32 = 0.65
	mouse_flick_chance        f32 = 0.33
	mouse_click_zap_chance    f32 = 1.00
	cpu_active_cutoff         f32 = 0.35
	cpu_busy_cutoff           f32 = 0.75
	hum_active_max            f32 = 0.58
	hum_base_chance           f32 = 0.52
	hum_gain_scale            f32 = 0.52
	cpu_warble_active_chance  f32 = 0.18
	cpu_warble_busy_chance    f32 = 0.44
	process_threshold         f32 = 0.15
	memory_threshold          f32 = 0.18
	system_threshold          f32 = 0.20
	network_threshold         f32 = 0.16
	process_stutter_intensity f32 = 0.55
	process_stutter_chance    f32 = 0.35
	memory_warble_intensity   f32 = 0.44
	memory_warble_chance      f32 = 0.28
	system_stutter_intensity  f32 = 0.50
	system_stutter_chance     f32 = 0.42
	network_chirp_intensity   f32 = 0.60
	network_chirp_chance      f32 = 0.46
	network_stutter_intensity f32 = 0.72
	network_stutter_chance    f32 = 0.30
	min_gap_ms                i64 = 70
	cooldown_ms               i64 = 180
}

pub struct EngineState {
mut:
	last_emit_ms   i64
	last_sample_ms i64
	last_motif     string
	activity_ema   f32
	rng_state      u32
}

pub fn new_state() EngineState {
	return EngineState{
		rng_state: 0x9E3779B9
	}
}
