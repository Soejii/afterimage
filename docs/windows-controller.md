# Optional Windows virtual controller

Afterimage can automate GGST's replay menus while the user keeps a physical
Xbox, DualShock, or DualSense controller connected. It does not read, remap, or
disconnect that physical controller. Instead, it creates a separate,
short-lived Xbox 360-compatible controller for the recording batch.

## Mapping

| Replay action | Virtual controller sequence |
| --- | --- |
| Open replay | South face button, South face button, normally A or Cross |
| Exit to replay list | South face button, normally A or Cross |
| Select next replay | D-pad up |

Each button is held for 80 ms. Afterimage releases the button after every tap
and sends a neutral report before removing the virtual controller. It does not
silently fall back to keyboard if controller creation or input fails.

## Runtime requirement

Windows does not provide a built-in API for creating an XInput controller.
Controller mode therefore requires the separately installed
[ViGEmBus driver](https://github.com/nefarius/ViGEmBus/releases/tag/v1.22.0).
The upstream project is retired, so review its
[end-of-life notice](https://docs.nefarius.at/projects/ViGEm/End-of-Life/)
before installing it. Some controller-remapping applications may already have
installed ViGEmBus.

Afterimage's setup check only connects to the bus and then disconnects. It does
not create a controller during setup, install a driver, request elevation, or
change system configuration. If the driver is absent, recording stays locked
for controller mode and the app explains how to resolve the blocker. Keyboard
mode remains a separate explicit choice.

The release bundle includes Afterimage's native controller bridge and a pinned,
MIT-licensed ViGEmClient build. Keep `afterimage_controller.dll` beside
`afterimage.exe` and the rest of the portable bundle.

## Current verification boundary

The mapping, readiness failures, release behavior, and backend selection have
automated tests. A live Windows run with GGST and real Xbox and PlayStation
controllers is still required before this mode should be described as verified
end to end.
