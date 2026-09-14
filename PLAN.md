# Codex Phone Call Plugin — Implementation Plan

Status: research complete; Milestone 1 **implemented** (builds + install scripts ready).
Decisions taken: desktop app target, BlackHole-derived driver, Developer ID available,
build Milestone 1 now.
Target host inspected: macOS 26 (arm64), Codex CLI 0.144.6, ChatGPT.app 26.908.40834
(bundled `codex` binary), Xcode 26 / Swift 6.3 / clang 21.

---

## 0. Recommendation up front

Build this as a **Codex plugin** (personal marketplace) with a bundled native helper.
**No fork of `openai/codex` is required for Milestone 1.**

The plugin-first design is viable because:

1. Codex's realtime voice is a normal WebRTC client. It captures from a selected
   microphone and plays to the **system default output**. It does not need to know the
   audio is coming from a virtual device.
2. macOS virtual audio devices are still supported on this machine
   (`MSTeamsAudioDevice.driver`, `ZoomAudioDevice.driver`, `ParrotAudioPlugin.driver`
   are all installed in `/Library/Audio/Plug-Ins/HAL/`).
3. Plugins can bundle arbitrary executables and expose them as MCP servers, and can
   bundle skills/instructions. Everything the call flow needs can live behind MCP tools
   plus a long-running helper.

Two host constraints materially shape the design and must be accepted (see §7):

- The desktop realtime client has **no output-device selector**. Output always goes to
  the **system default output device**. Therefore `Codex Virtual TX` must become the
  system default output, and the helper must pass it through to the physical output in
  normal mode.
- The desktop realtime client **does** have an input-device selector
  (`microphoneInputDeviceId`, default = system default). We leave it on "system default"
  and make `Codex Virtual RX` the system default input.

If the user runs Codex via the **CLI** realtime voice (`/voice`), there is a cleaner,
first-class path: the CLI config exposes `[audio] microphone` and `[audio] speaker`
(`RealtimeAudioToml`), so Codex can be pinned to RX/TX explicitly without touching system
defaults. The desktop app does not use that config for its renderer-owned WebRTC path.

---

## 1. What was inspected

| Area | Location | Method |
| --- | --- | --- |
| Plugin format | `~/.codex/skills/.system/plugin-creator/` | read spec + scaffold scripts |
| Plugin manifest examples | `~/.codex/.tmp/bundled-marketplaces/openai-bundled/plugins/*` | read `plugin.json`, `.mcp.json`, launcher |
| Plugin CLI | `codex plugin --help`, `codex plugin list` | CLI |
| Realtime voice (desktop) | `/Applications/ChatGPT.app/Contents/Resources/app.asar` | string/asset analysis |
| Realtime voice (CLI/app-server) | `.../Resources/codex` | symbol/string analysis |
| Config schema | `codex` binary `ConfigToml` symbols, `~/.codex/config.toml` | string analysis |
| Audio devices | `system_profiler SPAudioDataType`, `/Library/Audio/Plug-Ins/HAL` | system |
| Toolchain | `xcode-select`, `clang`, `swift` | system |

---

## 2. Findings — Codex plugin architecture

- Plugin root: `~/plugins/<name>/`, manifest at `.codex-plugin/plugin.json`.
- Personal marketplace: `~/.agents/plugins/marketplace.json` (discovered implicitly).
  No marketplace file exists on this machine yet.
- Manifest fields accepted by the ingestion validator: `name`, `version`, `description`,
  `author`, `homepage`, `repository`, `license`, `keywords`, `skills`, `mcpServers`,
  `apps`, `interface`. **`hooks` is rejected by validation** (the bundled OpenAI plugins
  use hooks, but that is outside the workspace ingestion schema — do not rely on hooks).
- MCP servers are declared either inline or via `./.mcp.json`. Server entries support
  `command`, `args`, `cwd`, `env_vars`, `startup_timeout_sec`, `tool_timeout_sec`, and
  per-tool `approval_mode`. A bundled launcher script pattern is used by OpenAI's own
  `codex-app-tools` plugin to locate a Node runtime.
- Skills are directories with `SKILL.md` (YAML frontmatter `name`/`description`) plus
  optional `references/`, `scripts/`, `assets/`, `agents/openai.yaml`.
- Dev loop: `python3 update_plugin_cachebuster.py <path>` then
  `codex plugin add <name>@personal`, then a new thread picks up the change.
- Plugins can ship native binaries and run them as MCP servers; there is no sandbox
  restriction preventing a long-running helper or a `sudo`-assisted installer, but the
  user must approve elevation.

Conclusion: the requested plugin layout
(`call skill` + `MCP server` + `macOS helper` + `virtual audio component` + `installer`)
maps cleanly onto a single plugin folder.

---

