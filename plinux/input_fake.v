module plinux

import core
import time

pub fn run_fake_input(out chan core.ActivitySample) {
	mut tick := 0
	for {
		time.sleep(140 * time.millisecond)
		tick++
		now := core.now_ms()

		if tick % 2 == 0 {
			out <- core.ActivitySample{
				kind:      .keyboard
				intensity: 0.35 + f32((tick % 5)) * 0.08
				timestamp: now
				source:    'linux.fake.keyboard'
			}
		}

		if tick % 3 == 0 {
			out <- core.ActivitySample{
				kind:      .mouse
				intensity: 0.22 + f32((tick % 7)) * 0.06
				timestamp: now
				source:    'linux.fake.mouse'
			}
		}
	}
}
