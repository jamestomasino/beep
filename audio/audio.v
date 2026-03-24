module audio

import core

pub interface Backend {
	play(event core.SoundEvent)
}

pub struct ConsoleBackend {}

pub fn (_ ConsoleBackend) play(_ core.SoundEvent) {
	print('\a')
}

pub struct NullBackend {}

pub fn (_ NullBackend) play(_ core.SoundEvent) {}

pub fn new_backend(name string, synth_cfg SynthConfig) Backend {
	match name {
		'null' {
			return NullBackend{}
		}
		'console' {
			return ConsoleBackend{}
		}
		else {
			if b := try_miniaudio_backend(synth_cfg) {
				return b
			}
			eprintln('[warn] miniaudio backend unavailable; falling back to null audio backend')
			return NullBackend{}
		}
	}
}