## 3. Findings — realtime audio interface

### 3.1 Desktop app (the primary UX)

Realtime voice runs in the **Electron renderer** as a WebRTC client:

- `RTCPeerConnection` + data channel; model `gpt-live-1-codex`, version `v3`.
- Microphone: `navigator.mediaDevices.getUserMedia({ audio: { deviceId } })`.
  The chosen device comes from the setting **`microphoneInputDeviceId`** (UI:
  Settings → Voice → Microphone, description "Used for voice chat and dictation").
  `enumerateDevices()` is filtered to `audioinput`; the default is **system default**.
- Output: on `ontrack`, the remote stream is assigned to a hidden
  `document.createElement("audio").srcObject` and `play()` is called.
  **`setSinkId` is never used and there is no output-device setting** → the audio plays
  to the **system default output device**.
- The mic is refreshable live (`refreshInput`, `setMuted`, `getStream`), so the app can
  re-open a device mid-session, but we do not need that if RX/TX are stable.
- Realtime audio is also observable/controllable over the app-server protocol
  (experimental, not exposed through MCP):
  `thread/realtime/start|append|stop|list` and notifications
  `thread/realtime/started|sdp|transcript/delta|transcript/done|output/...|closed|error|item/...`,
  with `ThreadRealtimeAppendAudioParams`, `AppendSpeechParams`, `AppendTextParams`.

### 3.2 CLI TUI (alternative)

- A `/voice` command exists and the TUI keymap has `toggle_voice_mute`.
- The CLI config has `[audio] microphone` / `[audio] speaker` (`RealtimeAudioToml`) and
  `[realtime] transport = webrtc|websocket`, `voice`, `version`. This is a first-class
  way to pin Codex to RX/TX, but it belongs to the CLI/app-server audio path, not the
  desktop renderer path.

### 3.3 Implication

The brief's "Codex always uses RX/TX, helper switches behind them" works for both paths:

- Desktop: RX/TX must be the **system default input/output**.
- CLI: RX/TX can be set explicitly via `[audio]`.

---

## 4. Feasibility verdict vs. forking Codex

| Fork-fallback trigger (from brief) | Verdict |
| --- | --- |
| 1. Realtime can't be told the participant changed owner → remote | **Not proven blocking.** Instructions can be injected per call via skill/developer instructions. Live mid-session instruction swap is the main open question; if it can't be done, this is the one likely fork point. |
| 2. Realtime can't use persistent virtual devices | **Not blocking.** Desktop uses system default + mic setting; CLI has explicit device config. |
| 3. Plugin/MCP can't coordinate realtime state | **Partially open.** MCP can drive the helper and set state/instructions, but cannot directly mutate a running realtime session. Delegation (`create_thread`/`fork_thread`) exists for tool use. |
| 4. Plugin can't manage call lifecycle | **Not blocking.** `open "tel:..."` / FaceTime control is reachable from the helper. |

Milestone 1 does not touch any of these. No fork.

---

## 5. Proposed architecture

```
plugins/codex-call/                 Codex plugin (manifest, skill, MCP server)
native/driver/                      HAL AudioServerPlugIn → Codex Virtual RX + TX
native/helper/                      routing engine + control CLI + watchdog
scripts/                            install / uninstall / doctor
```

### 5.1 Virtual devices

Two isolated loopback devices installed as a HAL plug-in bundle in
`/Library/Audio/Plug-Ins/HAL/`:

- `Codex Virtual RX` — presents an input stream to Codex. The helper writes physical
  (or call) audio to its output side; the loopback exposes it on the input side.
- `Codex Virtual TX` — presents an output stream to Codex. Codex writes its voice; the
  helper reads the input side and forwards it.

RX and TX are separate devices with separate clocks and no internal cross-connection, so
Codex can never hear its own output. This directly satisfies the "two independent
directions, no feedback" requirement.

### 5.2 Normal mode

```
physical mic ──▶ helper ──▶ RX(output side) ──▶ RX(input side) ──▶ Codex
Codex ──▶ TX(output side) ──▶ TX(input side) ──▶ helper ──▶ physical output
```

System defaults: input = `Codex Virtual RX`, output = `Codex Virtual TX`.

### 5.3 Call mode

```
phone/FaceTime output ──▶ RX(output side) ──▶ RX(input side) ──▶ Codex
Codex ──▶ TX(output side) ──▶ TX(input side) ──▶ phone/FaceTime input
```

The helper sets the system default output to RX (so the phone writes remote audio into
RX) and the system default input to TX (so the phone reads Codex voice from TX), then
stops its normal-mode passthrough. This depends on the phone app honoring system default
devices — a Milestone 2 verification item. If it does not, fall back to extra loopback
endpoints dedicated to the call app.

### 5.4 Control plane

