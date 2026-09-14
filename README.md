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

This is a working prototype. Audio routing and call placement work; two things
are still unreliable (see below).

### Working

- **Plugin** installed into Codex as `codex-call@personal` with MCP tools and a
  `phone-call` skill.
- **Virtual audio devices** `Codex Virtual RX`, `Codex Virtual TX`, and
  `Codex Virtual Clock` (BlackHole-derived, signed, installed to
  `/Library/Audio/Plug-Ins/HAL`).
- **Normal voice** — physical mic → RX → Codex; Codex → TX → speakers.
- **Call placement** — `start_phone_call` switches to call mode and opens the
  Phone/FaceTime dialer.
- **Remote → Codex** — the call app's audio is captured digitally into RX and
  Codex transcribes it.
- **Menu-bar + window app** that installs the driver/helper/plugin and owns the
  audio router (Start/Stop/Quit).

### Not working / unreliable

- **Hearing Codex locally during a real call.** The process tap requires an
  aggregate device, which conflicts with rendering Codex's voice to the
  speakers. Reliable in the simulated test, flaky on real calls.
- **Codex reliably replying on a real call.** It hears the line and sometimes
  replies; the realtime session's turn-taking is not reliably triggered by phone
  audio.
- **Hang-up detection** has missed a hang-up (state can stay `IN_CALL`).
- **Steering the live voice session.** The plugin cannot inject "you're on a
  call, reply now" into Codex's realtime session: MCP tools can't reach it, and
  the desktop app's app-server is stdio-private. This is the core limitation.

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

1. Download **`CodexCall-macos.zip`** from the
   [latest release](https://github.com/thedarkcder/codex-call/releases/latest).
2. Unzip and move **Codex Call.app** to `/Applications`.
3. Double-click it.

The app installs the virtual audio driver (admin password required), the helper,
and the Codex plugin, then starts the router. On first run macOS may ask for
Microphone and Audio Recording permissions.

The app is signed with a Developer ID but not notarized, so Gatekeeper may warn;
if so, right-click the app and choose **Open** once.

### Build from source

```bash
scripts/install.sh
```

or build and launch the app:

```bash
app/install-app.sh
open "/Applications/Codex Call.app"
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

Codex calls `start_phone_call`, which switches to call mode and dials. When done
it calls `end_phone_call` and normal routing is restored.

## Components

```
plugins/codex-call/     Codex plugin (manifest, MCP server, skills)
native/driver/          Core Audio driver build/install (RX, TX, Clock)
native/helper/          Swift routing helper + CLI
app/                    Menu-bar + window app (installs everything)
scripts/                install / uninstall
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
