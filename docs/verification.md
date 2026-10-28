# Actual verification

Test date: 2026-10-27. These are local results, not claims about every macOS
version, website, protected content, or multi-hour recordings.

## Environment and build

- Apple M2, arm64; macOS 27.0.1 (26A434).
- Command Line Tools: `/Library/Developer/CommandLineTools`, package
  `27.0.0.0.1788430756`; Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple clang 21.0.0
  (`clang-2100.3.34.2`), macOS SDK 27.0.
- Built with `swiftc`/`clang`, without the Xcode IDE or package downloads.
- `.build/Macam.app`, bundle ID `org.macam.Macam`, ad-hoc signed.
  Code-signature verification and Info.plist validation passed.

The command sandbox hides Core Audio and returns an empty device list. Actual
audio tests ran outside it with authorization. Empty snapshots are rejected.

## Architecture conclusion

### 0.2 browser routing update

Playback exclusion now defaults to Off and is an explicit opt-in; old implicit
Chrome defaults are ignored on preference migration. Source choices are retained.
Macam remains self-excluded. The updated menu opens browser-neutral tone/receiver
pages in Chrome, Safari, or the default browser.

The user reported **all four routes passing** on 2026-10-27:
Chrome → Chrome, Safari → Safari, Chrome → Safari, Safari → Chrome, with playback
exclusion Off. Installed browser versions: Chrome 156.0.8078.49, Safari 27.0.1.
These are non-silent input checks with a playing source; the per-route choice of
Whole system versus selected-app capture was not separately recorded.
See [the public browser matrix](browser-testing.md).

New local checks passed for optional exclusion, old-preference migration, all four
source/receiver combinations, Chromium/Safari API mocks (including missing permission
queries and MP4 fallback), and tone-source graph/Stop behavior. They supplement the
user-observed browser tests. The new CI workflow is prepared but has not been run
on GitHub. The original 0.1 native/browser evidence below remains historical.

Final 0.2 packaging checks passed: full local test script, YAML parsing, signature
and plist validation, bundled-page/source equality, ZIP checksum, and a three-second
native Start/Stop with exclusion Off. That lifecycle-only check allowed silence,
delivered 143,872 frames with zero sample-time discontinuities, preserved all
snapshotted settings, removed the input, and reported no cleanup errors. The final
app was launched stopped. Artifacts: `.build/Macam-0.2.0-arm64.zip` and its SHA-256
sidecar; `.build/Macam.zip` is the convenience alias.

### Native architecture and original 0.1 results

**Option A works on this machine.** An unmuted public stereo process tap feeds a
public tap-only aggregate named **Macam Audio**. It provides stereo Float32 PCM
input at 48 kHz, with no physical subdevice, output callback, or replay. The tap
provides the clock. `tapautostart` is omitted because the SDK requires a private
aggregate for that key.

**Initial Google Chrome capture was verified by the user in their real receiving
application**, with non-silent input and normal original playback. The user then
verified non-silent capture and automatic Stop/Start reconnection in the corrected
offline diagnostic (v4). Browser observations are user-reported; automated browser
control was unavailable. The optional MediaRecorder download was not confirmed.

The initial page appeared to expose no inputs. Its diagnostics revealed a live
authorized track labeled **Macam Audio (Aggregate)** while `enumerateDevices()`
returned only an anonymous placeholder with no device ID. The initial page required
an exact “Macam Audio” label and a publicly enumerated device ID. The corrected
page accepts the observed qualified label and can consume that already-authorized
verified track directly. Permission streams remain active until switching, Stop,
or timeout. This was a diagnostic-page compatibility failure; the live track proved
Chrome had opened Macam's input. No change to system device settings was needed.

BlackHole 2ch already existed on this Mac. Macam did not open, configure, route
through, or install it. Options B and C were unnecessary and are not implemented.

## Audio and lifecycle results

