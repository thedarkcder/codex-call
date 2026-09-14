---
name: call-setup
description: Install and configure the Codex Call virtual audio component, routing helper, and Apple calling capability. Use when the user asks to set up, install, repair, or check the phone call plugin.
---

# Codex Call setup

Set up the audio layer that lets Codex make phone calls.

## Steps

1. Locate the plugin repository root (the directory containing `scripts/install.sh`).
2. Run the installer:

   ```bash
   scripts/install.sh
   ```

   This builds the `Codex Virtual RX` / `Codex Virtual TX` Core Audio driver and the
   routing helper, installs the driver (requires an administrator password), configures
   the system default audio devices, and installs the router agent.
3. Run diagnostics:

   ```bash
   codex-call-helper doctor
   ```

4. Report the result to the user in the setup format:

   ```text
   Codex Call setup

   Virtual RX: OK
   Virtual TX: OK
   Physical microphone: <name>
   Physical output: <name>
   Codex realtime input: Codex Virtual RX
   Codex realtime output: Codex Virtual TX
   Apple calling: available

   Ready to make calls.
   ```

## Required one-time setting in Codex

Set **Codex → Settings → Voice → Microphone** to **`Codex Virtual RX`**. This pins Codex's
input to RX so that call mode can reuse TX for the phone's microphone. Without this, Codex
follows the system default input and will hear itself during a call.

## Permissions

macOS will ask for two permissions the first time they are needed:

- **Microphone** for `Codex Call Helper` (normal routing).
- **Audio Recording** for `Codex Call Helper` (capturing the call app's audio in call mode).

Approve both. If a permission was denied, reset it and retry:

```bash
tccutil reset Microphone com.codexcall.helper
tccutil reset AudioCapture com.codexcall.helper
```

## Notes

- The installer needs `sudo` for the Core Audio driver. Ask the user before running it.
- If `Codex Virtual RX`/`Codex Virtual TX` are missing after install, `coreaudiod` may
  need a restart (`sudo launchctl kickstart -k system/com.apple.audio.coreaudiod`).
- Never claim setup succeeded unless `doctor` reports all checks OK.
