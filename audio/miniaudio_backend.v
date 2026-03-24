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

fn pick_sample_gain(event core.SoundEvent) f32 {
	if event.motif in ['hum', 'drone', 'pad', 'wobble', 'whirr'] {
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
	if event.motif in ['cluster', 'stutter', 'run'] {
		return 0.0
	}
	if event.motif in ['hum', 'drone', 'pad', 'wobble', 'whirr'] {
		return 0.20
	}
	return 0.30
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
}
