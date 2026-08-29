# Afterimage Linux runtime

Afterimage's Linux adapter is a read-only integration with the GGST process.
It does not require Python. It uses the Dart runtime bundled with the desktop
build, `process_vm_readv(2)` for memory reads, and `/proc/<pid>/mem` as a
read-only fallback.

## Runtime packages

Install the GTK 3, X11, and XTest runtime libraries supplied by your
distribution:

| Distribution family | Packages |
| --- | --- |
| Arch Linux | `gtk3`, `libx11`, `libxtst` |
| Debian or Ubuntu | `libgtk-3-0` or `libgtk-3-0t64`, `libx11-6`, `libxtst6` |
| Fedora | `gtk3`, `libX11`, `libXtst` |

The development `-dev` or `-devel` packages are not required for a released
Afterimage build. They are only needed when compiling the application locally.

Afterimage sends XTest events to the `DISPLAY` inherited by
`GGST-Win64-Shipping.exe` through gamescope. It does not raise the Afterimage
window, take desktop focus, or inject into the default desktop display. Start
GGST through gamescope and keep its process alive while a batch runs.

## Process-memory permission

The monitor reads a few GGST values and never writes game memory. Linux may
reject reads because of the kernel ptrace policy, a sandbox, a different user,
or a process that is exiting. Afterimage reports this as **process memory
denied**. It does not silently treat permission failures as a game update.

The safe one-time prerequisites are:

1. Run Steam, GGST, and Afterimage as the same desktop user.
2. If GGST is sandboxed, grant only the narrowly scoped process-inspection
   permission offered by that sandbox, following its distribution
   documentation.
3. If a managed workstation still denies access, ask its administrator for a
   per-application debug/inspection policy for Afterimage and GGST.

Do not set `kernel.yama.ptrace_scope` to a weaker global value, make `/proc`
world-readable, or add broad capabilities to unrelated binaries. Afterimage
does not modify those settings automatically. A permission change can be
reverted through the same distribution or administrator policy that granted
it.

## Readiness messages

The Linux preflight keeps these cases separate:

- **GGST process absent:** start the game.
- **Module mapping missing:** GGST is starting, exiting, or its Wine process
  layout is not visible yet.
- **Process memory denied:** fix the scoped permission described above.
- **GWorld signature mismatch:** GGST may have updated, or the build is not
  supported by this adapter. No write or patch is attempted.
- **libX11/libXtst missing:** install the matching runtime packages.
- **Gamescope DISPLAY missing:** launch GGST through gamescope and retry.
- **uinput missing or denied:** install or enable the kernel uinput interface
  and grant the current user narrowly scoped access to its device node. See
  [`linux-controller.md`](linux-controller.md).

The current automated tests use fake procfs, memory, keyboard, and controller
providers. They do not claim that a live GGST process, gamescope display,
XTest event, or uinput controller has been verified on this machine.
