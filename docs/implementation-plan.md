# Macam implementation plan

## Requirements and environment

The lasting requirements are in `AGENTS.md`. Initial inspection on 2026-10-27:
macOS 27.0.1 (26A434), arm64; Command Line Tools selected at
`/Library/Developer/CommandLineTools`; Swift 6.4; SDK, clang, and codesign available.
No full Xcode application is required for the proposed implementation.

## Architecture hypotheses

1. **A (implemented; native input, Chrome capture, and Chrome Stop/Start verified):** create a stereo, unmuted Core Audio process tap,
   then a public aggregate device named **Macam Audio** containing that tap.
   Verify input streams, formats, clocking, independent enumeration, and non-silent
   input from a second process. The first runtime test succeeded (see below).
2. **B (fallback, unverified):** capture through a private tap/aggregate and write
   the copy to BlackHole 2ch by explicit device ID. BlackHole must never become a
   default device. Requires separate installation and exposes BlackHole's name.
3. **C (deferred):** app capture plus custom HAL virtual input. Begin only after
   documenting why A and B cannot meet the requirements.

## Work sequence

1. Read current SDK headers and Apple process-tap documentation. Build a small
   command-line diagnostic within the app bundle, before polishing the interface.
2. Snapshot default device UIDs and readable volume/mute properties. Create tap
   and aggregate, inspect streams and formats, and read from an independent
   process. Observe permission handling; require actual audio for non-silence.
3. Resolve specific gaps with targeted FineTune source inspection. Record pinned
   revisions, actual file paths, license, and significant adaptations.
4. Implement lifecycle/resource ownership, process discovery including helpers,
   source/receiver selection, meter, and the minimal menu-bar UI.
5. Add recovery for process changes, device/rate changes, sleep/wake, and crashes.
   Keep callbacks bounded and free of allocation, locks, logging, and UI work.
6. Package with stable identifier `org.macam.Macam`, permission descriptions,
   local signing, and shell build/run scripts using Command Line Tools.
7. Verify independent app capture and settings preservation, lifecycle/restarts,
   sustained audio/drift, and device switching where available. Report blocked or
   manual checks explicitly; update this plan with evidence and conclusions.

## Questions and uncertainties

- Public input: verified by an independent native process and Google Chrome on
  macOS 27.0.1. Other applications/OS versions remain interoperability checks.
- Clocking: the tap-only aggregate supplies stereo 48 kHz input without a physical
  subdevice; two-minute callback continuity passed. Hardware changes and multi-hour
  drift still require testing.
- Permission handling: the app includes audio-capture and input-usage descriptions.
  Browser microphone permission can be temporary and device IDs can be hidden even
  for an authorized live track. A zero-filled callback alone proves no permission.
- Helpers: responsibility/ancestry/path resolution and process-ID updates are
  implemented; shared WebKit identities are isolated. Exhaustive helper relaunch
  testing remains open. The optional private responsibility lookup is documented.
- Playback exclusion is optional and Off by default. Macam itself is always
  excluded. The UI can explicitly exclude an app or all browsers. Source and
  receiver may be Chrome or Safari, including the same browser.
- Crash recovery: SIGKILL left a public aggregate; exact-journal cleanup and restart
  passed. Ownership is never inferred from an arbitrary device name.
- The user verified normal original playback and Chrome capture/reconnection.
  Physical controls, headphone switching, sleep/wake, hardware rate changes, and
  saved long recordings remain in the manual verification checklist.

## Implementation status

### 0.2 browser routing and public project requirements

Implemented update: default playback exclusion to Off, retain explicit application
or all-browser exclusion as an opt-in, and cover Chrome → Chrome, Safari → Safari,
Chrome → Safari, Safari → Chrome. Migrate the old implicit Chrome receiver setting
to Off while preserving source choices. Update CLI, UI, regression tests, and docs.

The test receiver must be browser-neutral, launch in either Chrome or Safari, and
include an offline tone generator page for an independent source tab. The receiver
never monitors its input. Same-browser capture is application-wide: Core Audio
cannot distinguish the receiving tab's playback from other tabs in that browser.
No per-tab isolation or feedback immunity should be claimed.

Prepare community-facing README, contributing/security/support guidance, changelog,
issue templates, and CLT-based CI with explicit mocked/native/browser test evidence.
Prior Chrome runtime results remain historical evidence. All four routes require
new runtime results; selection-model and browser mocks alone do not establish them.
The user subsequently reported all four routes passing with the updated browser-neutral
receiver and stereo tone source. Environment: macOS 27.0.1, Chrome 156.0.8078.49,
Safari 27.0.1. This is user-observed non-silent capture, not browser automation.
The per-route Whole system/selected-app choice was not separately recorded.

Completed: optional exclusion and legacy-preference migration, source-model tests
for four routes, Chromium/Safari API mocks, MIME feature detection, Web Audio
user-gesture activation, browser-neutral test menu, silent-on-open tone source,
community README/contributing/support/security/changelog, issue/PR templates,
package/checksum script, and macOS CI definition. CI execution remains unverified
until run on a hosted repository; local deterministic checks have passed.