- MCP server (Node, no deps) exposes the required tools and shells out to the helper CLI.
- Helper CLI is the single source of truth for state and routing; it writes a state file
  and can be run by a launchd agent for watchdog/fail-safe.
- State machine: `NORMAL → STARTING_CALL → IN_CALL → ENDING_CALL → NORMAL`, plus `ERROR`.
- On helper crash or uninstall, system defaults must be restored to the physical devices
  automatically; otherwise all system audio is lost.

---

## 6. Milestone 1 — normal virtual audio (only this is in scope now)

Goal: prove ordinary Codex realtime voice works through RX/TX with no echo/feedback and
no meaningful latency regression. No calling logic.

Deliverables:

1. `CodexVirtualAudio.driver` HAL plug-in exposing RX and TX (custom, or a renamed
   BlackHole-derived build — see decision D1).
2. `codex-call-helper` with commands: `devices`, `route normal`, `route call`,
   `status`, `setup`, `doctor`, `restore`.
3. Routing engine: capture physical mic → RX; TX → physical output; single clock master
   with sample-rate conversion; < ~20 ms added latency.
4. Codex pinned to RX/TX:
   - desktop: set system default input = RX, output = TX (leave `microphoneInputDeviceId`
     on system default);
   - CLI: `[audio] microphone = "Codex Virtual RX"`, `speaker = "Codex Virtual TX"`.
5. Fail-safe: restore physical defaults on crash/uninstall/logout.
6. `/call-setup` and `/call-test` skill commands reporting the required diagnostics.

Acceptance (from brief):

- user talks to Codex, Codex hears the user, replies;
- no echo, no feedback, no substantial latency regression;
- Codex never receives its own voice;
- physical mic and physical speakers are reached only through the helper.

Tag: `milestone/normal-virtual-audio`.

### 6.1 Implemented in this pass

| Component | Path | State |
| --- | --- | --- |
| HAL driver build (RX + TX, BlackHole-derived, pinned commit) | `native/driver/build.sh` | builds, unsigned until `CODESIGN_IDENTITY` is set |
| Driver install/uninstall (privileged) | `native/driver/install.sh`, `uninstall.sh` | ready |
| Routing helper (Swift, Core Audio IOProc duplex router) | `native/helper/Sources/main.swift` | builds; `devices`, `status`, `audio-status`, `setup`, `restore`, `run`, `route`, `doctor`, `selftest` |
| Helper app bundle for microphone TCC | `native/helper/build.sh` → `CodexCallHelper.app` | ready |
| Router launchd agent (KeepAlive + fail-safe restore) | `scripts/launchd/com.codexcall.router.plist.template` | ready |
| One-shot installer / uninstaller | `scripts/install.sh`, `uninstall.sh` | ready |
| Plugin manifest + MCP server (5 tools) | `plugins/codex-call/` | working; MCP server tested end-to-end |
| Skills: `phone-call`, `call-setup`, `call-test` | `plugins/codex-call/skills/` | ready |

