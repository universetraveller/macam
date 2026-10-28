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

### Reusable release instructions and cache cleanup

Updated release-command, checksum/download, and package-filename examples with
explicit `<version>`, `<arch>`, and checkout-path placeholders. The operational
Homebrew guide links to the latest release and the dated verification records
rather than presenting an old tested version as permanently current. Preserve
actual bundle metadata, changelog history, compatibility requirements, and archived
test results. The maintainer will perform the next version bump; these edits must
remain uncommitted and do not create a tag, push, or publish anything.

Document the local compiler module cache at `.build/module-cache` and the distinct
full `.build` cleanup, including quitting the local app and saving generated
reports/releases before full removal. The initial size check found 269 MB of
compiler cache in 304 MB of generated files. Do not remove files as part of this
documentation update. The bump helper's error uses the version format rather than
a concrete future example; the component preview uses a version placeholder, and
invalid-version fixtures derive from the fixture's current metadata. Seven release
tests and shell syntax checks for 20 documentation examples passed. The bundle
version/build and changelog were confirmed unchanged; edits remain unstaged and
uncommitted for maintainer review and the next version bump.

### Homebrew distribution

Investigated current Homebrew policy and local Homebrew 7.0.11. Official
`homebrew/cask` requires Apple signing/notarization and also applies public-interest
criteria; the current ad-hoc build is not eligible. A project-maintained third-party
tap is the zero-cost distribution path. Homebrew's local signing audit explicitly
distinguishes unofficial taps; installation must still preserve quarantine and
leave any first-launch approval to the user.

Prepare a `macam.rb` cask with each release using the actual app ZIP SHA-256,
architecture, version and OS minimum. Include it in the manifest/checksum set and
mark uncommitted-source recipes as review-only. Use a separate conventional
`homebrew-tap` repository for the eventual `universetraveller/tap/macam` package.
Validate generated Ruby and the real Homebrew DSL without installing an app,
changing global tap/trust settings, or stripping quarantine. Document publication
and upgrades. Do not advertise an install command as live until the public release
and tap are available.

The initial unauthenticated GitHub Releases API returned 404 while the repository
was private. On 2026-10-28 the maintainer made `universetraveller/macam` public and
explicitly authorized completing release and Homebrew publication. The public API
now succeeds, and existing GitHub credentials authorize repository administration
and pushes. At the start of publication there were no public releases or existing
`homebrew-tap` repository.

Publication completed: tagged commit `e8f65274a1873ca6e166aaa13f9e073747395315`
as `v0.3.0`; the release workflow (40644355696) and tag Checks (40644355694) passed.
Downloaded and verified every draft asset, exact source snapshot and clean/tagged
manifest, then published the release. Created `universetraveller/homebrew-tap`
with the exact cask, README and GPL license at commit
`d255d600baf7c7c392acb3d6fb804414a64236b5`. Anonymous app download matched SHA-256
`7f21003f02780e0d705f402a7b99dec79c71b659c68adb43951d188bc5dc745d`.

Homebrew installed and removed the public cask successfully in a temporary app
directory. The app binary matched the release, strict signature verification passed,
and quarantine remained present. The upgrade command correctly reported 0.3.0 as
current; cross-version upgrading remains untested. Gatekeeper rejected the ad-hoc
app; the manual Open Anyway requirement remains documented and no override was
automated. The original local build was reopened after uninstall. README and
verification records now describe the live installation route. No audio-code or
device-settings change was part of this distribution work.

The generated recipe passed Ruby syntax and Homebrew 7.0.11's real content-loader
DSL checks (version, checksum, URL, ARM requirement, Sonoma floor, app, uninstall
quit action). Homebrew's OS dependency model covers major releases; the bundle and
caveat retain the actual 14.2+ requirement. The recipe has no legacy Ruby flight
hooks and does not strip quarantine. Seven release tests passed locally, including
new cask metadata validation and dirty-review marking. These are local checks,
not evidence of a published cask or a live install/upgrade.

