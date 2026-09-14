---
name: call-setup
description: Install and configure the Codex Call virtual audio component, routing helper, and Apple calling capability. Use when the user asks to set up, install, repair, or check the phone call plugin.
---

# Codex Call setup

Set up the audio layer that lets Codex make phone calls.

## Steps

1. Prefer the signed, notarized `CodexCall-<version>.pkg` from the latest GitHub
   release. Open it with macOS Installer and let the user approve Installer's
   standard authorization request.
2. For a source checkout, build the same package and open it:

   ```bash
   installer/build-pkg.sh
   open dist/CodexCall-<version>.pkg
   ```

   Do not install components with `sudo`, temporary shell scripts, AppleScript
   authorization, or direct copies into `/Library` and `/usr/local`. The signed
   package is the only supported privileged installation and upgrade path.
3. Open `/Applications/Codex Call.app`. The app performs user-level setup,
   refreshes the Codex plugin, and starts the router without an admin prompt.
4. Run diagnostics:

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

- macOS Installer owns administrator authorization for the Core Audio driver;
  Codex Call never asks for or handles the password itself.
- Use the app's **Check for Updates…** command for upgrades. It verifies the
  downloaded package's Developer ID Installer team before opening Installer.
- If `Codex Virtual RX`/`Codex Virtual TX` are missing after install, `coreaudiod` may
  need a restart. Re-run the package rather than issuing privileged repair commands.
- Never claim setup succeeded unless `doctor` reports all checks OK.
