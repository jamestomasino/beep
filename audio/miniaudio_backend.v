module audio

import core
import os

#flag linux -ldl -lpthread -lm
#flag -I @VMODROOT/third_party/miniaudio
#include "@VMODROOT/audio/miniaudio_shim.h"

fn C.beep_audio_init() int
fn C.beep_audio_shutdown()
fn C.beep_audio_enqueue_ex(waveform int, freq0 f32, freq1 f32, gain f32, duration_ms int, delay_ms int, seed u32) int
fn C.beep_audio_load_sample(path &char) int
fn C.beep_audio_enqueue_sample_ex(sample_index int, gain f32, delay_ms int) int

pub struct MiniAudioBackend {
	ready        bool
	synth_cfg    SynthConfig
	sample_slots map[string][]int
}

pub fn try_miniaudio_backend(synth_cfg SynthConfig) ?Backend {
	ok := C.beep_audio_init() == 1
	if !ok {
		return none
	}
	slots := load_sample_bank()
	return MiniAudioBackend{
		ready:        true
		synth_cfg:    synth_cfg
		sample_slots: slots
	}
}

fn append_slot(mut slots map[string][]int, motif string, idx int) {
	if motif !in slots {
		slots[motif] = []int{}
	}
	mut cur := slots[motif]
	cur << idx
	slots[motif] = cur
}

fn load_sample_bank() map[string][]int {
	mut slots := map[string][]int{}
	base := 'assets/samples'
	files := os.ls(base) or { return slots }
	for file in files {
		if !file.ends_with('.wav') {
			continue
		}
		path := os.join_path(base, file)
		idx := C.beep_audio_load_sample(&char(path.str))
		if idx < 0 {
			continue
		}
		name := file.to_lower()
		if name.starts_with('amb_') || name.contains('engine') {
			append_slot(mut slots, 'bg', idx)
			append_slot(mut slots, 'hum', idx)
			append_slot(mut slots, 'drone', idx)
			append_slot(mut slots, 'pad', idx)
			append_slot(mut slots, 'whirr', idx)
		} else if name.starts_with('fx_') || name.contains('laser') {
			append_slot(mut slots, 'zap', idx)
			append_slot(mut slots, 'yip', idx)
			append_slot(mut slots, 'wheee', idx)
			append_slot(mut slots, 'warble', idx)
			append_slot(mut slots, 'wobble', idx)
		} else {
			append_slot(mut slots, 'bip', idx)
			append_slot(mut slots, 'chirp', idx)
			append_slot(mut slots, 'cluster', idx)
			append_slot(mut slots, 'stutter', idx)
			append_slot(mut slots, 'tick', idx)
			append_slot(mut slots, 'tsk', idx)
			append_slot(mut slots, 'bloop', idx)
		}
	}
	return slots
}

fn is_ambient_motif_backend(motif string) bool {
	return motif in ['hum', 'drone', 'pad', 'wobble', 'whirr']
}

fn is_sequenced_motif_backend(motif string) bool {
	return motif in ['cluster', 'stutter', 'run']
}

fn hotness_from_event(event core.SoundEvent) f32 {
	// Treat high event gain as "hot" periods; clamp into [0, 1].
	mut h := (event.gain - 0.55) / 0.45
	if h < 0.0 {
		h = 0.0
	}
	if h > 1.0 {
		h = 1.0
	}
	return h
}

fn pick_sample_gain(event core.SoundEvent) f32 {
	if is_ambient_motif_backend(event.motif) {
		return event.gain * 0.18
	}
	if event.motif in ['tick', 'tsk', 'cluster', 'stutter'] {
		return event.gain * 0.24
	}
	return event.gain * 0.20
}

fn sample_trigger_chance(event core.SoundEvent) f32 {
	if event.motif in ['tick', 'tsk'] {
		return 0.42
	}
	if is_sequenced_motif_backend(event.motif) {
		return 0.0
	}
	if is_ambient_motif_backend(event.motif) {
		return 0.20
	}
	return 0.30
}

fn bg_sample_trigger_chance(event core.SoundEvent) f32 {
	hot := hotness_from_event(event)
	if is_ambient_motif_backend(event.motif) {
		return 0.24 + event.gain * 0.24 + hot * 0.26
	}
	if is_sequenced_motif_backend(event.motif) {
		return 0.06 + event.gain * 0.08 + hot * 0.12
	}
	return 0.10 + event.gain * 0.12 + hot * 0.18
}

fn pick_bg_sample_gain(event core.SoundEvent) f32 {
	hot := hotness_from_event(event)
	mut out := f32(0.06)
	if is_ambient_motif_backend(event.motif) {
		out = event.gain * 0.10
	} else if is_sequenced_motif_backend(event.motif) {
		out = event.gain * 0.045
	} else {
		out = event.gain * 0.06
	}
	out *= 1.0 + hot * 0.55
	if out < 0.01 {
		out = 0.01
	}
	if out > 0.28 {
		out = 0.28
	}
	return out
}

