# Current status

This file records what works in the current alpha and what is still unverified.

Version `0.2.1+4` is an alpha desktop release:

- One Material 3 dark workspace screen that moves through four states:
  blocked, ready, running, and finished. While blocked it leads with a single
  next step and shows the remaining ones beneath. The full check list lives in
  a collapsed details drawer.
- Read-only checks for the supported OS, GGST Steam app manifests across
  configured library folders, the `GGST-Win64-Shipping.exe` process, the local
  OBS recording connection, and `REP###.sav` replay files. Linux discovery
  follows native and Flatpak Steam library folders; Windows also checks common
  environment paths and Steam's read-only registry entries.
- Production startup selects the real Windows or Linux native backend. Start
  remains locked until the game, OBS, replay library, selected input mode, and
  output folder all pass their checks.
- Keyboard automation is implemented on Windows through `SendInput` and on
  Linux through targeted gamescope XTest events. Linux also supports an
  optional `uinput` virtual controller. Windows supports an optional
  Xbox-compatible virtual controller through a separately installed ViGEmBus
  driver. Neither platform consumes the user's physical controller, and
  neither silently falls back to keyboard.
- The replay batch engine is now ported behind testable Dart contracts. It waits
  for frame movement before starting a battle, requires a result event or a
  duration-derived run of missing reads to finish it, and treats frozen frames
  as an in-progress replay.
- Every batch records into one combined video, stopped and organized once at
  the end. The engine still supports per-replay recording behind
  `VideoMode.separate`, but no interface offers it. Failures and stop requests
  preserve the current source output as a partial recording when possible.
- OBS WebSocket v5 control now supports localhost configuration discovery,
  Hello/Identify authentication, request timeouts, request failures, and safe
  close handling. Setup marks OBS ready only after this protocol and idle-state
  probe succeeds.
- Completed and partial outputs use collision-checked replay or combined names,
  preserve the OBS file extension, and leave the source recoverable when a move
  cannot be completed. `summary.json` is checkpointed after each replay and at
  terminal batch states through a temporary-file rename that is atomic where
  the platform supports replacement, with a durable backup/restore fallback
  elsewhere. A small hidden lock file prevents two active Afterimage batches
  from checkpointing into the same output folder at once.

While a batch runs, the interface shows a row for every replay with its live
status, elapsed time, and the file being written. That list is kept after the
batch ends as the record of which replays reached the video.

No files are installed, modified, or deleted by the setup checks. Afterimage
reads the OBS WebSocket configuration and never writes it, so switching the OBS
WebSocket server on remains a one-time action the user performs in OBS.
Afterimage detects which of those situations applies and gives the matching
instruction. It does not create or change OBS scenes, sources, or audio, and it
does not verify that a capture has picture or sound.

The native adapters and UI are covered by automated tests, but live GGST input
and process-memory operation still need end-to-end verification on both target
operating systems before this should be called a stable release.