The native audio path, menu bar, source/receiver selection, meter, ownership and
cleanup, recovery hooks, CLT build/signing, offline browser diagnostic, source and
meter tests, and native integration harness are implemented. Option A is retained
based on actual independent and browser capture. Remaining verification is listed
in `docs/verification.md`; untested recovery hooks are not marked as passed.

## Primary references

- Apple sample: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- CATapDescription: https://developer.apple.com/documentation/coreaudio/catapdescription
- FineTune: https://github.com/ronitsingh10/FineTune (GPL-3.0)
  - Verify current paths before reading: `FineTune/Audio/Engine/ProcessTapController.swift`
  - `FineTune/Audio/Engine/AudioEngine.swift`
  - `FineTune/Audio/Monitors/AudioProcessMonitor.swift`
  - `FineTune/Audio/Engine/TapResources.swift`
  - `FineTune/Audio/Engine/OrphanedTapCleanup.swift`
- BlackHole: https://github.com/ExistentialAudio/BlackHole

## Verification record

- Environment inspection succeeded. The app compiles and ad-hoc signs with CLT.
- The command sandbox returns an empty Core Audio device list. Actual audio tests
  require running the diagnostic outside that sandbox; an empty list is not a
  successful settings-preservation test.
- First option A runtime test on macOS 27.0.1: public tap, `.unmuted`, public
  tap-only aggregate, no physical subdevices, no `tapautostart`, no drift correction.
  Input enumerated as stereo Float32 PCM, 48 kHz in an independent process.
- Owner: 30 seconds, 1,440,256 frames, 2,878,786 nonzero samples, zero sample-time
  discontinuities. Independent receiver: 8 seconds, 384,000 frames, 767,531 nonzero
  samples, zero sample-time discontinuities. This is actual native input capture,
  not just visibility. Existing audible sources were active during the test.
- Default input/output/system-output UIDs and every readable volume/mute property
  on unrelated devices were equal before, during, and after Start/Stop.
- BlackHole 2ch was already installed. Macam did not install or configure it.
  Option B is unnecessary given the successful native path; option C is deferred.
- Initial 0.1 target was Google Chrome. The user verified non-silent input in their real Chrome
  receiving application with normal playback. An apparent no-input/restart failure
  was traced in the diagnostic page to anonymous enumeration despite an authorized
  live track labeled “Macam Audio (Aggregate)”. The page had required an exact
  unqualified name and an enumerated ID. Version 4 accepts the observed qualified
  name and reuses the verified authorized track when IDs are hidden. The user
  confirmed non-silent capture and automatic Stop/Start reconnection in v4.
  Browser evidence is user-reported. Pure JS regression tests reproduce temporary
  permission, qualified labels, hidden IDs, exact selection, reconnection, and Stop.
- Two-minute independent selected-Safari capture passed: 5,760,000 stereo frames,
  2,770,525 nonzero samples, zero sample-time discontinuities. Empty-source
  isolation, SIGTERM, SIGKILL/journal recovery, and restart passed. Settings matched
  throughout. See `docs/verification.md` and its archived JSON.
- After the helper-isolation refinement, live source updates retained the same
  aggregate ID, captured selected audio, and returned to silence after deselection.
  Sanitized meter tests and shared-helper/source-exclusion regression tests passed.
- Menu-bar Start and the Chrome test were exercised by the user. Physical controls,
  sleep/wake, rate changes, browser restart, saved website recordings, and multi-hour
  drift remain manual checks unless added to the verification record.

## FineTune investigation and adaptations

Pinned revision: `2285279d36d3f8115c1c2d4aecd904f1bdf96a51`. All five requested
paths exist at this revision; targeted files were downloaded into ignored
`.build/references/` for inspection. License is GPL-3.0 with Ronit Singh's notice.

- `ProcessTapController.swift`: confirms tap/aggregate dictionary keys and
  format-aware setup. Macam instead uses `.unmuted`, public visibility, and a
  tap-only input aggregate; no output subdevice, replay, EQ, crossfade, default
  device changes, or volume controls. The SDK says `tapautostart` requires a
  private aggregate, so Macam intentionally omits it.
- `TapResources.swift`: confirms callback-stop/destroy, aggregate-destroy,
  tap-destroy teardown order.
- `AudioProcessMonitor.swift`: helper grouping uses a guarded private
  responsibility lookup plus process ancestry. Macam documents that optional
  private API and its fallbacks. macOS 26 explicit bundle-ID matching is used for
  app-specific identities. Shared WebKit bundle IDs must not broaden app-specific
  selections, so those helpers use resolved process IDs. Automatic raw-bundle
  process restoration is disabled to preserve isolation.
- `OrphanedTapCleanup.swift`: name-prefix cleanup is too broad for Macam's
  ownership guarantee. Macam uses an exclusive process lock and a journal of
  exact UUIDs before reclaiming its public aggregate and taps.
- `AudioEngine.swift`: read only for lifecycle context; the processing/replay
  architecture is not needed for a public input.
