# Codex Call

A macOS plugin that lets Codex place and conduct phone calls using Apple's
Phone/FaceTime calling and Codex's existing realtime voice.

```
User:  "Call my dentist and ask if they have anything Tuesday afternoon."
Codex: "Calling."
       [call connects, Codex talks to the receptionist]
Codex: "They had 2:30 and 4:15. I booked 4:15."
```

## Disclaimer

This is an **experimental prototype**. Use it at your own risk.

- **It places real phone calls.** Calls may incur charges from your carrier or
  the number called. You are responsible for any charges.
- **It routes and processes audio.** Your microphone and the call audio are
  routed through virtual audio devices and Codex. Do not use it for sensitive
  conversations you would not want processed by an AI service.
- **Recording/consent laws apply.** Recording or transcribing calls is illegal
  in some jurisdictions without consent, and many places require that the other
  party be told they are speaking to an AI. **You** are responsible for
  complying with all applicable laws and for disclosing that an AI is on the
  call.
- **AI can be wrong.** Codex may mishear, misunderstand, or say something
  incorrect, and must not be relied on for legal, medical, financial, or other
  consequential decisions or commitments.
- **No warranty.** Provided "as is", without warranty of any kind, express or
  implied. The authors are not liable for any damages arising from its use.
- **Not affiliated** with OpenAI or Apple. "Codex", "ChatGPT", "FaceTime", and
  "Apple" are trademarks of their respective owners.

## Status

This is a working prototype. The routing and lifecycle reliability fixes below
are implemented; a real-call soak test is still required on each supported macOS
release and audio-device combination.

### Working

- **Plugin** installed into Codex as `codex-call@personal` with MCP tools and a
  `phone-call` skill.
- **Virtual audio devices** `Codex Virtual RX`, `Codex Virtual TX`, and
  `Codex Virtual Clock` (BlackHole-derived, signed, installed to
  `/Library/Audio/Plug-Ins/HAL`).
- **Normal voice** — physical mic → RX → Codex; Codex → TX → speakers.
- **Call placement** — `start_phone_call` switches to call mode, opens the
  Phone/FaceTime dialer, and waits for real call audio before handing Codex its opening
  line.
- **Remote → Codex and local monitor** — the call app's audio is captured
  digitally into RX and mixed to the physical speakers.
- **Codex → phone and local monitor** — TX is consumed by the call app as its
  microphone and mixed to the physical speakers through one output callback.
- **Menu-bar + window app** that configures the user-level Codex plugin, owns
  the audio router, and provides a signed-package update check.

### Reliability fixes

- The router fans one tapped source out to RX and the local monitor, and mixes
  remote + Codex audio into a single physical-output IOProc.
- Core Audio IO is stopped before an aggregate device or process tap is
  destroyed; failed graph builds clean up all partially-started IOProcs.
- A changed Phone/FaceTime audio-process set causes a complete tap + aggregate
  rebuild instead of leaving the router attached to a stale process object.
- State remains `STARTING_CALL` until call audio actually becomes active.
  Hang-up detection follows the call processes' active input/output audio and
  returns to `NORMAL` after activity ends, even when the app stays open.
- The call skill ends Codex's assistant turn immediately after its opening line and
  leaves the call active. It does not poll state between voice turns, allowing the
  remote participant's RX audio to trigger Codex's next normal voice turn.
- `end_phone_call` now terminates the active Phone/FaceTime app before restoring
  routing, and reports when macOS does not confirm the hang-up.
- The app compares helper contents rather than file size and safely restarts an
  older running helper after an update.
- Restore now resets the default system-output device as well as input/output.

### Remaining platform limitation

The plugin still cannot directly append instructions to, or force a turn in,
the desktop app's already-running realtime session. MCP and the renderer-owned
realtime transport are separate. The strengthened routing and audio-activity
state remove several causes of apparent silence, but a true realtime-session
steering API would require a Codex desktop integration point.

## Architecture

Codex always uses two fixed devices:

