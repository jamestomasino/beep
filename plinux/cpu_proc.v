module plinux

import core
import os
import strconv
import time

fn read_cpu_line() !string {
	contents := os.read_file('/proc/stat')!
	for line in contents.split_into_lines() {
		if line.starts_with('cpu ') {
			return line
		}
	}
	return error('could not read aggregate cpu line from /proc/stat')
}

fn parse_cpu_totals(line string) !(u64, u64) {
	parts := line.fields()
	if parts.len < 5 {
		return error('unexpected /proc/stat cpu format')
	}

	mut total := u64(0)
	for idx in 1 .. parts.len {
		val := strconv.parse_uint(parts[idx], 10, 64) or {
			return error('failed parsing /proc/stat cpu field')
		}
		total += val
	}
	idle := strconv.parse_uint(parts[4], 10, 64) or {
		return error('failed parsing /proc/stat idle field')
	}
	return total, idle
}

fn utilization_bucket(util f32, cfg core.EngineConfig) core.CpuBucket {
	if util >= cfg.cpu_busy_cutoff {
		return .busy
	}
	if util >= cfg.cpu_active_cutoff {
		return .active
	}
	return .idle
}

pub fn run_cpu_sampler(cfg core.EngineConfig, debug bool, out chan core.ActivitySample) {
	mut prev_total := u64(0)
	mut prev_idle := u64(0)
	mut primed := false

	for {
		line := read_cpu_line() or {
			if debug {
				eprintln('[cpu] failed reading /proc/stat: ${err}')
			}
			time.sleep(500 * time.millisecond)
			continue
		}
		total, idle := parse_cpu_totals(line) or {
			if debug {
				eprintln('[cpu] failed parsing cpu stats: ${err}')
			}
			time.sleep(500 * time.millisecond)
			continue
		}

		if !primed {
			prev_total = total
			prev_idle = idle
			primed = true
			time.sleep(250 * time.millisecond)
			continue
		}

		delta_total := total - prev_total
		delta_idle := idle - prev_idle
		prev_total = total
		prev_idle = idle

		if delta_total == 0 {
			time.sleep(250 * time.millisecond)
			continue
		}

		used := delta_total - delta_idle
		util := f32(used) / f32(delta_total)
		bucket := utilization_bucket(util, cfg)

		if debug {
			println('[cpu] util=${util:.3f} bucket=${bucket}')
		}

		out <- core.ActivitySample{
			kind:       .cpu
			intensity:  util
			timestamp:  core.now_ms()
			source:     'linux.proc.stat'
			cpu_bucket: bucket
		}
		time.sleep(250 * time.millisecond)
	}
}
