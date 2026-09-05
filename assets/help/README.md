# Help images

Images shown inside Afterimage when it explains a step the user has to perform
outside the application.

## Needed: `obs-websocket-settings.png`

An annotated screenshot of the OBS Studio dialog at
**Tools > WebSocket Server Settings**, with the **Enable WebSocket server**
checkbox marked.

This is the one wall Afterimage deliberately does not remove. Afterimage reads
the OBS WebSocket configuration but never writes it, so enabling the server is
a one-time action only the user can take, and a picture of the exact dialog is
the clearest way to describe it.

Requirements for the capture:

- OBS Studio 28 or later, default theme.
- The dialog only, not the whole desktop.
- A visible marker on the "Enable WebSocket server" checkbox.
- No personal information: blank or redact the server password field.

`ObsSetupGuide` loads this file through an `errorBuilder`, so the application
still runs and still shows the written instructions while the image is absent.
