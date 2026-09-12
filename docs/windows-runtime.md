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

## Game and replay discovery

Afterimage checks the usual Steam folders, paths supplied by the Windows
environment, and Steam's read-only registry values. It then follows Steam's
configured library folders when looking for GGST. If discovery cannot see a
library, choose the game or saved replay folder in Setup. The selected folders
are read-only setup inputs and are never modified by Afterimage.

Start with one replay and inspect the resulting video before recording a larger
batch. Confirm that the picture shows GGST and that the expected game sound is
present. Choose the keyboard or virtual-controller method under **Replay controls**; the
controller method requires the separately installed ViGEmBus driver.

After selecting Record, switch to GGST during the five-second countdown.
Keyboard recording checks that GGST owns the active window before it sends
keys and while the replay plays. If another app becomes active, Afterimage
stops the batch and attempts to preserve the current recording as a partial
video. Return to Saved Replays before trying again. These checks do not bring
the game to the foreground automatically.

Afterimage waits up to 30 seconds for OBS's matching recording-stopped event
before moving the recording. If completion is not confirmed, it leaves the
file in OBS's recording folder and reports the path when OBS supplied it.
Move errors include the failed operation and original filesystem error.

Focus failures include a UTC timestamp, expected GGST PID, foreground PID and
window handle, lookup failure details, and best-effort process name and window
title. Batch errors also include the stage, replay index, and elapsed time.
These details appear in the error and the batch's `summary.json`; window titles
can include document or page names, so inspect the report before sharing it.

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
