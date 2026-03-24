module beepapp

import audio
import config
import core
import os
import plinux

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

fn print_usage() {
	println('beep - nullsoft-inspired activity sonifier')
	println('flags:')
	println('  --config=<path> use config file (default: ~/.config/beep/config.conf)')
	println('  --profile=<calm|normal|noisy> apply profile')
	println('  --x11-input    use x11 global input source (requires `-d x11_input`)')
	println('  --x11-mode=<poll|xi2> x11 backend mode (default: poll)')
	println('  --debug-fake-input enable fake keyboard/mouse activity generator (testing only)')
	println('  --no-cpu       disable /proc/stat cpu activity sampler')
	println('  --no-system    disable /proc system churn sampler')
	println('  --no-net       disable /proc network traffic sampler')
	println('  --debug-events print emitted sound events')
	println('  --debug-cpu    print cpu sampler details')
	println('  --audio-null   disable audio output (logs only)')
}

pub fn run() ! {
	args := os.args[1..]
	if has_flag(args, '--help') || has_flag(args, '-h') {
		print_usage()
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
		return error('no activity sources enabled; remove --no-cpu/--no-system/--no-net or use --debug-fake-input for testing')
	}

	session := plinux.detect_session()
	println('session=${session} profile=${cfg.profile} config=${config_path}')
	if session == .wayland {
		eprintln('[warn] wayland session detected. Global input hooks require compositor-specific support.')
	}

	mut activity_ch := chan core.ActivitySample{cap: 512}
	mut sound_ch := chan core.SoundEvent{cap: 512}

	spawn core.run_engine(cfg.engine, activity_ch, sound_ch)

	if has_flag(args, '--x11-input') {
		if session == .x11 {
			x11_mode := value_flag(args, '--x11-mode=') or { 'poll' }
			plinux.run_x11_input_with_mode(activity_ch, x11_mode) or {
				eprintln('[warn] x11 input unavailable: ${err}')
			}
		} else {
			eprintln('[warn] --x11-input ignored (session is ${session})')
		}
	}

	if cfg.debug_fake_input {
		eprintln('[warn] debug fake input enabled (testing mode)')
		spawn plinux.run_fake_input(activity_ch)
	}
	if cfg.enable_cpu {
		spawn plinux.run_cpu_sampler(cfg.engine, cfg.debug_cpu, activity_ch)
	}
	if cfg.enable_system {
		spawn plinux.run_system_sampler(activity_ch)
	}
	if cfg.enable_network {
		spawn plinux.run_net_sampler(activity_ch)
	}

	backend := audio.new_backend(cfg.audio_backend, cfg.synth)
	println('beep daemon started (linux prototype). Press Ctrl+C to stop.')

	for {
		event := <-sound_ch or { break }
		if cfg.log_events {
			println('[${event.timestamp}] ${event.motif} gain=${event.gain:.2f} duration=${event.duration_ms}ms (${event.reason})')
		}
		backend.play(event)
	}
}