References: [acceptable casks](https://docs.brew.sh/Acceptable-Casks),
[third-party taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap),
[tap trust](https://docs.brew.sh/Tap-Trust),
[cask DSL](https://docs.brew.sh/Cask-Cookbook).

### Release preparation and download installation

Implemented release-download installation in the README, including Apple Silicon
assets, minimum OS, Applications placement, manual upgrades/uninstall, capture
permissions, and Apple-linked guidance for ad-hoc/non-notarized launch blocks.
Source builds remain a separate option; no hosted release is assumed to exist.

`scripts/prepare-release.sh` runs the deterministic suite and fresh build, validates
bundle/version consistency, and prepares the versioned app ZIP, matching GPL source
snapshot, checksums, notes from CHANGELOG, and machine-readable provenance. It
round-trips the app ZIP, checks the extracted signature/executable, and rejects
source changes during preparation. `scripts/release.py bump X.Y.Z` updates app/build
versions and starts an empty changelog section that must be filled before packaging.

Initial local preparation passed on the M2 with CLT, including six release-invariant
tests, the existing C/Swift/browser mock suite, all asset checksums, and exact
source/archive comparison. It produced an uncommitted-source review package. Public
0.3.0 assets were rebuilt in CI from the clean tag and checked separately above.
See `docs/verification.md` for actual results and `docs/releasing.md` for usage.

The general GitHub Checks workflow passed for the committed source (runs
40637313073 and 40643290337). The tag-triggered release workflow also passed for
0.3.0 (40644355696). It requires a clean checkout and tag/version/HEAD agreement,
builds on arm64, retains an artifact, and creates an unpublished draft. That reviewed
draft was explicitly published under the maintainer's authorization, followed by
public download and Homebrew install/uninstall checks. Local signature success does
not establish Developer ID/notarization or older-macOS runtime compatibility.

### README positioning refinement

Moved practical advantages and comparisons ahead of the preview, feature list,
and build instructions. Lead with unmuted parallel capture and unchanged system/app
output routing. FineTune's inspected processing/replay path is cited directly;
BlackHole's routing requirements are scoped to its workflows rather than asserting
every user must change system defaults. Loopback's official documentation confirms
that disabling “Mute when capturing” preserves app playback, so this is not claimed
as unique to Macam. Macam's distinction there is the focused free/open-source
workflow and its defaults. No comparative latency/fidelity claim or application
behavior change was introduced.

### 0.3 multi-exclusion and interface refinement

Requested: a set of optional playback exclusions, checkable independently, retaining
Off as the empty default. Decode the 0.2 single explicit exclusion into that set;
continue ignoring 0.1's implicit receiver preference. Repeated CLI `--exclude`
flags add exclusions; `--exclude none` clears them.

Replace the two-line header and separate Start/status items with a one-line header
and compact control row. Show a short status beside Start/Stop and retain detailed
status/error text through an accessible details action. Move browser diagnostics
and permission help into About. Verify the actual AppKit components visually.

Rewrite the public README around purpose, quickstart, multi-choice exclusions,
browser use, evidence/limits, and a primary-source product comparison. Add an
explicit 100% LLM-generated code disclosure without erasing upstream authorship.
The existing responsibility/ancestry helper implementation is attributed as an
adaptation of FineTune, so retain the focused credit, source notices, and GPL-3.0.
The public tap-only input path remains Macam-specific; no output replay or default
device management is introduced by this refinement.

Implemented: set-based exclusions and 0.2 migration, independently checked menu
items, repeated CLI exclusions and clearing, compact Start/status controls with
accessible detailed status, one-line heading, and diagnostics inside About.
Selection tests cover union/removal/clearing, shared-helper isolation, selected
sources, migration/round trips, and CLI accumulation. AppKit previews were rendered
and inspected for the menu states and About tools. README comparison sources are
the upstream FineTune/BlackHole repositories and Rogue Amoeba's Loopback page.
Completed verification: full local test script and native three-second lifecycle
probe with two exclusions. Settings stayed unchanged, input cleanup passed, and no
sample-time gaps were observed. The user confirmed Start/Stop, independent checked
exclusions, and opening diagnostics from About. The signed 0.3.0 app was packaged
with a checksum. The browser signal matrix remains the recorded 0.2 runtime evidence;
the UI refinement does not claim a fresh four-route or long-duration browser run.

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
