#ifndef BEEP_X11_XINPUT2_SHIM_H
#define BEEP_X11_XINPUT2_SHIM_H

#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>

static inline int beep_xi2_available(Display* display, int* opcode_out) {
	int event = 0;
	int error = 0;
	int opcode = 0;
	if (!XQueryExtension(display, "XInputExtension", &opcode, &event, &error)) {
		return 0;
	}
	int major = 2;
	int minor = 0;
	if (XIQueryVersion(display, &major, &minor) != Success) {
		return 0;
	}
	*opcode_out = opcode;
	return 1;
}

static inline int beep_xi2_select(Display* display, Window root) {
	unsigned char mask[(XI_LASTEVENT + 7) / 8];
	for (unsigned int i = 0; i < sizeof(mask); i++) {
		mask[i] = 0;
	}
	XISetMask(mask, XI_RawKeyPress);
	XISetMask(mask, XI_RawKeyRelease);
	XISetMask(mask, XI_RawButtonPress);
	XISetMask(mask, XI_RawButtonRelease);
	XISetMask(mask, XI_RawMotion);

	XIEventMask event_mask;
	event_mask.deviceid = XIAllMasterDevices;
	event_mask.mask_len = (int)sizeof(mask);
	event_mask.mask = mask;
	XISelectEvents(display, root, &event_mask, 1);
	XFlush(display);
	return 1;
}

// Returns 1 when an event was decoded and written, 0 otherwise.
// kind: 1 = keyboard, 2 = mouse
static inline int beep_xi2_next(Display* display, int opcode, int timeout_us, int* kind_out, float* intensity_out) {
	if (XPending(display) == 0) {
		if (timeout_us > 0) {
			usleep((useconds_t)timeout_us);
		}
		if (XPending(display) == 0) {
			return 0;
		}
	}

	XEvent event;
	XNextEvent(display, &event);
	if (event.type != GenericEvent || event.xcookie.extension != opcode) {
		return 0;
	}
	if (!XGetEventData(display, &event.xcookie)) {
		return 0;
	}

	int handled = 1;
	switch (event.xcookie.evtype) {
		case XI_RawKeyPress:
		case XI_RawKeyRelease:
			*kind_out = 1;
			*intensity_out = 0.60f;
			break;
		case XI_RawButtonPress:
			*kind_out = 2;
			*intensity_out = 0.98f;
			break;
		case XI_RawButtonRelease:
			*kind_out = 2;
			*intensity_out = 0.68f;
			break;
		case XI_RawMotion:
			*kind_out = 2;
			*intensity_out = 0.25f;
			break;
		default:
			handled = 0;
			break;
	}

	XFreeEventData(display, &event.xcookie);
	return handled;
}

#endif
