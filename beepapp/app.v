module beepapp

import audio
import config
import core
import json
import os
import plinux
import time

fn has_flag(args []string, flag string) bool {
	for arg in args {
		if arg == flag {
			return true
		}
	}
	return false
}

fn value_flag(args []string, prefix string) ?string {
	for arg in args {
		if arg.starts_with(prefix) {
			return arg[prefix.len..]
		}
	}
	return none
}

fn is_ambient(motif string) bool {
	return motif in ['hum', 'drone', 'pad']
}

fn is_burst(motif string) bool {
	return motif in ['cluster', 'stutter', 'run', 'tick', 'tsk', 'zap', 'chirp', 'yip']
}

fn hash01(ts i64, salt u32) f32 {
	mut x := u32(ts) ^ salt
	x = x * 1664525 + 1013904223
	return f32((x >> 8) & 0xFFFF) / 65535.0
}

fn apply_runtime_profile(mut cfg config.AppConfig, shared rt RuntimeControl) {
	mut desired := ''
	rlock rt {
		desired = rt.profile
	}
	if desired != '' && desired != cfg.profile {
		cfg = config.with_profile(cfg, desired)
	}
}

fn run_engine_dynamic(cfg config.AppConfig, input_ch chan core.ActivitySample, out chan core.SoundEvent, shared rt RuntimeControl) {
	mut local_cfg := cfg
	mut state := core.new_state()
	for {
		sample := <-input_ch or { break }
		apply_runtime_profile(mut local_cfg, shared rt)
		if event := core.map_activity(mut state, local_cfg.engine, sample) {
			out <- event
		}
	}
	out.close()
}

fn run_activity_filter(raw chan core.ActivitySample, filtered chan core.ActivitySample, shared rt RuntimeControl) {
	for {
		sample := <-raw or { break }
		if filter_activity(sample, shared rt) {
			filtered <- sample
		}
	}
}

fn start_control_server(addr string, config_path string, shared rt RuntimeControl) {
	run_control_server(addr, config_path, shared rt) or {
		eprintln('[warn] control server disabled: ${err}')
	}
}

fn start_web_ui(addr string, ipc_addr string) {
	run_web_ui_server(addr, ipc_addr) or {
		eprintln('[warn] web ui disabled: ${err}')
	}
}

fn filter_activity(sample core.ActivitySample, shared rt RuntimeControl) bool {
	rlock rt {
		if !rt.enabled {
			return false
		}
		match sample.kind {
			.cpu {
				return rt.enable_cpu
			}
			.network {
				return rt.enable_network
			}
			.process, .memory, .system {
				return rt.enable_system
			}
			else {
				return true
			}
		}
	}
}

fn print_usage() {
	println('beep - activity sonifier daemon + live control')
	println('flags:')
	println('  --config=<path> use config file (default: ~/.config/beep/config.conf)')
	println('  --profile=<calm|normal|noisy> apply profile')
	println('  --x11-input    use x11 global input source (requires `-d x11_input`)')
	println('                 on x11 sessions, this is auto-enabled unless --no-x11-input is set')
	println('  --no-x11-input disable x11 global input source')
	println('  --x11-mode=<poll|xi2> x11 backend mode (default: poll)')
	println('  --debug-fake-input enable fake keyboard/mouse activity generator (testing only)')
	println('  --no-cpu       disable cpu sampler')
	println('  --no-system    disable system sampler')
	println('  --no-net       disable network sampler')
	println('  --debug-events print emitted sound events')
	println('  --debug-cpu    print cpu sampler details')
	println('  --audio-null   disable audio output')
	println('  --ipc-addr=<host:port> control server address (default 127.0.0.1:48777)')
	println('  --no-ipc       disable control server')
	println('  --ui-addr=<host:port> web ui server address (default 127.0.0.1:48778)')
	println('  --no-web-ui    disable built-in web ui')
	println('  --ctl=<cmd>    send control cmd and exit')
	println('      cmds: get_state | quit | save_config | toggle:<key> | set:<key>=<value>')
}

fn parse_ctl_cmd(raw string) ?ControlRequest {
	if raw == 'get_state' {
		return ControlRequest{cmd: 'get_state'}
	}
	if raw == 'quit' {
		return ControlRequest{cmd: 'quit'}
	}
	if raw == 'save_config' {
		return ControlRequest{cmd: 'save_config'}
	}
	if raw.starts_with('toggle:') {
		return ControlRequest{cmd: 'toggle', key: raw['toggle:'.len..]}
	}
	if raw.starts_with('set:') {
		body := raw['set:'.len..]
		sep := body.index('=') or { return none }
		if sep <= 0 || sep >= body.len - 1 {
			return none
		}
		return ControlRequest{cmd: 'set', key: body[..sep], value: body[sep + 1..]}
	}
	return none
}

