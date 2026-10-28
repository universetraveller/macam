# Macam — Mac Audio Mirror

**Mirror your Mac’s audio.**

Macam is a free, open-source macOS menu-bar utility that mirrors system or
selected-application playback into a stereo input named **Macam Audio**. Choose
that input in a recording, transcription, meeting, or other receiving application.
Original audio continues through the existing speakers or headphones.

- Whole-system and selected-application capture, including browser audio helpers.
- Chrome and Safari as sources and receivers, including two tabs in one browser.
- **Playback exclusion is optional and Off by default.** Macam always excludes itself.
- Manual Start/Stop, source selection, status, and input meter.
- Native Core Audio process tap and public input aggregate; no driver installation.
- Local-only: no networking, analytics, accounts, updates, login item, or app recording.

Macam is experimental. Runtime evidence and remaining limitations are recorded in
[verification](docs/verification.md), rather than inferred from compilation or mocks.

## Browser routing

| Audio source | Receiving web app | Macam source | Playback exclusion | Runtime result |
| --- | --- | --- | --- | --- |
| Chrome | Chrome | Whole system or Google Chrome | Off | Passed, user-observed on macOS 27.0.1 |
| Safari | Safari | Whole system or Safari | Off | Passed, user-observed on macOS 27.0.1 |
| Chrome | Safari | Whole system or Google Chrome | Off | Passed, user-observed on macOS 27.0.1 |
| Safari | Chrome | Whole system or Safari | Off | Passed, user-observed on macOS 27.0.1 |

In the receiving web app, select **Macam Audio**. Browsers may display a qualified
name such as **Macam Audio (Aggregate)**. Grant the browser/site microphone
permission; virtual inputs use the same browser permission as microphones.

Capture is per application, **not per browser tab**. Selecting Chrome captures
playing audio across its tabs/profiles, and selecting Safari includes its associated
audio helpers. A receiving tab's playback is included when its browser is a source.
Keep input monitoring/play-through off in the receiver to avoid feeding captured
audio back into itself. Macam never plays the captured copy through speakers.

To exclude an application's playback deliberately, use **Playback exclusion** and
choose that application or **All browsers**. This excludes the entire application
family, including its source tabs. Do not exclude the source browser for any of
the four routes above. Turning exclusion Off allows that browser as a source again.
All browsers conservatively excludes shared WebKit helpers too, which can include
embedded web content in other applications.

## Build and run

Runtime target: macOS 14.2+. The current source requires Apple Command Line Tools
with a macOS 26+ SDK. Swift/clang compile the app directly; the Xcode IDE and an
Xcode project are unnecessary. Runtime tests currently cover Apple Silicon on
macOS 27.0.1; other deployment targets remain unverified.

If Command Line Tools are missing:

```sh
xcode-select --install
```

From a checkout:

```sh
./scripts/build.sh
./scripts/run.sh
```

The output is `.build/Macam.app`, bundle ID `org.macam.Macam`, locally ad-hoc signed.
It launches **stopped**. Quit Macam before rebuilding or copying the app to a new
location. Keep the app at a consistent location for permissions. Existing local
signing identities can be selected without changing the build:

```sh
MACAM_SIGN_IDENTITY='Signing identity name' ./scripts/build.sh
```

Signing uses no timestamp service. Ad-hoc signatures change after rebuilding and
macOS may require capture permission again. Local packages are not notarized.

## Use

1. Open Macam's waveform menu and choose Whole system or source applications.
   A dot marks an application currently producing audio.
2. Leave **Playback exclusion: Off** unless you deliberately want to exclude an app.
3. Click **Start** and allow System Audio Recording when prompted. Macam's own
   meter reads its virtual input, not a physical microphone.
4. Select Macam Audio in the receiving application and grant its input permission.
   Disable noise suppression, echo cancellation, and automatic gain where appropriate.
5. Check the source, Macam, and receiving-app meters. Stop/Quit removes Macam's input.

Stopping removes the device and can end a receiver's input stream. After restarting,
the receiver may reconnect automatically, need its input reselected, or need its
capture permission renewed. Refreshing or reconnecting is controlled by the receiving
application. Source-selection changes update the tap without replacing the input.

Version 0.2 intentionally ignores the old implicit Chrome `receiver` preference.
Existing source choices remain; playback exclusion starts Off. Any desired exclusion
must be chosen explicitly in the new menu.

## Offline browser tests

The **Browser Audio Tests** menu opens the receiver and tone source in the default
browser, Chrome, or Safari. No web server, external assets, or network requests are
used. These are ordinary local files:

- [ReceiverTest.html](Resources/ReceiverTest.html): input selector, stereo meters,
  permission/device diagnostics, reconnect handling, optional ten-second recording.
- [ToneSource.html](Resources/ToneSource.html): a quiet stereo tone (440 Hz left,
  660 Hz right), stopped manually or after two minutes.

