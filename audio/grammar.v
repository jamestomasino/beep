module audio

import core

pub struct VoiceLayer {
pub:
	waveform    int
	freq0       f32
	freq1       f32
	gain_mul    f32
	duration_ms int
	delay_ms    int
}

struct Rng {
mut:
	state u32
}

fn new_rng(seed u32) Rng {
	return Rng{
		state: if seed == 0 { u32(0xC0FFEE11) } else { seed }
	}
}

fn (mut r Rng) next_u32() u32 {
	r.state = r.state * 1664525 + 1013904223
	return r.state
}

fn (mut r Rng) next_f32() f32 {
	return f32((r.next_u32() >> 8) & 0x00ffffff) / f32(0x01000000)
}

fn (mut r Rng) range_f32(min f32, max f32) f32 {
	return min + (max - min) * r.next_f32()
}

fn (mut r Rng) chance(p f32) bool {
	mut v := p
	if v < 0.0 {
		v = 0.0
	}
	if v > 1.0 {
		v = 1.0
	}
	return r.next_f32() < v
}

fn clamp01(v f32) f32 {
	if v < 0.0 {
		return 0.0
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

fn clamp_i(v int, lo int, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

fn motif_hash(s string) u32 {
	mut h := u32(2166136261)
	for b in s.bytes() {
		h ^= b
		h *= 16777619
	}
	return h
}

pub fn plan_layers(event core.SoundEvent, synth_cfg SynthConfig) []VoiceLayer {
	mut out := []VoiceLayer{}
	base_dur := if event.duration_ms > 0 { event.duration_ms } else { 60 }
	energy := clamp01(event.gain)
	seed := u32(event.timestamp) ^ motif_hash(event.motif) ^ (u32(base_dur) << 10)
	mut rng := new_rng(seed)

	match event.motif {
		'bip' {
			f := rng.range_f32(740, 980)
			mut main_dur := int(f32(base_dur) * rng.range_f32(0.55, 1.55))
			if main_dur < 14 {
				main_dur = 14
			}
			out << VoiceLayer{0, f, f * rng.range_f32(0.96, 1.03), 0.90, main_dur, 0}
			// Sometimes hold a slightly longer sine tail instead of pure staccato.
			if rng.chance(0.34 + energy * 0.20) {
				mut tail_dur := int(f32(base_dur) * rng.range_f32(1.20, 3.20))
				if tail_dur > 220 {
					tail_dur = 220
				}
				out << VoiceLayer{0, f * rng.range_f32(0.98, 1.01), f * rng.range_f32(0.98, 1.01), 0.20,
					tail_dur, 6}
			}
			if rng.chance(0.45 + energy * 0.30) {
				out << VoiceLayer{1, f * 1.99, f * 1.8, 0.20, int(f32(base_dur) * 0.55), int(rng.next_u32() % 12)}
			}
			if rng.chance(0.25 + energy * 0.40) {
				out << VoiceLayer{4, 1800, 1200, 0.12, 18, 4 + int(rng.next_u32() % 8)}
			}
		}
		'yip' {
			f0 := rng.range_f32(520, 760)
			f1 := rng.range_f32(1250, 1900)
			mut main_dur := int(f32(base_dur) * rng.range_f32(0.50, 1.35))
			if main_dur < 12 {
				main_dur = 12
			}
			out << VoiceLayer{0, f0, f1, 0.84, main_dur, 0}
			if rng.chance(0.24 + energy * 0.25) {
				out << VoiceLayer{0, f1 * 0.92, f1 * 0.92, 0.16, 40 + int(rng.next_u32() % 120), 8}
			}
			if rng.chance(0.35 + energy * 0.45) {
				out << VoiceLayer{4, 2100, 1400, 0.16, 14, 1}
			}
		}
		'chirp' {
			f0 := rng.range_f32(880, 1320)
			f1 := rng.range_f32(620, 980)
			mut main_dur := int(f32(base_dur) * rng.range_f32(0.55, 1.65))
			if main_dur < 12 {
				main_dur = 12
			}
			out << VoiceLayer{0, f0, f1, 0.62, main_dur, 0}
			if rng.chance(0.28 + energy * 0.18) {
				hold := 56 + int(rng.next_u32() % 140)
				out << VoiceLayer{0, f1 * 0.96, f1 * 0.96, 0.18, hold, 10}
			}
			out << VoiceLayer{1, f0 * 1.4, f1 * 1.1, 0.14, int(f32(base_dur) * 0.50), 3}
			if rng.chance(0.25 + energy * 0.35) {
				out << VoiceLayer{4, 2200, 900, 0.10, 12, 0}
			}
		}
		'bloop' {
			f0 := rng.range_f32(520, 760)
			f1 := rng.range_f32(180, 340)
			out << VoiceLayer{0, f0, f1, 0.82, int(f32(base_dur) * 1.15), 0}
			if rng.chance(0.55) {
				out << VoiceLayer{3, f0 * 0.8, f1 * 0.7, 0.10, int(f32(base_dur) * 0.55), 9}
			}
			if rng.chance(0.20 + energy * 0.3) {
				out << VoiceLayer{4, 1400, 800, 0.10, 20, 2}
			}
		}
		'zap' {
			f0 := rng.range_f32(1900, 2600)
			f1 := rng.range_f32(260, 520)
			out << VoiceLayer{3, f0, f1, 0.76, int(f32(base_dur) * 0.65), 0}
			out << VoiceLayer{0, f0 * 0.7, f1 * 0.9, 0.32, int(f32(base_dur) * 0.75), 0}
			out << VoiceLayer{4, 2600, 1000, 0.22, 12, 0}
			if rng.chance(0.50) {
				out << VoiceLayer{4, 1400, 700, 0.10, 10, 7}
			}
		}
		'whirr' {
			f0 := rng.range_f32(95, 160)
			f1 := f0 + rng.range_f32(25, 80)
			bed := 0.40 + (energy * 0.72)
			out << VoiceLayer{2, f0, f1, bed, int(f32(base_dur) * 1.8), 0}
			out << VoiceLayer{0, f0 * 0.5, f1 * 0.6, bed * 0.38, int(f32(base_dur) * 1.6), 0}
			if rng.chance(0.35 + energy * 0.5) {
				out << VoiceLayer{3, f0 * 2.5, f1 * 3.0, bed * 0.16, int(f32(base_dur) * 1.2), 7}
			}
		}
		'warble' {
			f0 := rng.range_f32(180, 420)
			f1 := rng.range_f32(460, 920)
			out << VoiceLayer{0, f0, f1, 0.58, int(f32(base_dur) * 1.3), 0}
			out << VoiceLayer{0, f1, f0, 0.22, int(f32(base_dur) * 1.1), 14}
			out << VoiceLayer{1, f0 * 1.95, f1 * 1.70, 0.10, int(f32(base_dur) * 0.9), 6}
			if rng.chance(0.42) {
				out << VoiceLayer{3, f0 * 2.8, f1 * 2.3, 0.10, int(f32(base_dur) * 0.65), 22}
			}
		}
		'hum' {
			f0 := rng.range_f32(synth_cfg.hum_freq_min, synth_cfg.hum_freq_max)
			// Ambient bed should stay close to pitch-stable.
			drift := rng.range_f32(-1.2, 1.6)
			f1 := f0 + drift
			base := 0.32 + energy * 0.56
			out << VoiceLayer{0, f0, f1, base, int(f32(base_dur) * 1.0), 0}
			out << VoiceLayer{2, f0 * 2.0, f1 * 2.15, base * 0.22, int(f32(base_dur) * 1.0), 0}
			if rng.chance(0.30 + energy * 0.42) {
				out << VoiceLayer{3, f0 * 5.0, f1 * 5.4, base * 0.10, int(f32(base_dur) * 1.0), 320}
			}
			if rng.chance(clamp01(synth_cfg.ambient_noise_chance)) {
				noise_gain := base * synth_cfg.ambient_noise_gain
				out << VoiceLayer{4, rng.range_f32(950, 1450), rng.range_f32(650, 980), noise_gain, 120,
					600 + int(rng.next_u32() % 800)}
			}
			if rng.chance(clamp01(synth_cfg.ambient_blip_chance)) {
				blip_gain := base * synth_cfg.ambient_blip_gain
				out << VoiceLayer{0, rng.range_f32(380, 620), rng.range_f32(300, 560), blip_gain, 260,
					420 + int(rng.next_u32() % 900)}
			}
		}
		'pad' {
			// Very soft, very long ambient bed with stable low tones.
			f0 := rng.range_f32(synth_cfg.drone_freq_min * 0.85, synth_cfg.hum_freq_max * 0.95)
			base := 0.16 + energy * 0.22
			pad_dur := int(f32(base_dur) * rng.range_f32(0.9, 1.8))
			out << VoiceLayer{0, f0, f0, base, pad_dur, 0}
			out << VoiceLayer{0, f0 * 1.5, f0 * 1.5, base * 0.22, int(f32(pad_dur) * 0.95), 180}
			out << VoiceLayer{2, f0 * 0.5, f0 * 0.5, base * 0.10, int(f32(pad_dur) * 1.05), 0}
			if rng.chance(clamp01(synth_cfg.ambient_noise_chance * 0.20)) {
				out << VoiceLayer{3, f0 * 3.8, f0 * 3.8, base * 0.05, int(f32(pad_dur) * 0.75), 320}
			}
		}
		'drone' {
			f0 := rng.range_f32(synth_cfg.drone_freq_min, synth_cfg.drone_freq_max)
			// Keep drones pitch-stable; movement should come from texture layers.
			f1 := f0
			base := 0.34 + energy * 0.48
			out << VoiceLayer{0, f0, f1, base, int(f32(base_dur) * 1.0), 0}
			out << VoiceLayer{2, f0 * 1.5, f1 * 1.8, base * 0.16, int(f32(base_dur) * 1.0), 0}
			out << VoiceLayer{3, f0 * 4.0, f1 * 4.6, base * 0.08, int(f32(base_dur) * 1.0), 420}
			if rng.chance(clamp01(synth_cfg.ambient_noise_chance * 0.50)) {
				noise_gain := base * synth_cfg.ambient_noise_gain
				out << VoiceLayer{4, rng.range_f32(820, 1180), rng.range_f32(620, 940), noise_gain, 140,
					900 + int(rng.next_u32() % 1200)}
			}
			if rng.chance(clamp01(synth_cfg.ambient_blip_chance * 0.40)) {
				blip_gain := base * synth_cfg.ambient_blip_gain
				out << VoiceLayer{0, rng.range_f32(260, 420), rng.range_f32(220, 380), blip_gain, 240,
					720 + int(rng.next_u32() % 1000)}
			}
		}
		'wobble' {
			f0 := rng.range_f32(synth_cfg.wobble_freq_min, synth_cfg.wobble_freq_max)
			f1 := f0 + rng.range_f32(28, 88)
			base := 0.24 + energy * 0.42
			out << VoiceLayer{0, f0, f1, base, int(f32(base_dur) * 0.95), 0}
			out << VoiceLayer{0, f1, f0, base * 0.34, int(f32(base_dur) * 0.72), 8}
			out << VoiceLayer{2, f0 * 2.2, f1 * 2.0, base * 0.10, int(f32(base_dur) * 0.60), 0}
			if rng.chance(0.24 + energy * 0.24) {
				out << VoiceLayer{4, rng.range_f32(900, 1500), rng.range_f32(650, 980), base * 0.08, 24,
					4 + int(rng.next_u32() % 16)}
			}
		}
		'wheee' {
			f0 := rng.range_f32(250, 430)
			f1 := rng.range_f32(900, 1600)
			out << VoiceLayer{0, f0, f1, 0.80, int(f32(base_dur) * 1.35), 0}
			if rng.chance(0.70) {
				out << VoiceLayer{1, f0 * 0.98, f1 * 0.75, 0.16, int(f32(base_dur) * 0.9), 10}
			}
			if rng.chance(0.42) {
				out << VoiceLayer{4, 1900, 900, 0.10, 16, 3}
			}
		}
		'stutter' {
			min_steps := clamp_i(synth_cfg.stutter_steps_min, 1, 12)
			max_steps := clamp_i(synth_cfg.stutter_steps_max, min_steps, 16)
			steps := min_steps + int(rng.next_u32() % u32(max_steps - min_steps + 1))
			spacing_lo := clamp_i(synth_cfg.stutter_spacing_min_ms, 2, 100)
			spacing_hi := clamp_i(synth_cfg.stutter_spacing_max_ms, spacing_lo, 150)
			base_f := rng.range_f32(820, 1650)
			mut acc_delay := 0
			for i in 0 .. steps {
				j := f32(i)
				mut step_ms := spacing_lo + int(rng.next_u32() % u32(spacing_hi - spacing_lo + 1))
				// Occasional ratchet (very fast repeats) and occasional breath (small pause).
				if rng.chance(0.24) {
					step_ms = 1 + int(rng.next_u32() % 3)
				} else if rng.chance(0.16) {
					step_ms += 6 + int(rng.next_u32() % 10)
				}
				acc_delay += step_ms
				out << VoiceLayer{
					waveform:    0
					freq0:       base_f + j * rng.range_f32(55, 160)
					freq1:       base_f + j * rng.range_f32(20, 110)
					gain_mul:    0.24 + energy * 0.48 - j * 0.035
					duration_ms: 8 + int(rng.next_u32() % 10)
					delay_ms:    acc_delay
				}
			}
		}
		'cluster' {
			min_steps := clamp_i(synth_cfg.cluster_steps_min, 2, 16)
			max_steps := clamp_i(synth_cfg.cluster_steps_max, min_steps, 24)
			steps := min_steps + int(rng.next_u32() % u32(max_steps - min_steps + 1))
			spacing_lo := clamp_i(synth_cfg.cluster_spacing_min_ms, 1, 80)
			spacing_hi := clamp_i(synth_cfg.cluster_spacing_max_ms, spacing_lo, 120)
			base_f := rng.range_f32(900, 2100)
			mut acc_delay := 0
			for i in 0 .. steps {
				j := f32(i)
				mut step_ms := spacing_lo + int(rng.next_u32() % u32(spacing_hi - spacing_lo + 1))
				if rng.chance(0.32) {
					step_ms = 1 + int(rng.next_u32() % 3)
				} else if rng.chance(0.18) {
					step_ms += 5 + int(rng.next_u32() % 9)
				}
				acc_delay += step_ms
				out << VoiceLayer{
					waveform:    0
					freq0:       base_f + j * rng.range_f32(20, 140)
					freq1:       base_f + j * rng.range_f32(10, 90)
					gain_mul:    0.20 + energy * 0.42 - j * 0.028
					duration_ms: 6 + int(rng.next_u32() % 8)
					delay_ms:    acc_delay
				}
			}
		}
		'run' {
			// Pure sine calculation-run: tightly coupled notes with timing variation.
			steps := 5 + int(rng.next_u32() % 14)
			base_f := rng.range_f32(780, 1750)
			mut acc_delay := 0
			for i in 0 .. steps {
				j := f32(i)
				mut step_ms := 1 + int(rng.next_u32() % 7)
				if rng.chance(0.26) {
					step_ms = 1 + int(rng.next_u32() % 3)
				} else if rng.chance(0.15) {
					step_ms += 6 + int(rng.next_u32() % 12)
				}
				acc_delay += step_ms
				fa := base_f + j * rng.range_f32(14, 120)
				out << VoiceLayer{
					waveform:    0
					freq0:       fa
					freq1:       fa * rng.range_f32(0.99, 1.02)
					gain_mul:    0.18 + energy * 0.42 - j * 0.018
					duration_ms: 4 + int(rng.next_u32() % 9)
					delay_ms:    acc_delay
				}
			}
		}
		'tick' {
			base := 0.25 + (energy * 1.05)
			out << VoiceLayer{4, 1800, 1200, base, 16, 0}
			if rng.chance(0.25 + energy * 0.45) {
				out << VoiceLayer{0, rng.range_f32(900, 1300), rng.range_f32(650, 980), base * 0.24, 26, 2}
			}
		}
		'tsk' {
			base := 0.22 + (energy * 1.08)
			out << VoiceLayer{3, rng.range_f32(1400, 2200), rng.range_f32(500, 900), base, 28, 0}
			if rng.chance(0.22 + energy * 0.42) {
				out << VoiceLayer{4, 1600, 700, base * 0.26, 18, 1}
			}
		}
		else {
			f := rng.range_f32(620, 760)
			out << VoiceLayer{0, f, f, 0.85, int(f32(base_dur) * 0.8), 0}
		}
	}

	return out
}
