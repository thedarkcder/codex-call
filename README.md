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

## Project status

Codex Call is an experimental prototype under active development. Incoming call
audio and Codex voice turns work, but the outgoing digital phone path is not yet
proven end to end. Do not rely on it for unattended or important calls.

### Build stages

- [x] Codex plugin with five MCP tools and the `phone-call` skill
- [x] Signed virtual RX, TX, and clock Core Audio devices
- [x] Menu-bar/window control app with consistent routing state
- [x] Standard signed macOS package installer and in-app updater path
- [x] Normal Codex voice: physical microphone → RX → Codex → TX → speakers
- [x] Phone/FaceTime call placement and transition into call mode
- [x] Remote caller audio captured into RX and transcribed by Codex
- [x] Codex generates spoken replies during a live call
- [x] Codex replies are audible through the local monitor
- [ ] Make TX the single authoritative Codex-output stream for both Phone and
      local monitoring
- [ ] Prove that Phone/FaceTime opens `Codex Virtual TX` as its microphone
- [ ] Verify channel mapping, clocking, and remote volume with recorded evidence
- [ ] Pass repeated end-to-end calls with clearly intelligible remote audio
- [ ] Complete hang-up, reconnect, and long-call soak testing
- [ ] Publish a production-ready release

### Tests completed

- `doctor`, `audio-status`, `devices`, and physical-microphone `selftest` pass on
  the development Mac.
- A generated speech sample sent through TX in normal mode was audible on the
  physical speakers.
- A digital TX loopback returned the same `0.25` peak written into the installed
  unity-gain driver, confirming that the virtual device itself did not attenuate
  that test signal.
- A call to the UK speaking-clock service confirmed remote audio reached Codex;
  Codex transcribed it, generated replies, and those replies were heard locally.
- A live person reported possibly hearing Codex very faintly. Because the local
  monitor currently uses a separate process tap, that result is inconclusive and
  may have been acoustic speaker leakage rather than the digital TX path.

### Known gaps

- Local monitoring is not currently taken from the exact TX stream consumed by
  Phone, so hearing Codex locally does not prove that the caller received it.
- The Phone/FaceTime input-device attachment has not been instrumented and
  proven during an active call.
- The uninstalled 0.1.9 gain experiment is not considered a confirmed fix;
  signal gain should not mask an unverified routing or channel-selection fault.
- Hang-up detection and audio graph recovery still need repeated real-call
  testing across different macOS and hardware configurations.
- MCP cannot directly control the desktop app's private realtime voice session.
  This limits explicit turn steering, but it does not prevent a correct Core
  Audio input/output implementation.

## Contributing

Contributions and reproducible test results are welcome. The most useful help
right now is Core Audio expertise, Phone/FaceTime device-selection diagnostics,
testing on other Apple Silicon Macs, and independently verified call recordings
that identify exactly where the outgoing signal changes.

Please open a GitHub issue before starting a large change. Include your macOS
version, audio hardware, the relevant diagnostic output, exact reproduction
steps, and whether the result was measured at TX, heard locally, or confirmed by
the remote caller. Pull requests should keep the standard package installer as
the only privileged installation and upgrade path.

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

The TX driver applies a clipped 6 dB gain so Codex remains intelligible over
telephone audio. Normal mode compensates that gain before local playback; call
mode applies the same gain to the independent local Codex monitor.

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
open dist/CodexCall-0.1.9.pkg
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
