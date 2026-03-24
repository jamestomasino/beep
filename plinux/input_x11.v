module plinux

import core
import time

const x11_poll_interval = 55 * time.millisecond
const x11_button_mask_bits = u32(0x1F00)

fn popcount8(x u8) int {
	mut y := x
	mut count := 0
	for y != 0 {
		y &= y - 1
		count++
	}
	return count
}

fn popcount32(x u32) int {
	mut y := x
	mut count := 0
	for y != 0 {
		y &= y - 1
		count++
	}
	return count
}

fn clamp01(v f32) f32 {
	if v < 0.0 {
		return 0.0
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

$if linux ? {
	$if x11_input ? {
		#flag linux -lX11
		#include <X11/Xlib.h>
		$if x11_xi2 ? {
			#flag linux -lXi
			#include "@VMODROOT/plinux/x11_xinput2_shim.h"

			fn C.beep_xi2_available(display voidptr, opcode_out &int) int
			fn C.beep_xi2_select(display voidptr, root u64) int
			fn C.beep_xi2_next(display voidptr, opcode int, timeout_us int, kind_out &int, intensity_out &f32) int
		}

		fn C.XOpenDisplay(display_name &char) voidptr
		fn C.XDefaultRootWindow(display voidptr) u64
		fn C.XQueryKeymap(display voidptr, keys_return &char) int
		fn C.XQueryPointer(display voidptr, w u64, root_return &u64, child_return &u64, root_x_return &int,
	root_y_return &int, win_x_return &int, win_y_return &int, mask_return &u32) int

		pub fn run_x11_input(out chan core.ActivitySample) ! {
			run_x11_input_with_mode(out, 'poll')!
		}

		pub fn run_x11_input_with_mode(out chan core.ActivitySample, mode string) ! {
			display := C.XOpenDisplay(unsafe { nil })
			if isnil(display) {
				return error('could not open X11 display')
			}
			root_window := C.XDefaultRootWindow(display)
			if mode == 'xi2' {
				$if x11_xi2 ? {
					mut opcode := 0
					if C.beep_xi2_available(display, &opcode) == 0 {
						return error('xinput2 extension not available on this x11 server')
					}
					if C.beep_xi2_select(display, root_window) == 0 {
						return error('failed to subscribe to xinput2 raw events')
					}
					spawn x11_xi2_loop(display, opcode, out)
					return
				} $else {
					return error('xinput2 backend disabled at compile time; build with `-d x11_xi2`')
				}
			}
			spawn x11_poll_loop(display, root_window, out)
		}

		$if x11_xi2 ? {
			fn x11_xi2_loop(display voidptr, opcode int, out chan core.ActivitySample) {
				for {
					mut kind := 0
					mut intensity := f32(0.0)
					if C.beep_xi2_next(display, opcode, 150000, &kind, &intensity) == 0 {
						continue
					}
					if kind == 1 {
						out <- core.ActivitySample{
							kind:      .keyboard
							intensity: clamp01(intensity)
							timestamp: core.now_ms()
							source:    'linux.x11.xi2.keyboard'
						}
					} else if kind == 2 {
						out <- core.ActivitySample{
							kind:      .mouse
							intensity: clamp01(intensity)
							timestamp: core.now_ms()
							source:    'linux.x11.xi2.mouse'
						}
					}
				}
			}
		}

		fn x11_poll_loop(display voidptr, root_window u64, out chan core.ActivitySample) {
			mut prev_keymap := [32]u8{}
			mut curr_keymap := [32]u8{}
			mut prev_x := int(0)
			mut prev_y := int(0)
			mut prev_mask := u32(0)
			mut initialized := false

			for {
				C.XQueryKeymap(display, &char(&curr_keymap[0]))

				mut root_ret := u64(0)
				mut child_ret := u64(0)
				mut root_x := int(0)
				mut root_y := int(0)
				mut win_x := int(0)
				mut win_y := int(0)
				mut mask := u32(0)
				C.XQueryPointer(display, root_window, &root_ret, &child_ret, &root_x,
					&root_y, &win_x, &win_y, &mask)

				if initialized {
					mut key_changes := 0
					for i in 0 .. 32 {
						key_changes += popcount8(prev_keymap[i] ^ curr_keymap[i])
					}
					if key_changes > 0 {
						out <- core.ActivitySample{
							kind:      .keyboard
							intensity: clamp01(f32(key_changes) / 8.0)
							timestamp: core.now_ms()
							source:    'linux.x11.keyboard'
						}
					}

					dx := root_x - prev_x
					dy := root_y - prev_y
					dist := if dx < 0 { -dx } else { dx } + if dy < 0 { -dy } else { dy }
					pressed_changes := popcount32((mask & ~prev_mask) & x11_button_mask_bits)
					released_changes := popcount32((prev_mask & ~mask) & x11_button_mask_bits)
					if pressed_changes > 0 {
						out <- core.ActivitySample{
							kind:      .mouse
							intensity: clamp01(0.88 + f32(pressed_changes - 1) * 0.06)
							timestamp: core.now_ms()
							source:    'linux.x11.mouse.click'
						}
					}
					if released_changes > 0 {
						out <- core.ActivitySample{
							kind:      .mouse
							intensity: clamp01(0.62 + f32(released_changes - 1) * 0.05)
							timestamp: core.now_ms()
							source:    'linux.x11.mouse.release'
						}
					}

					if dist > 0 {
						movement_score := f32(dist) / 34.0
						out <- core.ActivitySample{
							kind:      .mouse
							intensity: clamp01(movement_score)
							timestamp: core.now_ms()
							source:    'linux.x11.mouse.move'
						}
					}
				}

				for i in 0 .. 32 {
					prev_keymap[i] = curr_keymap[i]
				}
				prev_x = root_x
				prev_y = root_y
				prev_mask = mask
				initialized = true
				time.sleep(x11_poll_interval)
			}
		}
	} $else {
		pub fn run_x11_input(_out chan core.ActivitySample) ! {
			return error('x11 input support is disabled at compile time; build with `-d x11_input`')
		}

		pub fn run_x11_input_with_mode(_out chan core.ActivitySample, _mode string) ! {
			return error('x11 input support is disabled at compile time; build with `-d x11_input`')
		}
	}
} $else {
	pub fn run_x11_input(_out chan core.ActivitySample) ! {
		return error('x11 input is only supported on linux')
	}

	pub fn run_x11_input_with_mode(_out chan core.ActivitySample, _mode string) ! {
		return error('x11 input is only supported on linux')
	}
}
