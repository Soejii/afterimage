# Afterimage Windows runtime

Afterimage's Windows adapter reads a small set of values from the running
GGST process and never writes game memory. It uses the Win32
`ReadProcessMemory` API and presses replay-menu keys while GGST is the active
window.
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

After selecting Record, leave Saved Replays selected during the five-second
countdown. Before each menu key, keyboard mode checks that the foreground
window belongs to `GGST-Win64-Shipping.exe`. If it does not, Afterimage asks
Windows to bring the single visible, unowned GGST main window to the front,
restoring it first if it is minimized, and waits up to three seconds for that
to happen. It then presses the key with `SendInput`, which rechecks the
foreground process at key-down. If GGST cannot be brought to the front, no key
is sent and the batch stops with the foreground window's details.

GGST only needs to be in front when a replay opens or closes. You can use
other windows while a replay plays, as long as GGST stays at least partly
visible; Afterimage takes the front again for the next key. On a single
monitor GGST will cover Afterimage, so use Alt+Tab to reach the Stop button.

When Windows refuses the foreground change because Afterimage is not the
active application, Afterimage briefly attaches to the input state of the
thread that is in front and asks again. Nothing is sent to that thread's
window. No graphics hook or game-memory write is used.

Versions 0.2.2 to 0.3.3 posted `WM_KEYDOWN` and `WM_KEYUP` to the game window
instead. On a live Windows run that route started the recording but GGST never
opened the replay, so it was replaced. The adapter remains in the source for
its tests but is no longer selected by the Windows backend. The new route has
not been confirmed on a live Windows machine yet.

Replay controls are expanded by default on Windows. A physical controller does
not automatically select Afterimage's controller mode.

Afterimage waits up to 30 seconds for OBS's matching recording-stopped event
before moving the recording. If completion is not confirmed, it leaves the
file in OBS's recording folder and reports the path when OBS supplied it.
Move errors include the failed operation and original filesystem error. The
result screen labels the intended destination as the batch folder, not as proof
that the video was saved there.

Focus failures include a UTC timestamp, expected GGST PID, foreground PID and
window handle, lookup failure details, and best-effort process name and window
title. Batch errors also include the stage, replay index, and elapsed time.
These details appear in the error and the batch's `summary.json`; window titles
can include document or page names, so inspect the report before sharing it.

### Background input investigation

On the reported Windows borderless setup, physical controller menu input works
with a smaller browser focused and GGST partly visible, but fails when that same
browser fully covers GGST. This distinguishes coverage from focus in that setup;
it does not establish the cause or prove virtual-controller behavior.

[Microsoft documents DXGI occlusion](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-status)
as a rendering visibility condition that applications may use to suspend work.
That is a hypothesis here, not a measured GGST status. The documentation also
excludes flip-model swap chains from this status. No game setting, graphics
hook, memory write, or focus-stealing workaround is applied on that assumption.

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
  same Windows integrity level. Windows blocks injected keys aimed at a
  higher-integrity window, and Afterimage does not change these permissions.
- **Virtual controller driver missing:** install ViGEmBus manually, restart
  Afterimage, and refresh the setup checks. The adapter does not install a
  driver or silently fall back to keyboard input. See
  [`windows-controller.md`](windows-controller.md).

The keyboard adapter sends `U,U` to open a replay, `U` to return to the replay
list, and `W` to select the next replay. It releases every key even when an
input call fails, and waits 800 milliseconds between the two keys in `U,U`.

The automated tests use fake process-memory, window-focus, window-message, SendInput, and virtual-controller
providers. They run on Linux and do not claim that a live GGST process, Windows
process handle, Windows keyboard event, or virtual controller has been verified.
