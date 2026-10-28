# Browser routing and verification

## Current evidence

| Source | Receiver | Exclusion | Selection/model tests | Browser runtime |
| --- | --- | --- | --- | --- |
| Chrome | Chrome | Off | Passed | Passed, user-observed 2026-10-27 |
| Safari | Safari | Off | Passed | Passed, user-observed 2026-10-27 |
| Chrome | Safari | Off | Passed | Passed, user-observed 2026-10-27 |
| Safari | Chrome | Off | Passed | Passed, user-observed 2026-10-27 |

Runtime results are from the bundled offline tone/receiver pages on an M2 with
macOS 27.0.1. These are non-silent input checks, not saved-recording, multi-hour
drift, every-site, or every-browser-version guarantees. Browser automation was
unavailable; the user performed and reported all four checks. Chromium and Safari
API mocks test compatibility branches separately and do not count as runtime evidence.
Installed versions were Chrome 156.0.8078.49 and Safari 27.0.1. The exact capture
scope per route was not separately recorded; explicit source-model tests and the
earlier native selected-Safari test provide separate selection evidence.

## Reproduce each route

1. Start Macam with **Playback exclusion: Off**. Choose Whole system or the source
   browser explicitly. Use application selection for an isolation check.
2. From **Browser Audio Tests**, open the tone source in the source browser and the
   receiver in the destination browser. For same-browser routes, use separate tabs.
3. Stop every other test tone and the previous receiver session. Choose the route
   label in the destination page. Route metadata does not configure Macam.
4. Click Play test tone in the source. It plays 440 Hz left/660 Hz right through
   the current output and stops after two minutes. Normal playback remains audible.
5. Click Grant audio-input access in the destination, allow permission, then Connect
   Macam Audio. Confirm the track label, both channel meters, current peak/RMS,
   and `nonSilentInputVerified: true`. The permission button temporarily opens the
   browser's current input; actual test capture accepts only a verified Macam name.
6. Stop the tone and confirm the current meters return to silence. Stop/restart the
   receiver before the next route so an old non-silent counter cannot count as a pass.
7. Test optional recording separately. Inspect/play the saved result after stopping
   Macam capture; verify channel independence, content, and timing.

Keep receiving-app monitoring off. Core Audio taps identify applications/processes,
not web origins or tabs. A browser's receiving tab cannot be excluded independently
of its source tab. Enabling exclusion for that browser removes both from capture.

## Lifecycle and permissions

Test Macam Stop/Start and browser restart independently. Stop removes the input
and may end the browser track; source changes update the existing tap in place.
The test receiver retries only the known Macam device ID, never a different input.
If the browser hides IDs or permission expires, Grant access → Connect may be needed.
The earlier Chrome diagnostic passed automatic Stop/Start reconnection; Safari
receiver restart behavior has not yet been verified.

Browser device labels may be `Macam Audio`, `Macam Audio (Aggregate)`, or the
equivalent aggregate-device qualifier handled by the test receiver. Some privacy
settings hide enumeration details even while a named track is live. The page can
reuse that verified authorized track without inventing a device ID.

Safari may not support querying microphone permission through the Permissions API;
the diagnostic reports `unavailable` and continues through getUserMedia. Web Audio
is resumed from the Connect click. Recording MIME types are feature-detected; MP4
is available as a fallback instead of assuming WebM support. See WebKit's
[MediaRecorder documentation](https://webkit.org/blog/11353/mediarecorder-api/) and
[Safari media updates](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/).

## Submit new evidence

Include OS/browser versions, route, Macam sources/exclusion, permission state,
observed device name, signal values, lifecycle steps, and any processing enabled
by the receiving website. Never describe a mock or an anonymous device listing as
proof of non-silent capture. Keep private recordings and device IDs out of issues.
