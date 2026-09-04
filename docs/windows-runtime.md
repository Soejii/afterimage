# Afterimage Windows runtime

Afterimage's Windows adapter reads a small set of values from the running
GGST process and never writes game memory. It uses the Win32
`ReadProcessMemory` API and sends the replay-menu keys through `SendInput`.
The Windows desktop build includes the Dart runtime, so Python is not needed.

## Prerequisites

- Use the 64-bit Afterimage build with the 64-bit GGST build.
- Start GGST before recording and leave it open on `Collection -> Replay ->
  Saved Replays`.
- Run GGST and Afterimage as the same Windows user. If Windows denies process
  access, restart both applications at the same integrity level.
- Run OBS with its WebSocket server enabled. Afterimage checks the WebSocket
  protocol and refuses to take over an existing OBS recording.

Afterimage does not install drivers, change security policy, patch GGST, or
modify replay files.

## Native checks

The Windows preflight keeps these cases separate:

- **GGST process absent:** start the game.
- **Module mapping missing:** GGST is still starting, has exited, or its
  process architecture is not visible to this build.
- **Process memory denied:** run both applications as the same user and close
  tools that deny process inspection.
- **Architecture mismatch:** install the matching 64-bit Afterimage build.
- **GWorld signature mismatch:** GGST may have updated, or the build is not
  supported by this adapter. No write or patch is attempted.
- **Keyboard input unavailable:** check that Afterimage and GGST run at the
  same Windows integrity level.
- **Virtual controller driver missing:** install ViGEmBus manually, restart
  Afterimage, and refresh the setup checks. The adapter does not install a
  driver or silently fall back to keyboard input. See
  [`windows-controller.md`](windows-controller.md).

The keyboard adapter sends `U,U` to open a replay, `U` to return to the replay
list, and `W` to select the next replay. It releases every key even when an
input call fails, and waits 800 milliseconds between the two keys in `U,U`.

The automated tests use fake process-memory, SendInput, and virtual-controller
providers. They run on Linux and do not claim that a live GGST process, Windows
process handle, Windows keyboard event, or virtual controller has been verified.
