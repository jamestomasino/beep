module main

import beepapp

fn main() {
	beepapp.run() or { panic(err) }
}
