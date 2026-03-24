module config

import audio
import core
import os
import strconv

fn parse_bool(v string) ?bool {
	value := v.trim_space().to_lower()
	if value in ['1', 'true', 'yes', 'on'] {
		return true
	}
	if value in ['0', 'false', 'no', 'off'] {
		return false
	}
	return none
}

fn parse_i64(v string) ?i64 {
	n := strconv.parse_int(v.trim_space(), 10, 64) or { return none }
	return n
}

fn parse_f32(v string) ?f32 {
	n := strconv.atof64(v.trim_space()) or { return none }
	return f32(n)
}

pub fn default_config_path() string {
	home := os.home_dir()
	if home == '' {
		return 'config/beep.conf'
	}
	return os.join_path(home, '.config', 'beep', 'config.conf')
}

pub fn load_file(path string, base AppConfig) !AppConfig {
	contents := os.read_file(path)!
	mut cfg := base

	for raw in contents.split_into_lines() {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}

		sep := line.index('=') or { continue }
		if sep <= 0 || sep >= line.len - 1 {
			continue
		}

		key := line[..sep].trim_space().to_lower()
		val := line[sep + 1..].trim_space()

		match key {
			'profile' {
				cfg = with_profile(cfg, val)
			}
			'debug_fake_input' {
				if b := parse_bool(val) {
					cfg.debug_fake_input = b
				}
			}
			'enable_cpu' {
				if b := parse_bool(val) {
					cfg.enable_cpu = b
				}
			}
			'enable_system' {
				if b := parse_bool(val) {
					cfg.enable_system = b
				}
			}
			'enable_network' {
				if b := parse_bool(val) {
					cfg.enable_network = b
				}
			}
			'log_events' {
				if b := parse_bool(val) {
					cfg.log_events = b
				}
			}
			'debug_cpu' {
				if b := parse_bool(val) {
					cfg.debug_cpu = b
				}
			}
			'audio_backend' {
				cfg.audio_backend = val
			}
			'keyboard_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						keyboard_threshold: x
					}
				}
			}
			'mouse_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						mouse_threshold: x
					}
				}
			}
			'keyboard_yip_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						keyboard_yip_intensity: x
					}
				}
			}
			'keyboard_yip_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						keyboard_yip_chance: x
					}
				}
			}
			'keyboard_chirp_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						keyboard_chirp_chance: x
					}
				}
			}
			'mouse_flick_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						mouse_flick_intensity: x
					}
				}
			}
			'mouse_flick_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						mouse_flick_chance: x
					}
				}
			}
			'mouse_click_zap_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						mouse_click_zap_chance: x
					}
				}
			}
			'cpu_active_cutoff' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						cpu_active_cutoff: x
					}
				}
			}
			'cpu_busy_cutoff' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						cpu_busy_cutoff: x
					}
				}
			}
			'hum_active_max' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						hum_active_max: x
					}
				}
			}
			'hum_base_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						hum_base_chance: x
					}
				}
			}
			'hum_gain_scale' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						hum_gain_scale: x
					}
				}
			}
			'cpu_warble_active_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						cpu_warble_active_chance: x
					}
				}
			}
			'cpu_warble_busy_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						cpu_warble_busy_chance: x
					}
				}
			}
			'process_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						process_threshold: x
					}
				}
			}
			'memory_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						memory_threshold: x
					}
				}
			}
			'system_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						system_threshold: x
					}
				}
			}
			'network_threshold' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						network_threshold: x
					}
				}
			}
			'process_stutter_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						process_stutter_intensity: x
					}
				}
			}
			'process_stutter_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						process_stutter_chance: x
					}
				}
			}
			'memory_warble_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						memory_warble_intensity: x
					}
				}
			}
			'memory_warble_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						memory_warble_chance: x
					}
				}
			}
			'system_stutter_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						system_stutter_intensity: x
					}
				}
			}
			'system_stutter_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						system_stutter_chance: x
					}
				}
			}
			'network_chirp_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						network_chirp_intensity: x
					}
				}
			}
			'network_chirp_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						network_chirp_chance: x
					}
				}
			}
			'network_stutter_intensity' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						network_stutter_intensity: x
					}
				}
			}
			'network_stutter_chance' {
				if x := parse_f32(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						network_stutter_chance: x
					}
				}
			}
			'hum_freq_min' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						hum_freq_min: x
					}
				}
			}
			'hum_freq_max' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						hum_freq_max: x
					}
				}
			}
			'drone_freq_min' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						drone_freq_min: x
					}
				}
			}
			'drone_freq_max' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						drone_freq_max: x
					}
				}
			}
			'wobble_freq_min' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						wobble_freq_min: x
					}
				}
			}
			'wobble_freq_max' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						wobble_freq_max: x
					}
				}
			}
			'ambient_noise_chance' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						ambient_noise_chance: x
					}
				}
			}
			'ambient_noise_gain' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						ambient_noise_gain: x
					}
				}
			}
			'ambient_blip_chance' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						ambient_blip_chance: x
					}
				}
			}
			'ambient_blip_gain' {
				if x := parse_f32(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						ambient_blip_gain: x
					}
				}
			}
			'cluster_steps_min' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						cluster_steps_min: int(x)
					}
				}
			}
			'cluster_steps_max' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						cluster_steps_max: int(x)
					}
				}
			}
			'cluster_spacing_min_ms' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						cluster_spacing_min_ms: int(x)
					}
				}
			}
			'cluster_spacing_max_ms' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						cluster_spacing_max_ms: int(x)
					}
				}
			}
			'stutter_steps_min' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						stutter_steps_min: int(x)
					}
				}
			}
			'stutter_steps_max' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						stutter_steps_max: int(x)
					}
				}
			}
			'stutter_spacing_min_ms' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						stutter_spacing_min_ms: int(x)
					}
				}
			}
			'stutter_spacing_max_ms' {
				if x := parse_i64(val) {
					cfg.synth = audio.SynthConfig{
						...cfg.synth
						stutter_spacing_max_ms: int(x)
					}
				}
			}
			'min_gap_ms' {
				if x := parse_i64(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						min_gap_ms: x
					}
				}
			}
			'cooldown_ms' {
				if x := parse_i64(val) {
					cfg.engine = core.EngineConfig{
						...cfg.engine
						cooldown_ms: x
					}
				}
			}
			else {}
		}
	}

	return cfg
}
