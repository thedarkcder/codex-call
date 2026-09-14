---
name: call-test
description: Diagnose and self-test the Codex Call audio routing. Use when the user asks to test, debug, or check the phone call plugin or its audio.
---

# Codex Call test

Run the diagnostics and audio self-test.

## Steps

1. Report routing status:

   ```bash
   codex-call-helper audio-status
   ```

   Expected format:

   ```text
   Plugin: loaded
   Native helper: running
   Virtual RX: found
   Virtual TX: found

   Mode: NORMAL

   Physical mic:
   <name>

   Physical output:
   <name>

   Codex input:
   Codex Virtual RX

   Codex output:
   Codex Virtual TX

   Apple call capability:
   available
   ```

2. Run the checks:

   ```bash
   codex-call-helper doctor
   ```

3. Capture a short sample from the physical microphone to confirm input works:

   ```bash
   codex-call-helper selftest
   ```

4. If the user is running the desktop app, confirm the realtime voice is still audible
   and that speaking to Codex works normally. If audio is broken, run:

   ```bash
   codex-call-helper restore
   ```

   to return the system to the original physical devices, then report the failure.

## Notes

- Never report success unless `doctor` returns all checks OK.
- The router must be running for audio to pass through `Codex Virtual RX`/`TX`.
