module plinux

import core
import os
import strconv
import time

struct NetSnapshot {
	rx_bytes u64
	tx_bytes u64
}

fn read_net_snapshot() ?NetSnapshot {
	contents := os.read_file('/proc/net/dev') or { return none }
	mut rx_total := u64(0)
	mut tx_total := u64(0)

	for line in contents.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('Inter-') || trimmed.starts_with('face') {
			continue
		}

		parts := trimmed.replace(':', ' ').fields()
		if parts.len < 17 {
			continue
		}
		iface := parts[0]
		if iface == 'lo' {
			continue
		}

		rx := strconv.parse_uint(parts[1], 10, 64) or { continue }
		tx := strconv.parse_uint(parts[9], 10, 64) or { continue }
		rx_total += rx
		tx_total += tx
	}

	return NetSnapshot{
		rx_bytes: rx_total
		tx_bytes: tx_total
	}
}

pub fn run_net_sampler(out chan core.ActivitySample) {
	mut prev := NetSnapshot{}
	for {
		if snap := read_net_snapshot() {
			prev = snap
			break
		}
		time.sleep(400 * time.millisecond)
	}

	for {
		time.sleep(350 * time.millisecond)
		next := read_net_snapshot() or { continue }
		now := core.now_ms()

		rx_delta := if next.rx_bytes > prev.rx_bytes {
			next.rx_bytes - prev.rx_bytes
		} else {
			u64(0)
		}
		tx_delta := if next.tx_bytes > prev.tx_bytes {
			next.tx_bytes - prev.tx_bytes
		} else {
			u64(0)
		}
		total_delta := rx_delta + tx_delta

		if total_delta > 0 {
			// Scale around ~256KB/s equivalent to high intensity.
			bytes_per_second := f32(total_delta) * (1000.0 / 350.0)
			mut intensity := bytes_per_second / 262144.0
			if intensity > 1 {
				intensity = 1
			}
			out <- core.ActivitySample{
				kind:      .network
				intensity: intensity
				timestamp: now
				source:    'linux.proc.net'
			}
		}

		prev = next
	}
}