Install (needs the user's admin password for the driver and `/usr/local`):

```bash
scripts/install.sh
```

`call` and `route call` intentionally return "Milestone 2" until the call audio path is
built.

### 6.2 Milestone 2 routing refinement (found during implementation)

The simple system-default swap in §5.3 does **not** work as written, because Codex's
desktop output is always the system default output and the phone app is also expected to
use the system default. Codex and the phone would fight over the same default.

Resolved direction for M2:

- Pin Codex **input** explicitly to `Codex Virtual RX` via the desktop setting
  `microphoneInputDeviceId` (verified to exist).
- Keep the system default **output** = `Codex Virtual TX`, and feed `TX` to the phone by
  setting the system default **input** = `Codex Virtual TX`.
- Capture the phone app's **output** with a Core Audio process tap
  (`AudioHardwareCreateProcessTap`, macOS 14.2+) instead of relying on the phone having a
  device picker, then write it into `RX`. Mute the tap (macOS 14.4+) so remote audio is
  not echoed back through `TX`.

This removes the dependency on the phone app exposing its own device selection (L4) and
keeps Codex pinned to RX/TX. If process taps are unavailable, the fallback is the CLI
`/voice` path with explicit `[audio] microphone`/`speaker` config.

### 6.3 Milestone 2 implemented and verified (audio core)

- Router is now mode-aware (`normal` / `call`) and owns the process tap.
- `call start` / `call end`, and `route normal|call`, are implemented.
- Verified with a simulated remote source (`afplay` tapped via `CODEX_CALL_TAP_PID`):
  - remote audio reaches `RX` (RMS 0.127) in call mode;
  - once the source stops, `RX` is 0.000 while the mic still reads 0.008 → the physical
    microphone is **not** bridged in call mode;
  - defaults become input=`TX`, output=`TX`;
  - the launchd router creates the tap successfully (RX 0.050).
- Helper app now carries `com.apple.security.device.audio-input` and
  `NSAudioCaptureUsageDescription`.

Remaining for M2 sign-off: a real call through FaceTime/Phone to confirm the call app
follows the system default input (`TX`) and that Codex's realtime transcript receives the
remote speaker. Codex input must be pinned to `Codex Virtual RX` in Settings → Voice →
Microphone.

---

## 7. Host-level limitations and assumptions

**L1 — No output-device selection in the desktop client.** Output is hard-wired to the
system default. Consequence: every system sound passes through `Codex Virtual TX` while
the plugin is active. The helper must pass TX → physical output transparently in normal
mode, and must restore defaults if it dies. Accepted risk; mitigation = watchdog + atomic
restore on launchd exit.

**L2 — HAL plug-in install is privileged.** Writing to `/Library/Audio/Plug-Ins/HAL/`
needs admin, and `coreaudiod` must be restarted. On macOS 26 the plug-in may need a valid
Developer ID signature. If no signing identity is available, install may be blocked or
reset on OS updates. Needs confirmation (decision D5).

**L3 — Clock drift / SRC.** The virtual device clock and the physical device clock are
independent. A naive two-device copy will drift and glitch. The routing engine must run a
single graph with one clock master and explicit sample-rate conversion. This is the main
engineering risk in Milestone 1.

**L4 — Phone/FaceTime device selection is unknown.** Assumed to follow system defaults.
Must be verified in Milestone 2. If it has an independent picker, add dedicated call
loopback endpoints (or UI automation as a last resort).

**L5 — Call initiation cannot bypass Apple UI.** `open "tel:+..."` (or FaceTime URLs) may
show Apple's confirmation UI, and iPhone cellular calling from the Mac must already be
enabled by the user. No security/privacy bypass.

**L6 — No first-class "remote participant" concept.** Realtime voice treats all audio as
the session owner's voice. The security boundary ("remote caller is untrusted external
input") must be enforced through injected instructions plus tool-side permission checks,
not by the model's audio context. If live instruction swap during a session is impossible,
this is the strongest fork candidate.

**L7 — MCP cannot directly mutate a live realtime session.** Tools can set state, drive
the helper, and (via delegation) spawn background work, but there is no MCP surface for
`thread/realtime/*`. Instruction/context changes likely require a realtime restart or the
experimental app-server socket.

**L8 — Permissions.** The helper needs Microphone (TCC) consent. The driver install needs
`sudo`. No Screen Recording is required for audio.

**L9 — Only one Codex install / one plugin install.** Satisfied by design; no second voice
stack, no Twilio/SIP, no acoustic loop.

---

## 8. Milestones 2–5 (outline, not started)

- **M2 — digital call audio** (`milestone/digital-call-audio`): manual test call, prove
  remote ↔ RX/TX routing, no self-hearing, interruptions preserved, verify L4.
- **M3 — `/call <number> <goal>`** (`milestone/call-command`): full state machine,
  call-mode instructions, `end_phone_call`, restore routing, report result.
- **M4 — natural language** intent → `start_phone_call(...)`.
- **M5 — tools during calls** (calendar/contacts/notes) via realtime delegation.

---

## 9. Fork-fallback triggers (documented, not acted on)

Create a fork only if, after M1–M3:

1. call-mode instructions cannot be applied to a live realtime session (most likely);
2. the desktop client cannot be pinned to RX/TX without breaking normal voice;
3. an MCP tool cannot coordinate call lifecycle with the realtime session;
4. the plugin cannot manage the call lifecycle.

If triggered: write the blocker report, identify the smallest internal API to expose
(candidates: a realtime "participant/instructions update" method, or an MCP-exposed
binding to the existing `thread/realtime/append*` methods), prefer an upstream PR, and
only then fork minimally.

---

## 10. Decisions

Resolved:

- **D1 — Virtual driver source:** BlackHole-derived, renamed via compile-time defines
  (`kDriver_Name`, `kDevice_Name`, `kPlugin_BundleID`), pinned to commit `ffcb7443`.
- **D2 — Target surface:** desktop app.
- **D3 — System-default hijack accepted:** default input = RX, default output = TX, with
  router passthrough and launchd fail-safe restore.
- **D4 — Routing engine:** custom Swift Core Audio IOProc duplex router.
- **D5 — Signing:** Developer ID available; pass `CODESIGN_IDENTITY` to the build scripts.

Still open:

- GPL obligations for shipping a BlackHole-derived driver (source availability, notices).
- Whether to keep the BlackHole-derived driver long term or replace it with a first-party
  HAL plug-in before public distribution.
- Mic TCC behavior when the router runs under launchd (needs a real install to confirm).
