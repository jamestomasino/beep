module core

fn clamp01(v f32) f32 {
	if v < 0.0 {
		return 0.0
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

fn clamp_gain(v f32) f32 {
	if v < 0.03 {
		return 0.03
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

fn next_rand(mut state EngineState) u32 {
	state.rng_state = state.rng_state * 1664525 + 1013904223
	return state.rng_state
}

fn rand01(mut state EngineState) f32 {
	return f32(next_rand(mut state) & 0xFFFF) / 65535.0
}

fn choose_motif(mut state EngineState, options []string) string {
	if options.len == 0 {
		return 'bip'
	}
	return options[int(next_rand(mut state) % u32(options.len))]
}

fn base_duration_for_motif(motif string) int {
	return match motif {
		'drone' { 7000 }
		'hum' { 6200 }
		'pad' { 9000 }
		'wobble' { 180 }
		'whirr' { 100 }
		'wheee' { 130 }
		'warble' { 130 }
		'cluster' { 40 }
		'stutter' { 70 }
		'run' { 52 }
		'tick' { 24 }
		'tsk' { 30 }
		'zap' { 24 }
		'yip' { 32 }
		'chirp' { 34 }
		'bloop' { 58 }
		else { 42 }
	}
}

pub fn map_activity(mut state EngineState, cfg EngineConfig, sample ActivitySample) ?SoundEvent {
	now_ms := sample.timestamp
	mut dt := i64(60)
	if state.last_sample_ms > 0 {
		dt = now_ms - state.last_sample_ms
	}
	if dt < 10 {
		dt = 10
	}
	if dt > 1000 {
		dt = 1000
	}
	state.last_sample_ms = now_ms

	alpha := clamp01(f32(dt) / 220.0)
	state.activity_ema = state.activity_ema * (1.0 - alpha) + clamp01(sample.intensity) * alpha
	density := clamp01(if sample.intensity > state.activity_ema {
		sample.intensity
	} else {
		state.activity_ema
	})

	mut motif := ''
	mut reason := ''
	mut gain := sample.intensity
	mut duration := 55

	match sample.kind {
		.keyboard {
			if sample.intensity < cfg.keyboard_threshold {
				return none
			}
			mut options := ['bip', 'chirp', 'tick', 'cluster', 'run']
			if sample.intensity > cfg.keyboard_yip_intensity
				&& rand01(mut state) < clamp01(cfg.keyboard_yip_chance) {
				options << 'yip'
				options << 'stutter'
			}
			if rand01(mut state) < clamp01(cfg.keyboard_chirp_chance) {
				options << 'chirp'
			}
			motif = choose_motif(mut state, options)
			reason = 'keyboard variety'
		}
		.mouse {
			if sample.intensity < cfg.mouse_threshold {
				return none
			}
			mut options := ['bip', 'chirp', 'tick', 'cluster', 'run', 'bloop']
			if sample.intensity > cfg.mouse_flick_intensity
				&& rand01(mut state) < clamp01(cfg.mouse_flick_chance) {
				options << 'yip'
				options << 'stutter'
			}
			if (sample.source.contains('click') || sample.source.contains('press'))
				&& rand01(mut state) < clamp01(cfg.mouse_click_zap_chance) {
				options << 'zap'
				options << 'zap'
			}
			motif = choose_motif(mut state, options)
			reason = 'mouse variety'
		}
		.cpu {
			gain = if sample.intensity < cfg.cpu_active_cutoff {
				cfg.cpu_active_cutoff
			} else {
				sample.intensity
			}
			match sample.cpu_bucket {
				.idle {
					if rand01(mut state) > clamp01(cfg.hum_base_chance * 0.60) {
						return none
					}
					motif = choose_motif(mut state, ['drone', 'hum', 'pad', 'warble'])
					gain = 0.07 + sample.intensity * 0.24
					reason = 'cpu idle variety'
				}
				.active {
					motif = choose_motif(mut state, ['whirr', 'warble', 'cluster', 'run', 'tick', 'hum', 'drone', 'pad',
						'wobble'])
					gain = if sample.intensity < cfg.cpu_active_cutoff {
						cfg.cpu_active_cutoff
					} else {
						sample.intensity
					}
					reason = 'cpu active variety'
				}
				.busy {
					motif = choose_motif(mut state, ['wheee', 'warble', 'stutter', 'cluster', 'run', 'zap', 'whirr',
						'wobble'])
					gain = if sample.intensity < cfg.cpu_busy_cutoff {
						cfg.cpu_busy_cutoff
					} else {
						sample.intensity
					}
					reason = 'cpu busy variety'
				}
			}
		}
		.process {
			if sample.intensity < cfg.process_threshold {
				return none
			}
			motif = choose_motif(mut state, ['tick', 'cluster', 'stutter', 'run', 'chirp', 'bip', 'wobble'])
			reason = 'process variety'
		}
		.memory {
			if sample.intensity < cfg.memory_threshold {
				return none
			}
			motif = choose_motif(mut state, ['tsk', 'warble', 'cluster', 'run', 'chirp', 'bloop', 'wobble'])
			reason = 'memory variety'
		}
		.system {
			if sample.intensity < cfg.system_threshold {
				return none
			}
			motif = choose_motif(mut state, ['tick', 'stutter', 'cluster', 'run', 'bip', 'tsk', 'wobble'])
			gain = sample.intensity * 0.85
			reason = 'system variety'
		}
		.network {
			if sample.intensity < cfg.network_threshold {
				return none
			}
			motif = choose_motif(mut state, ['tsk', 'chirp', 'stutter', 'cluster', 'run', 'zap', 'bip', 'wobble'])
			gain = sample.intensity * 0.95
			reason = 'network variety'
		}
	}
	duration = base_duration_for_motif(motif)

	mut drop_chance := clamp01(0.40 - density * 0.25)
	if motif == 'hum' || motif == 'drone' || motif == 'wobble' || motif == 'pad' {
		drop_chance = clamp01(0.22 - density * 0.10)
	} else if motif == 'tick' || motif == 'tsk' {
		drop_chance = clamp01(drop_chance - 0.18)
	}
	if drop_chance > 0 && f32(next_rand(mut state) & 0xFFFF) / 65535.0 < drop_chance {
		return none
	}

	mut effective_gap := cfg.min_gap_ms - i64(f32(cfg.min_gap_ms) * density * 0.82)
	jitter := i64(int(next_rand(mut state) % 17) - 8)
	effective_gap += jitter
	if effective_gap < 12 {
		effective_gap = 12
	}
	if now_ms - state.last_emit_ms < effective_gap {
		return none
	}

	mut motif_cooldown := i64(f32(cfg.cooldown_ms) * (1.0 - density))
	if motif_cooldown < 8 {
		motif_cooldown = 8
	}
	if motif == 'hum' || motif == 'drone' || motif == 'wobble' || motif == 'pad' {
		motif_cooldown = motif_cooldown * 2
	}
	if motif == state.last_motif && now_ms - state.last_emit_ms < motif_cooldown && density < 0.86 {
		return none
	}

	dur_scale := clamp01(1.0 - density * 0.34)
	min_scale := if motif == 'hum' || motif == 'drone' || motif == 'wobble' || motif == 'pad' {
		f32(0.82)
	} else {
		f32(0.58)
	}
	duration = int(f32(duration) * if dur_scale < min_scale { min_scale } else { dur_scale })
	if duration < 16 {
		duration = 16
	}

	state.last_emit_ms = now_ms
	state.last_motif = motif
	return SoundEvent{
		motif:       motif
		gain:        clamp_gain(gain)
		duration_ms: duration
		reason:      reason
		timestamp:   now_ms
	}
}