fn bg_delay_ms(event core.SoundEvent, salt u32) int {
	hot := hotness_from_event(event)
	x := (u32(event.timestamp) * 2654435761) ^ salt
	mut base_min := 120
	mut base_span := 860
	if hot > 0.0 {
		base_min = 80 - int(hot * 28.0)
		base_span = 860 - int(hot * 380.0)
	}
	if base_min < 46 {
		base_min = 46
	}
	if base_span < 220 {
		base_span = 220
	}
	base := base_min + int((x >> 8) % u32(base_span))
	return if is_sequenced_motif_backend(event.motif) { base + 120 } else { base }
}

fn chance_from_event(event core.SoundEvent, salt u32) f32 {
	mut x := u32(event.timestamp) ^ (u32(event.duration_ms) << 12) ^ salt
	x = x * 1664525 + 1013904223
	return f32((x >> 8) & 0xFFFF) / 65535.0
}

pub fn (b MiniAudioBackend) play(event core.SoundEvent) {
	if !b.ready {
		return
	}
	layers := plan_layers(event, b.synth_cfg)
	mut idx := u32(0)
	for layer in layers {
		mut gain := event.gain * layer.gain_mul
		if gain < 0.01 {
			gain = 0.01
		}
		if gain > 1.0 {
			gain = 1.0
		}
		_ = C.beep_audio_enqueue_ex(layer.waveform, layer.freq0, layer.freq1, gain, layer.duration_ms,
			layer.delay_ms, u32(event.timestamp) + idx * 977)
		idx++
	}

	if event.motif in b.sample_slots {
		slots := b.sample_slots[event.motif]
		if slots.len > 0 {
			r := chance_from_event(event, 0x9e37)
			if r < sample_trigger_chance(event) {
				pick := int((u32(event.timestamp) ^ 0x85ebca6b) % u32(slots.len))
				mut sgain := pick_sample_gain(event)
				if sgain < 0.02 {
					sgain = 0.02
				}
				if sgain > 0.65 {
					sgain = 0.65
				}
				_ = C.beep_audio_enqueue_sample_ex(slots[pick], sgain, 0)
			}
		}
	}

	// Additional background-oriented ambient layer with its own delayed cadence.
	if 'bg' in b.sample_slots {
		bg_slots := b.sample_slots['bg']
		if bg_slots.len > 0 {
			hot := hotness_from_event(event)
			bg_r := chance_from_event(event, 0xA341)
			if bg_r < bg_sample_trigger_chance(event) {
				bg_pick := int(((u32(event.timestamp) >> 2) ^ 0x27d4eb2d) % u32(bg_slots.len))
				mut bg_gain := pick_bg_sample_gain(event)
				if bg_gain < 0.015 {
					bg_gain = 0.015
				}
				if bg_gain > 0.24 {
					bg_gain = 0.24
				}
				_ = C.beep_audio_enqueue_sample_ex(bg_slots[bg_pick], bg_gain, bg_delay_ms(event,
					0x77c1))

				// Rare second grain to create moving background smear without crowding.
				second_grain_chance := 0.14 + hot * 0.26
				if chance_from_event(event, 0x5BD1) < second_grain_chance {
					mut bg_pick2 := int(((u32(event.timestamp) >> 1) ^ 0x85ebca6b) % u32(bg_slots.len))
					if bg_slots.len > 1 && bg_pick2 == bg_pick {
						bg_pick2 = (bg_pick2 + 1 + int(u32(event.timestamp) % u32(bg_slots.len - 1))) % bg_slots.len
					}
					mut bg_gain2 := bg_gain * 0.62
					if bg_gain2 < 0.01 {
						bg_gain2 = 0.01
					}
					_ = C.beep_audio_enqueue_sample_ex(bg_slots[bg_pick2], bg_gain2,
						bg_delay_ms(event, 0x13f9) + 180)
				}

				// In hot moments, occasionally add a third very soft trail grain.
				if hot > 0.55 && chance_from_event(event, 0x39A7) < (hot - 0.55) * 0.26 {
					mut bg_pick3 := int(((u32(event.timestamp) >> 3) ^ 0xc2b2ae35) % u32(bg_slots.len))
					if bg_slots.len > 1 && bg_pick3 == bg_pick {
						bg_pick3 = (bg_pick3 + 1) % bg_slots.len
					}
					mut bg_gain3 := bg_gain * 0.38
					if bg_gain3 < 0.01 {
						bg_gain3 = 0.01
					}
					_ = C.beep_audio_enqueue_sample_ex(bg_slots[bg_pick3], bg_gain3,
						bg_delay_ms(event, 0x2D77) + 320)
				}
			}
		}
	}
}
