module config

import audio
import core

pub struct AppConfig {
pub mut:
	engine           core.EngineConfig
	enable_cpu       bool = true
	enable_system    bool = true
	enable_network   bool = true
	log_events       bool
	debug_cpu        bool
	debug_fake_input bool
	audio_backend    string = 'miniaudio'
	profile          string = 'normal'
	master_volume    f32    = 1.0
	ambient_level    f32    = 1.0
	burst_density    f32    = 1.0
	synth            audio.SynthConfig
}

pub fn defaults() AppConfig {
	return AppConfig{}
}

pub fn with_profile(cfg AppConfig, profile_name string) AppConfig {
	profile := profile_name.to_lower()
	mut out := AppConfig{
		...cfg
		profile: profile
	}

	match profile {
		'calm' {
			out.engine = core.EngineConfig{
				...out.engine
				keyboard_threshold:        0.45
				mouse_threshold:           0.40
				keyboard_yip_intensity:    0.78
				keyboard_yip_chance:       0.24
				keyboard_chirp_chance:     0.14
				mouse_flick_intensity:     0.72
				mouse_flick_chance:        0.22
				mouse_click_zap_chance:    0.85
				cpu_active_cutoff:         0.18
				cpu_busy_cutoff:           0.72
				hum_active_max:            0.72
				hum_base_chance:           0.92
				hum_gain_scale:            0.62
				cpu_warble_active_chance:  0.10
				cpu_warble_busy_chance:    0.30
				process_threshold:         0.25
				memory_threshold:          0.30
				system_threshold:          0.34
				network_threshold:         0.28
				process_stutter_intensity: 0.66
				process_stutter_chance:    0.22
				memory_warble_intensity:   0.58
				memory_warble_chance:      0.16
				system_stutter_intensity:  0.62
				system_stutter_chance:     0.24
				network_chirp_intensity:   0.68
				network_chirp_chance:      0.30
				network_stutter_intensity: 0.80
				network_stutter_chance:    0.18
				min_gap_ms:                120
				cooldown_ms:               260
			}
			out.synth = audio.SynthConfig{
				...out.synth
				hum_freq_min:           62
				hum_freq_max:           108
				drone_freq_min:         48
				drone_freq_max:         84
				ambient_noise_chance:   0.55
				ambient_noise_gain:     0.07
				ambient_blip_chance:    0.48
				ambient_blip_gain:      0.08
				cluster_steps_min:      3
				cluster_steps_max:      9
				cluster_spacing_min_ms: 8
				cluster_spacing_max_ms: 20
			}
		}
		'noisy' {
			out.engine = core.EngineConfig{
				...out.engine
				keyboard_threshold:        0.15
				mouse_threshold:           0.12
				keyboard_yip_intensity:    0.60
				keyboard_yip_chance:       0.48
				keyboard_chirp_chance:     0.28
				mouse_flick_intensity:     0.48
				mouse_flick_chance:        0.44
				mouse_click_zap_chance:    1.00
				cpu_active_cutoff:         0.20
				cpu_busy_cutoff:           0.58
				hum_active_max:            0.52
				hum_base_chance:           0.44
				hum_gain_scale:            0.48
				cpu_warble_active_chance:  0.28
				cpu_warble_busy_chance:    0.56
				process_threshold:         0.09
				memory_threshold:          0.12
				system_threshold:          0.14
				network_threshold:         0.10
				process_stutter_intensity: 0.42
				process_stutter_chance:    0.46
				memory_warble_intensity:   0.30
				memory_warble_chance:      0.40
				system_stutter_intensity:  0.36
				system_stutter_chance:     0.50
				network_chirp_intensity:   0.42
				network_chirp_chance:      0.58
				network_stutter_intensity: 0.58
				network_stutter_chance:    0.44
				min_gap_ms:                40
				cooldown_ms:               110
			}
			out.synth = audio.SynthConfig{
				...out.synth
				hum_freq_min:           74
				hum_freq_max:           132
				drone_freq_min:         56
				drone_freq_max:         102
				wobble_freq_min:        96
				wobble_freq_max:        166
				ambient_noise_chance:   0.46
				ambient_noise_gain:     0.11
				ambient_blip_chance:    0.42
				ambient_blip_gain:      0.12
				cluster_steps_min:      4
				cluster_steps_max:      14
				cluster_spacing_min_ms: 4
				cluster_spacing_max_ms: 14
				stutter_steps_min:      3
				stutter_steps_max:      6
				stutter_spacing_min_ms: 9
				stutter_spacing_max_ms: 20
			}
		}
		else {
			out.engine = core.EngineConfig{
				...out.engine
				keyboard_threshold:        0.25
				mouse_threshold:           0.20
				keyboard_yip_intensity:    0.72
				keyboard_yip_chance:       0.38
				keyboard_chirp_chance:     0.20
				mouse_flick_intensity:     0.65
				mouse_flick_chance:        0.33
				mouse_click_zap_chance:    1.00
				cpu_active_cutoff:         0.22
				cpu_busy_cutoff:           0.62
				hum_active_max:            0.68
				hum_base_chance:           0.88
				hum_gain_scale:            0.58
				cpu_warble_active_chance:  0.18
				cpu_warble_busy_chance:    0.44
				process_threshold:         0.15
				memory_threshold:          0.18
				system_threshold:          0.20
				network_threshold:         0.16
				process_stutter_intensity: 0.55
				process_stutter_chance:    0.35
				memory_warble_intensity:   0.44
				memory_warble_chance:      0.28
				system_stutter_intensity:  0.50
				system_stutter_chance:     0.42
				network_chirp_intensity:   0.60
				network_chirp_chance:      0.46
				network_stutter_intensity: 0.72
				network_stutter_chance:    0.30
				min_gap_ms:                70
				cooldown_ms:               180
			}
			out.synth = audio.SynthConfig{
				...out.synth
				hum_freq_min:           68
				hum_freq_max:           118
				drone_freq_min:         52
				drone_freq_max:         92
				wobble_freq_min:        84
				wobble_freq_max:        140
				ambient_noise_chance:   0.40
				ambient_noise_gain:     0.08
				ambient_blip_chance:    0.36
				ambient_blip_gain:      0.10
				cluster_steps_min:      3
				cluster_steps_max:      12
				cluster_spacing_min_ms: 6
				cluster_spacing_max_ms: 16
				stutter_steps_min:      2
				stutter_steps_max:      5
				stutter_spacing_min_ms: 12
				stutter_spacing_max_ms: 26
			}
			out.profile = 'normal'
		}
	}

	return out
}