Open the tone page in the source browser and the receiver page in the receiving
browser. Choose the route label, start only the source tone, then Grant access →
Connect Macam Audio. Look for `nonSilentInputVerified: true`. Stop the receiver
between routes so previous non-silent measurements do not count toward a new test.
The route label describes the test; it does not configure the app or browsers.

The permission button may open the browser's current input for up to 30 seconds
while revealing device names. This permission track is never recorded or monitored
and closes when switching to Macam Audio or pressing Stop. If the browser hides
device IDs, an already-authorized live track with the verified Macam name can be
used. Reconnection never silently falls back to a physical/default microphone.

The receiver resumes Web Audio from a user gesture, tolerates unavailable microphone
permission queries, and selects a supported MediaRecorder type at runtime (WebM or
MP4). Optional recordings stay in memory until explicitly saved. The Macam app has
no recording feature. The receiver never plays its input.

## Development and checks

```sh
./scripts/test.sh
./scripts/package.sh
```

The test script compiles/signs the app, runs sanitized C meter tests, tests source
selection and migration, and runs browser API mocks when Node.js is installed.
Node is optional for building/running Macam; CI requires it for the JS checks.
Mocked Chromium/Safari tests are not real-browser interoperability results.

Diagnostics are read-only except for their own Macam resources:

```sh
.build/Macam.app/Contents/MacOS/Macam --inspect
.build/Macam.app/Contents/MacOS/Macam --processes
.build/Macam.app/Contents/MacOS/Macam --probe 30 --source com.google.Chrome
# In another terminal while the probe runs:
.build/Macam.app/Contents/MacOS/Macam --read 10
```

Explicit opt-in exclusion: `--exclude com.apple.Safari`. The default is none;
`--exclude none` clears it. `--receiver` remains a legacy alias for an explicit
exclusion. Diagnostic owners are independent of saved menu-bar preferences.

With a continuously playing source and menu-bar capture stopped:

```sh
python3 scripts/verify.py --seconds 120 --source com.apple.Safari
.build/Macam.app/Contents/MacOS/Macam --exercise-updates --source com.apple.Safari
```

The native suite checks independent capture, continuity, settings, source isolation,
termination, crash cleanup, and restart. Reports stay in ignored `.build/verification/`.
Run it outside restricted command sandboxes: an empty device list is an error.
CI builds and runs deterministic tests; it does not grant TCC or test live audio.

## Architecture and system changes

An **unmuted public Core Audio process tap** feeds a **public tap-only aggregate
input**. There are no physical subdevices, output streams, or replay callbacks.
Macam does not select default devices or write device volumes, mute states, hardware
sample rates, or routing preferences. Its only Core Audio property write updates
its own tap description. No BlackHole, HAL plugin, root service, or Multi-Output
Device is installed or required.

Start creates the tap and Macam Audio; Stop/Quit tears down callbacks, aggregate,
and tap. An exclusive lock and exact-UUID ownership journal under
`~/Library/Application Support/Macam/` support crash recovery. Source and exclusion
preferences use `org.macam.Macam`; macOS stores permission grants and temporary
aggregate configuration. Macam never restores old default/volume snapshots over
the user's changes.

If cleanup was interrupted, stop other Macam owners and run:

```sh
.build/Macam.app/Contents/MacOS/Macam --cleanup
```

Recovery verifies journaled UUIDs and device composition; it refuses unverified or
modified resources. It never removes arbitrary devices based only on a similar name.

## Limits

- Application/helper capture does not provide per-tab isolation. Playback exclusion
  is a convenience, not a feedback isolation boundary.
- Helper discovery uses process-list notifications, periodic refresh, ancestry, app
  paths, and an optional guarded private responsibility lookup. Shared WebKit helpers
  are matched by resolved process IDs to avoid including unrelated applications.
  Detached helpers and relaunch behavior may vary by application/OS.
- Device/rate changes are observed without writing hardware settings. Stalled or
  incompatible streams trigger bounded recovery; receivers may need to reconnect.
- Sleep removes the input and wake recreates it if capture was active. Physical
  switching, sleep/wake, and multi-hour drift need further manual verification.
- Protected content may be silent; missing permission, idle sources, or an explicit
  exclusion can also cause silence. Browser processing may change stereo or levels.
- Other local audio clients can enumerate Macam Audio while it is active, subject
  to macOS permissions. Stop capture when it is no longer needed.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md), [SUPPORT.md](SUPPORT.md),
[SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md), and
[the browser verification matrix](docs/browser-testing.md).

GPL-3.0-only: [LICENSE](LICENSE), [third-party attribution](THIRD_PARTY_NOTICES.md).
Architecture evidence and significant adaptations are in
[the implementation plan](docs/implementation-plan.md).
Primary API references are [Apple's process-tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
and [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription).
