module plinux

import os

pub enum SessionType {
	x11
	wayland
	unknown
}

pub fn detect_session() SessionType {
	xdg := os.getenv('XDG_SESSION_TYPE').to_lower()
	match xdg {
		'x11' {
			return .x11
		}
		'wayland' {
			return .wayland
		}
		else {
			return .unknown
		}
	}
}

pub fn (s SessionType) str() string {
	match s {
		.x11 {
			return 'x11'
		}
		.wayland {
			return 'wayland'
		}
		.unknown {
			return 'unknown'
		}
	}
}