```
Codex input  = Codex Virtual RX
Codex output = Codex Virtual TX
```

The helper changes what is routed behind those devices.

Normal mode:

```
physical mic ─▶ router ─▶ RX ─▶ Codex
Codex ─▶ TX ─▶ router ─▶ physical output
```

Call mode:

```
remote caller ─▶ call app ─▶ process tap ─▶ RX ─▶ Codex
Codex ─▶ TX ─▶ phone microphone ─▶ remote caller
```

RX and TX are isolated, so Codex never hears itself.

## Requirements

- macOS 14.2+ (Core Audio process taps)
- Xcode command line tools (to build the driver and helper)
- A Developer ID or Apple Development signing identity
- An iPhone with Continuity calling enabled (for `tel:` calls)

## Install

### Download (easiest)

1. Download **`CodexCall-<version>.pkg`** from the
   [latest release](https://github.com/thedarkcder/codex-call/releases/latest).
2. Open the package and complete the standard macOS Installer flow.
3. Installer opens **Codex Call** when installation completes. If no graphical
   user is logged in, open it later from `/Applications`.

The Developer ID-signed package installs the app, helper, and virtual audio
drivers. Installer owns the one administrator-authorization step; Codex Call
does not create temporary root scripts, invoke AppleScript authorization, or
handle your password. On first launch the app installs the user-level Codex
plugin and starts the router. macOS may then ask for Microphone and Audio
Recording permissions.

Release packages are Developer ID signed, notarized, and stapled so Gatekeeper
can verify the publisher and package integrity.

### Updates

Choose **Check for Updates…** from the app window or menu-bar menu. The app:

1. reads the latest GitHub release,
2. downloads its `.pkg` asset,
3. verifies that it is signed by the expected Developer ID Installer team, and
4. opens the standard macOS Installer.

Update checks are user-initiated. The app never produces a surprise password
prompt at launch and never performs an unattended privileged installation.

### Build from source

```bash
installer/build-pkg.sh
open dist/CodexCall-0.1.4.pkg
```

`scripts/install.sh` and `app/install-app.sh` are retained as developer
convenience wrappers; both build the same package and open it in Installer.
They do not call `sudo` or create an ad-hoc privileged script.

A distributable package requires both a **Developer ID Application** identity
and a **Developer ID Installer** identity. Set `REQUIRE_SIGNING=1` to make a
missing installer identity a build error. Set `NOTARY_PROFILE` to a keychain
profile created for `notarytool` to notarize and staple the package:

```bash
REQUIRE_SIGNING=1 NOTARY_PROFILE=codex-call installer/build-pkg.sh
```

### One-time Codex setting

Set **Codex → Settings → Voice → Microphone** to **`Codex Virtual RX`** so
Codex stays on RX when call mode repoints the system default input.

## Usage

Normal voice works as usual once installed.

To place a call, ask Codex (voice or text):

```
Call +44... and ask if they have anything Tuesday afternoon.
```

Codex calls `start_phone_call`, which switches to call mode, dials, and waits until call
audio is active. Codex says its prepared opening line, yields to listen for the remote
participant, and replies one voice turn at a time. When the goal is complete it calls
`end_phone_call` and normal routing is restored.

## Components

```
plugins/codex-call/     Codex plugin (manifest, MCP server, skills)
native/driver/          Core Audio driver build/install (RX, TX, Clock)
native/helper/          Swift routing helper + CLI
app/                    Menu-bar + window app, router owner, and updater
installer/              signed macOS package build and fixed package scripts
scripts/                developer wrappers and manual uninstall
```

## Diagnostics

```bash
codex-call-helper doctor
codex-call-helper audio-status
codex-call-helper devices
codex-call-helper selftest
codex-call-helper restore
```

## Uninstall

```bash
scripts/uninstall.sh
```

## License / attribution

The virtual audio driver is derived from
[BlackHole](https://github.com/ExistentialAudio/BlackHole) (GPL-3.0). See the
upstream project for the full license text.
