# Linux controller input

Linux controller mode writes menu events into the existing evdev device that
GGST is already reading. It never creates a uinput device, disconnects the
physical controller, or falls back to keyboard input when controller mode is
unavailable.

## Discovery

Before sending an event, Afterimage discovers the current controller in this
order:

1. Find the GGST process from its command line or its truncated `/proc` `comm`
   name, then read its `WINEPREFIX` and SDL controller ignore list.
2. Find every process with the same Wine prefix, ignoring a trailing slash.
3. Inspect those processes' file-descriptor symlinks for `/dev/input/eventN`
   nodes.
4. Match those nodes against `/proc/bus/input/devices`. A controller must have
   `BTN_SOUTH` in its `KEY` bitmap and `ABS_HAT0Y` in its `ABS` bitmap.
5. When several candidates remain, remove vendor/product pairs in GGST's
   `SDL_GAMECONTROLLER_IGNORE_DEVICES` list. If several still remain, choose
   the lowest event number and report the ambiguity in the readiness detail.

This follows the Steam Input and Proton topology used by GGST. The physical
pad can be held by Steam while `winedevice.exe` holds the virtual pad that the
game actually reads.

## Mapping

| Replay action | Existing keyboard sequence | Existing controller event sequence |
| --- | --- | --- |
| Open replay | `U`, `U` | `BTN_SOUTH` tap, 800 ms delay, `BTN_SOUTH` tap |
| Exit to replay list | `U` | `BTN_SOUTH` tap |
| Select next replay | `W` | `ABS_HAT0Y = -1`, hold, `ABS_HAT0Y = 0` |

A tap presses `BTN_SOUTH`, holds it for 80 ms, and releases it. Every event is
followed by `EV_SYN`/`SYN_REPORT`. The adapter opens the selected node
`O_WRONLY` and writes Linux `input_event` records whose timestamp fields use
the native pointer width, matching the Linux `timeval` layout on 32-bit and
64-bit builds.

## Failure safety

The controller node is checked for write permission before recording. Missing
GGST, an unknown Wine prefix, no controller node held by the game, permission
denial, and event-write failure are reported separately. On every close path,
including a failed action, Afterimage attempts to release `BTN_SOUTH` and
return `ABS_HAT0Y` to zero before closing the file descriptor. This prevents a
failed batch from leaving the user's controller logically held.

No setup check changes `/proc`, device permissions, Steam Input, or the game.

Focused tests inject both procfs and device-writer seams, so they never open a
real `/dev/input/eventN` node or send input to GGST.
