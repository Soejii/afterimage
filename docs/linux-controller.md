# Optional Linux virtual controller

Afterimage includes an optional Linux `uinput` menu-input port. It is an
adapter behind a small native seam and is available when the setup probe can
open a uinput device. Keyboard mode remains an explicit user choice, not an
automatic fallback after a controller failure.

## Mapping

The port presents a digital gamepad named `Afterimage Replay Controller`:

| Replay action | Existing keyboard sequence | Virtual gamepad sequence |
| --- | --- | --- |
| Open replay | `U`, `U` | South face button, South face button, normally `A`, `A` |
| Exit to replay list | `U` | South face button, normally `A` |
| Select next replay | `W` | D-pad up |

The face-button names are the position-neutral Linux kernel names. South is
normally A on Xbox layouts and Cross on PlayStation layouts, so the mapping
remains clear across physical controller brands. Afterimage does not read or
disconnect the user's physical controller. The
adapter defines the remaining face and D-pad codes for future mappings, but it
does not create analog axes, rumble, or force feedback.

Each button is held for 80 ms. There is an additional 800 ms delay between the
two South button taps used to open a replay. A button is released in a `finally`
path after every tap. If an event or sequence fails, the adapter closes the
device and the native implementation releases any tracked buttons, destroys the
virtual device, and closes the file descriptor.

## Runtime requirements

The native implementation opens `/dev/uinput`, with `/dev/input/uinput` as a
fallback. The user must have permission to open one of these character
devices, normally through a distribution-specific udev rule or input group.
Afterimage does not change group membership, install a udev rule, or weaken a
system policy automatically.

The readiness probe only opens the device and sends `UI_SET_EVBIT(EV_KEY)`; it
does not create a virtual controller. It reports these cases separately:

- **Device missing:** neither uinput device path exists.
- **Permission denied:** a path exists but the process cannot open or configure
  it.
- **Unsupported ioctl:** the kernel rejected the uinput configuration ioctl,
  usually because the required interface is unavailable.
- **Ready:** the device opened and accepted the event-bit probe.

The implementation uses the modern `UI_DEV_SETUP`, `UI_DEV_CREATE`, and
`UI_DEV_DESTROY` ioctls. Ioctl requests are constructed from Linux's `_IOC`
layout. The setup buffer uses the fixed-width `struct uinput_setup` layout,
and input-event timestamps use the native Linux `long` width, so the event
buffer is not hard-coded to only the 64-bit layout.

Focused tests inject a fake device factory. Importing the library and running
the Linux unit tests never opens `/dev/uinput` or creates a real controller.
