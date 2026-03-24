module plinux

import core
import os
import strconv
import time

struct SystemSnapshot {
	processes_total u64
	ctxt_total      u64
	mem_used_ratio  f32
}

fn read_stat_counter(contents string, key string) ?u64 {
	for line in contents.split_into_lines() {
		if line.starts_with(key) {
			parts := line.fields()
			if parts.len >= 2 {
				v := strconv.parse_uint(parts[1], 10, 64) or { return none }
				return v
			}
		}
	}
	return none
}

fn read_mem_ratio(contents string) ?f32 {
	mut total := f32(0)
	mut avail := f32(0)
	for line in contents.split_into_lines() {
		parts := line.fields()
		if parts.len < 2 {
			continue
		}
		if parts[0] == 'MemTotal:' {
			total = f32(strconv.atof64(parts[1]) or { 0.0 })
		}
		if parts[0] == 'MemAvailable:' {
			avail = f32(strconv.atof64(parts[1]) or { 0.0 })
		}
	}
	if total <= 0 {
		return none
	}
	used := 1.0 - (avail / total)
	if used < 0 {
		return 0
	}
	if used > 1 {
		return 1
	}
	return used
}

fn read_snapshot() ?SystemSnapshot {
	stat := os.read_file('/proc/stat') or { return none }
	mem := os.read_file('/proc/meminfo') or { return none }
	procs := read_stat_counter(stat, 'processes') or { return none }
	ctxt := read_stat_counter(stat, 'ctxt') or { return none }
	mem_ratio := read_mem_ratio(mem) or { return none }
	return SystemSnapshot{
		processes_total: procs
		ctxt_total:      ctxt
		mem_used_ratio:  mem_ratio
	}
}

pub fn run_system_sampler(out chan core.ActivitySample) {
	mut prev := SystemSnapshot{}
	for {
		if snap := read_snapshot() {
			prev = snap
			break
		}
		time.sleep(400 * time.millisecond)
	}

	for {
		time.sleep(300 * time.millisecond)
		next := read_snapshot() or { continue }
		now := core.now_ms()

		proc_delta := if next.processes_total > prev.processes_total {
			next.processes_total - prev.processes_total
		} else {
			u64(0)
		}
		if proc_delta > 0 {
			proc_intensity := f32(proc_delta) / 12.0
			out <- core.ActivitySample{
				kind:      .process
				intensity: if proc_intensity > 1 { 1 } else { proc_intensity }
				timestamp: now
				source:    'linux.proc.processes'
			}
		}

		ctxt_delta := if next.ctxt_total > prev.ctxt_total {
			next.ctxt_total - prev.ctxt_total
		} else {
			u64(0)
		}
		if ctxt_delta > 0 {
			ctxt_intensity := f32(ctxt_delta) / 60000.0
			if ctxt_intensity > 0.08 {
				out <- core.ActivitySample{
					kind:      .system
					intensity: if ctxt_intensity > 1 { 1 } else { ctxt_intensity }
					timestamp: now
					source:    'linux.proc.ctxt'
				}
			}
		}

		mut mem_delta := next.mem_used_ratio - prev.mem_used_ratio
		if mem_delta < 0 {
			mem_delta = -mem_delta
		}
		if mem_delta > 0.006 {
			mem_intensity := mem_delta * 45.0
			out <- core.ActivitySample{
				kind:      .memory
				intensity: if mem_intensity > 1 { 1 } else { mem_intensity }
				timestamp: now
				source:    'linux.proc.mem'
			}
		}

		prev = next
	}
}
