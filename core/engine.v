module core

import time

pub fn run_engine(cfg EngineConfig, input_ch chan ActivitySample, out chan SoundEvent) {
	mut state := new_state()
	for {
		sample := <-input_ch or { break }
		if event := map_activity(mut state, cfg, sample) {
			out <- event
		}
	}
	out.close()
}

pub fn now_ms() i64 {
	return time.now().unix_milli()
}