pub fn run() ! {
	args := os.args[1..]
	if has_flag(args, '--help') || has_flag(args, '-h') {
		print_usage()
		return
	}

	ipc_addr := value_flag(args, '--ipc-addr=') or { default_ipc_addr() }
	ui_addr := value_flag(args, '--ui-addr=') or { default_ui_addr() }
	if ctl := value_flag(args, '--ctl=') {
		req := parse_ctl_cmd(ctl) or {
			return error('invalid --ctl command')
		}
		resp := send_control(ipc_addr, req)!
		println(json.encode(resp))
		return
	}

	mut cfg := config.with_profile(config.defaults(), 'normal')
	config_path := value_flag(args, '--config=') or { config.default_config_path() }
	if os.exists(config_path) {
		cfg = config.load_file(config_path, cfg) or {
			eprintln('[warn] could not parse config ${config_path}: ${err}')
			cfg
		}
	}
	if cli_profile := value_flag(args, '--profile=') {
		cfg = config.with_profile(cfg, cli_profile)
	}

	if has_flag(args, '--debug-fake-input') {
		cfg.debug_fake_input = true
	}
	if has_flag(args, '--no-cpu') {
		cfg.enable_cpu = false
	}
	if has_flag(args, '--no-system') {
		cfg.enable_system = false
	}
	if has_flag(args, '--no-net') {
		cfg.enable_network = false
	}
	if has_flag(args, '--audio-null') {
		cfg.audio_backend = 'null'
	}
	if has_flag(args, '--debug-events') {
		cfg.log_events = true
	}
	if has_flag(args, '--debug-cpu') {
		cfg.debug_cpu = true
	}

	if !cfg.debug_fake_input && !cfg.enable_cpu && !cfg.enable_system && !cfg.enable_network {
		return error('no activity sources enabled; use cpu/system/net or --debug-fake-input')
	}

	shared rt := RuntimeControl{
		enabled:          true
		profile:          cfg.profile
		master_volume:    cfg.master_volume
		ambient_level:    cfg.ambient_level
		burst_density:    cfg.burst_density
		enable_cpu:       cfg.enable_cpu
		enable_system:    cfg.enable_system
		enable_network:   cfg.enable_network
		debug_fake_input: cfg.debug_fake_input
		log_events:       cfg.log_events
	}

	if !has_flag(args, '--no-ipc') {
		spawn start_control_server(ipc_addr, config_path, shared rt)
	}
	if !has_flag(args, '--no-web-ui') {
		spawn start_web_ui(ui_addr, ipc_addr)
	}

	session := plinux.detect_session()
	println('session=${session} profile=${cfg.profile} config=${config_path} ipc=${ipc_addr} ui=${ui_addr}')
	if session == .wayland {
		eprintln('[warn] wayland session detected. Global input hooks require compositor-specific support.')
	}

	mut raw_activity_ch := chan core.ActivitySample{cap: 1024}
	mut engine_input_ch := chan core.ActivitySample{cap: 1024}
	mut sound_ch := chan core.SoundEvent{cap: 1024}

	spawn run_engine_dynamic(cfg, engine_input_ch, sound_ch, shared rt)
	spawn run_activity_filter(raw_activity_ch, engine_input_ch, shared rt)

	x11_mode := value_flag(args, '--x11-mode=') or { 'poll' }
	enable_x11_auto := session == .x11 && !has_flag(args, '--no-x11-input')
	enable_x11_cli := has_flag(args, '--x11-input')
	enable_x11 := enable_x11_cli || enable_x11_auto
	if enable_x11 {
		if session == .x11 {
			plinux.run_x11_input_with_mode(raw_activity_ch, x11_mode) or {
				eprintln('[warn] x11 input unavailable: ${err}')
			}
		} else if enable_x11_cli {
			eprintln('[warn] --x11-input ignored (session is ${session})')
		}
	}

	// Always run real samplers; runtime toggles gate them live.
	spawn plinux.run_cpu_sampler(cfg.engine, cfg.debug_cpu, raw_activity_ch)
	spawn plinux.run_system_sampler(raw_activity_ch)
	spawn plinux.run_net_sampler(raw_activity_ch)

	rlock rt {
		if rt.debug_fake_input {
			eprintln('[warn] debug fake input enabled (testing mode)')
			spawn plinux.run_fake_input(raw_activity_ch)
		}
	}

	backend := audio.new_backend(cfg.audio_backend, cfg.synth)
	println('beep daemon started. Press Ctrl+C to stop.')

	for {
		rlock rt {
			if rt.quit_requested {
				println('beep daemon stopping (quit requested).')
				exit(0)
			}
		}
		event := <-sound_ch or {
			time.sleep(50 * time.millisecond)
			continue
		}

		runtime := snapshot(shared rt)
		mut gain := event.gain * runtime.master_volume
		if is_ambient(event.motif) {
			gain *= runtime.ambient_level
		}
		if is_burst(event.motif) {
			if hash01(event.timestamp, 0xB17D35) > runtime.burst_density {
				continue
			}
		}
		if gain < 0.01 {
			continue
		}
		if gain > 1.0 {
			gain = 1.0
		}
		e := core.SoundEvent{
			motif:       event.motif
			gain:        gain
			duration_ms: event.duration_ms
			reason:      event.reason
			timestamp:   event.timestamp
		}

		if runtime.log_events {
			println('[${e.timestamp}] ${e.motif} gain=${e.gain:.2f} duration=${e.duration_ms}ms (${e.reason})')
		}
		backend.play(e)
	}
}