| Check | Actual result |
| --- | --- |
| Independent enumeration | Separate process opened Macam Audio by UID as stereo 48 kHz Float32 input. |
| Initial whole-system capture | Owner: 30 s, 1,440,256 frames; receiver: 8 s, 384,000 frames, 767,531 nonzero samples. Zero sample-time discontinuities. |
| Selected Safari capture | Receiver: 120.0036 s, 5,760,000 frames, 11,520,000 samples, 2,770,525 nonzero samples, zero sample-time discontinuities. Owner: 123.0024 s, 5,903,872 frames, same nonzero count. |
| Empty source isolation | Nonexistent selected bundle yielded zero nonzero samples. |
| Live selection updates | Empty → Terminal test tone → empty: 0 → 383,855 → 0 new nonzero samples after settling. Device ID stayed constant; settings matched. |
| Settings preservation | Default input/output/system-output UIDs and all readable main/channel volume/mute properties on unrelated devices matched before, during, and after automated tests. A snapshot while the menu-bar app was actively capturing also matched. |
| SIGTERM | Clean teardown of callbacks, aggregate, and tap; settings preserved. |
| SIGKILL/recovery | Force-killing the suite's own process left the public aggregate. Exact-journal recovery removed it, and restart succeeded. |
| Repeated sessions | Owners created/removed the input successfully; independent receivers opened it across sessions. |
| Final packaged build | Three-second lifecycle regression delivered 144,384 frames, zero sample-time discontinuities, unchanged settings, successful input removal, and no cleanup errors. Silence was explicitly allowed in this lifecycle-only check. |
| Meter tests | Interleaved/planar stereo, non-finite values, null buffers, timestamp gaps, and untouched output passed under address/undefined-behavior sanitizers. |
| Selection regression | Safari/Mail shared WebKit helpers remained separate; multiple sources and self/Chrome/all-browser exclusion passed. |
| Chrome | Initial real-app capture succeeded with normal playback. Corrected v4 page received non-silent audio and automatically resumed after Macam Stop/Start, confirmed by the user. |
| Browser page | Qualified names and hidden device IDs are handled using a verified live track. Mocked temporary-permission, qualified-name, anonymous-enumeration, exact-input, reconnect, and Stop regression tests pass. These mocks supplement the user test. |

The final build passed the full local test script, code-signature and plist
validation, browser-script syntax, and bundled-page/source equality checks. It is
also packaged as `.build/Macam.zip`. The final menu-bar app was launched stopped.

The [archived native suite summary](verification-native.json) is the actual
two-minute run's output. Its `browserVerified: false` and
`physicalControlsVerified: false` describe the automated suite; the user's Chrome
result above is separate evidence. Detailed settings snapshots remain in ignored
`.build/verification/`.
Additional user-reported browser results are archived in
[verification-browser.json](verification-browser.json).

The two-minute run preceded the shared-WebKit helper-isolation refinement. The
live selection and selection-regression tests passed after that refinement.
Audio was active for part of the long run and silent at the end: final peak/RMS
describe the last callback. Future diagnostics also report `maximumPeak`.
Zero sample-time gaps establishes callback continuity, not a proof against audible
glitches or multi-hour drift relative to a hardware reference clock.

## Remaining manual checks

- [ ] Normal volume keys and headphone unplug/reconnect during capture.
- [ ] Output sample-rate changes, Bluetooth profile changes, USB audio devices.
- [ ] Sleep/wake and browser restart, including reconnecting an ended input track.
- [ ] Saved recording in the actual receiving website; stereo independence and
  effects of its echo cancellation, noise suppression, and automatic gain.
- [ ] Multi-hour reference recording for audible dropouts and clock drift.
- [ ] Source/helper relaunches for each app, including detached/shared XPC helpers.
- [ ] Denied/revoked permissions and ad-hoc signature changes after a rebuild/move.
- [ ] Runtime compatibility on macOS 14.2–26. Those are deployment targets, not
  verified operating systems.

If a user changes volume or output during a manual test, preserve that choice.
Never restore old snapshots. Automated settings comparisons assume no user changes.

## Reproduce

`./scripts/test.sh` checks the build, sanitizer meter tests, and source isolation.
With capture stopped in the menu-bar app and audio playing in Safari, run outside
a restricted command sandbox:

```sh
python3 scripts/verify.py --seconds 120 --source com.apple.Safari
.build/Macam.app/Contents/MacOS/Macam --exercise-updates --source com.apple.Safari
```

The second command tests an empty selection, four seconds of selected capture,
and silence after deselection without replacing the public input. Use Macam's
**Browser Audio Tests** menu for browser verification.
